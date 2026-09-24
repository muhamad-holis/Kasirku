import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─── Google Auth HTTP Client ──────────────────────────────────────────────────

class _GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final http.Client _client = http.Client();

  _GoogleAuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _client.send(request..headers.addAll(_headers));
  }
}

// ─── State ────────────────────────────────────────────────────────────────────

enum BackupStatus { idle, loading, success, error }

class BackupState {
  final BackupStatus status;
  final String? message;
  final DateTime? lastBackup;
  final bool isConnected;
  final String? connectedEmail;

  const BackupState({
    this.status = BackupStatus.idle,
    this.message,
    this.lastBackup,
    this.isConnected = false,
    this.connectedEmail,
  });

  BackupState copyWith({
    BackupStatus? status,
    String? message,
    DateTime? lastBackup,
    bool? isConnected,
    String? connectedEmail,
  }) => BackupState(
    status: status ?? this.status,
    message: message ?? this.message,
    lastBackup: lastBackup ?? this.lastBackup,
    isConnected: isConnected ?? this.isConnected,
    connectedEmail: connectedEmail ?? this.connectedEmail,
  );
}

// ─── Notifier ─────────────────────────────────────────────────────────────────

const _kLastBackup = 'last_backup_time';
const _kBackupFileName = 'kasirku_backup.db';
const _kFolderName = 'KasirkuBackup';

class BackupNotifier extends StateNotifier<BackupState> {
  BackupNotifier() : super(const BackupState()) {
    _init();
  }

  final _googleSignIn = GoogleSignIn(
    scopes: [drive.DriveApi.driveFileScope],
  );

  Future<void> _init() async {
    // Cek apakah sudah pernah login Google sebelumnya
    final account = await _googleSignIn.signInSilently();
    if (account != null) {
      final prefs = await SharedPreferences.getInstance();
      final lastTs = prefs.getInt(_kLastBackup);
      state = state.copyWith(
        isConnected: true,
        connectedEmail: account.email,
        lastBackup: lastTs != null
            ? DateTime.fromMillisecondsSinceEpoch(lastTs)
            : null,
      );
    }
  }

  // ── Connect Google Drive ───────────────────────────────────────────────────
  Future<void> connectGoogle() async {
    state = state.copyWith(status: BackupStatus.loading, message: 'Menghubungkan...');
    try {
      final account = await _googleSignIn.signIn();
      if (account == null) {
        state = state.copyWith(status: BackupStatus.idle, message: 'Dibatalkan');
        return;
      }
      state = state.copyWith(
        status: BackupStatus.success,
        isConnected: true,
        connectedEmail: account.email,
        message: 'Berhasil terhubung ke ${account.email}',
      );
    } catch (e) {
      state = state.copyWith(
        status: BackupStatus.error,
        message: 'Gagal menghubungkan: $e',
      );
    }
  }

  // ── Disconnect Google Drive ────────────────────────────────────────────────
  Future<void> disconnectGoogle() async {
    await _googleSignIn.signOut();
    state = const BackupState();
  }

  // ── Backup ke Google Drive ─────────────────────────────────────────────────
  Future<void> backupNow() async {
    state = state.copyWith(
        status: BackupStatus.loading, message: 'Membackup data...');
    try {
      final account = await _googleSignIn.signInSilently() ??
          await _googleSignIn.signIn();
      if (account == null) {
        state = state.copyWith(
            status: BackupStatus.error, message: 'Silakan hubungkan Google terlebih dahulu');
        return;
      }

      final auth = await account.authentication;
      final authClient = _GoogleAuthClient({
        'Authorization': 'Bearer ${auth.accessToken}',
      });
      final driveApi = drive.DriveApi(authClient);

      // Cari atau buat folder KasirkuBackup
      final folderId = await _getOrCreateFolder(driveApi);

      // Ambil file database lokal
      final dbFile = await _getDbFile();
      if (!await dbFile.exists()) {
        state = state.copyWith(
            status: BackupStatus.error, message: 'File database tidak ditemukan');
        return;
      }

      // Cek apakah file backup sudah ada → update, jika tidak → create
      final existingId = await _findExistingBackup(driveApi, folderId);
      final media = drive.Media(dbFile.openRead(), await dbFile.length());

      if (existingId != null) {
        // Update file yang sudah ada
        await driveApi.files.update(
          drive.File()..name = _kBackupFileName,
          existingId,
          uploadMedia: media,
        );
      } else {
        // Buat file baru
        await driveApi.files.create(
          drive.File()
            ..name = _kBackupFileName
            ..parents = [folderId],
          uploadMedia: media,
        );
      }

      final now = DateTime.now();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kLastBackup, now.millisecondsSinceEpoch);

      state = state.copyWith(
        status: BackupStatus.success,
        lastBackup: now,
        message: 'Backup berhasil!',
      );
    } catch (e) {
      state = state.copyWith(
          status: BackupStatus.error, message: 'Backup gagal: $e');
    }
  }

  // ── Restore dari Google Drive ──────────────────────────────────────────────
  Future<void> restoreFromDrive() async {
    state = state.copyWith(
        status: BackupStatus.loading, message: 'Mengambil data backup...');
    try {
      final account = await _googleSignIn.signInSilently() ??
          await _googleSignIn.signIn();
      if (account == null) {
        state = state.copyWith(
            status: BackupStatus.error, message: 'Silakan hubungkan Google terlebih dahulu');
        return;
      }

      final auth = await account.authentication;
      final authClient = _GoogleAuthClient({
        'Authorization': 'Bearer ${auth.accessToken}',
      });
      final driveApi = drive.DriveApi(authClient);

      final folderId = await _getOrCreateFolder(driveApi);
      final existingId = await _findExistingBackup(driveApi, folderId);

      if (existingId == null) {
        state = state.copyWith(
            status: BackupStatus.error,
            message: 'Tidak ada backup di Google Drive');
        return;
      }

      // BUG-02 FIX: Download ke file TEMPORARY dulu, baru rename atomic.
      // Menulis langsung ke kasirku.db yang sedang terbuka oleh Drift
      // dapat menyebabkan korupsi data karena SQLite WAL masih aktif.
      // Dengan rename atomic, file lama tidak tersentuh sampai download selesai
      // sempurna — jika download gagal di tengah jalan, data lama tetap aman.
      final response = await driveApi.files.get(
        existingId,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ) as drive.Media;

      final dbFile  = await _getDbFile();
      final tempFile = File('${dbFile.path}.restore_tmp');

      // 1. Download ke file temporary
      final sink = tempFile.openWrite();
      await response.stream.pipe(sink);
      await sink.close();

      // 2. Rename atomic: timpa kasirku.db dengan file temporary
      //    Drift akan mendeteksi perubahan saat aplikasi di-restart.
      await tempFile.rename(dbFile.path);

      state = state.copyWith(
        status: BackupStatus.success,
        message: 'Restore berhasil! Harap restart aplikasi untuk menerapkan perubahan.',
      );
    } catch (e) {
      state = state.copyWith(
          status: BackupStatus.error, message: 'Restore gagal: $e');
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  Future<String> _getOrCreateFolder(drive.DriveApi api) async {
    final result = await api.files.list(
      q: "name='$_kFolderName' and mimeType='application/vnd.google-apps.folder' and trashed=false",
      spaces: 'drive',
      $fields: 'files(id)',
    );
    if (result.files != null && result.files!.isNotEmpty) {
      return result.files!.first.id!;
    }
    final folder = await api.files.create(
      drive.File()
        ..name = _kFolderName
        ..mimeType = 'application/vnd.google-apps.folder',
    );
    return folder.id!;
  }

  Future<String?> _findExistingBackup(
      drive.DriveApi api, String folderId) async {
    final result = await api.files.list(
      q: "name='$_kBackupFileName' and '$folderId' in parents and trashed=false",
      spaces: 'drive',
      $fields: 'files(id)',
    );
    if (result.files != null && result.files!.isNotEmpty) {
      return result.files!.first.id;
    }
    return null;
  }

  Future<File> _getDbFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/kasirku.db');
  }
}

final backupProvider =
    StateNotifierProvider<BackupNotifier, BackupState>(
  (ref) => BackupNotifier(),
);
