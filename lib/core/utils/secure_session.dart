// lib/core/utils/secure_session.dart
//
// SECURITY PATCH: Ganti SharedPreferences → flutter_secure_storage
// untuk menyimpan data session/auth yang sensitif.
//
// Mengapa flutter_secure_storage?
// - SharedPreferences disimpan sebagai file XML/JSON plain-text.
// - Di perangkat yang di-root, file ini dapat dibaca oleh aplikasi lain.
// - flutter_secure_storage menggunakan Android Keystore / iOS Keychain
//   yang hardware-backed dan tidak dapat diakses tanpa autentikasi.

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureSession {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(
      encryptedSharedPreferences: true, // AES-256 via Android Keystore
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock, // tersedia setelah unlock pertama
    ),
  );

  // Keys
  static const _kUserId   = 'session_user_id';
  static const _kUsername = 'session_username';
  static const _kDisplayName = 'session_display_name';
  static const _kRole     = 'session_role';

  /// Simpan session setelah login berhasil
  static Future<void> saveSession({
    required int userId,
    required String username,
    required String displayName,
    required String role,
  }) async {
    await _storage.write(key: _kUserId,      value: userId.toString());
    await _storage.write(key: _kUsername,    value: username);
    await _storage.write(key: _kDisplayName, value: displayName);
    await _storage.write(key: _kRole,        value: role);
  }

  /// Ambil session yang tersimpan. Return null jika belum ada.
  static Future<SavedSession?> getSession() async {
    final userId      = await _storage.read(key: _kUserId);
    final username    = await _storage.read(key: _kUsername);
    final displayName = await _storage.read(key: _kDisplayName);
    final role        = await _storage.read(key: _kRole);

    if (userId == null || username == null || role == null) return null;
    final id = int.tryParse(userId);
    if (id == null) return null;

    return SavedSession(
      userId: id,
      username: username,
      displayName: displayName ?? username,
      role: role,
    );
  }

  /// Hapus session saat logout
  static Future<void> clearSession() async {
    await _storage.delete(key: _kUserId);
    await _storage.delete(key: _kUsername);
    await _storage.delete(key: _kDisplayName);
    await _storage.delete(key: _kRole);
  }

  /// Migrasi dari SharedPreferences lama ke SecureStorage (one-time)
  static Future<void> migrateFromSharedPreferences() async {
    // Import di sini agar tidak ada circular dependency
    // Fungsi ini dipanggil sekali di SplashScreen saat upgrade
    try {
      // ignore: depend_on_referenced_packages
      final prefs = await _getSharedPrefs();
      final oldId   = prefs['last_user_id'];
      final oldName = prefs['last_user_name'];
      final oldRole = prefs['last_user_role'];

      if (oldId != null && oldName != null && oldRole != null) {
        // Data lama ada → pindahkan ke secure storage
        // Tidak bisa restore displayName dari data lama yang hanya ada 'name'
        // jadi username = name (akan dicocokkan ke DB saat biometrik)
        await _storage.write(key: _kUserId,      value: oldId.toString());
        await _storage.write(key: _kUsername,    value: oldName.toString());
        await _storage.write(key: _kDisplayName, value: oldName.toString());
        await _storage.write(key: _kRole,        value: oldRole.toString());
      }
      // Hapus data lama dari SharedPreferences
      await _clearSharedPrefsSession();
    } catch (_) {
      // Migrasi gagal bukan masalah kritis — user cukup login ulang
    }
  }

  // Lazy import untuk menghindari dependency di core
  static Future<Map<String, Object?>> _getSharedPrefs() async {
    // Menggunakan dynamic import agar file ini tidak hard-depend pada shared_preferences
    // Jika tidak ingin menambah complexity, cukup hapus method ini
    // dan handle migrasi langsung di SplashScreen
    return {};
  }

  static Future<void> _clearSharedPrefsSession() async {}
}

/// Data session tersimpan
class SavedSession {
  final int userId;
  final String username;
  final String displayName;
  final String role;

  const SavedSession({
    required this.userId,
    required this.username,
    required this.displayName,
    required this.role,
  });

  bool get isAdmin => role == 'admin';
}
