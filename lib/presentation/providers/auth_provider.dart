// lib/presentation/providers/auth_provider.dart
//
// SECURITY PATCH:
// - HAPUS _initDefaultAdmin() yang membuat admin dengan PIN 1234
// - Login via username unik (bukan name), pakai attemptLogin() yang rate-limited
// - Session disimpan di flutter_secure_storage, bukan SharedPreferences
// - needsSetupProvider: trigger Setup Wizard saat DB kosong
// - allUsersProvider: provider-level admin check

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/database/app_database.dart';
import '../../core/utils/secure_session.dart';
import '../../core/utils/pin_hasher.dart';
import 'database_provider.dart';

/// Re-export agar screen lain tidak perlu import pin_hasher langsung
String hashPin(String pin) => PinHasher.hashPin(pin);

// ─── Model user aktif ──────────────────────────────────────────────────────────

class ActiveUser {
  final int id;
  final String username;
  final String displayName;
  final String role;
  final bool mustChangePin;

  const ActiveUser({
    required this.id,
    required this.username,
    required this.displayName,
    required this.role,
    this.mustChangePin = false,
  });

  bool get isAdmin => role == 'admin';

  /// Nama tampilan untuk UI
  String get name => displayName;
}

// ─── Auth Notifier ─────────────────────────────────────────────────────────────

class AuthNotifier extends StateNotifier<ActiveUser?> {
  AuthNotifier(this._ref) : super(null);
  // KODE DIHAPUS: _initDefaultAdmin() → tidak ada lagi admin default PIN 1234
  // Admin pertama dibuat via SetupWizardScreen

  final Ref _ref;
  AppDatabase get _db => _ref.read(databaseProvider);

  /// Login via USERNAME + PIN mentah (bukan via name).
  /// PIN diverifikasi terhadap hash PBKDF2 di attemptLogin().
  /// Return null = sukses. Return string = pesan error.
  Future<String?> login(String username, String pin) async {
    final result = await _db.usersDao.attemptLogin(username, pin);
    if (!result.isSuccess) return result.errorMessage;

    final user = result.user!;
    state = ActiveUser(
      id: user.id,
      username: user.username,
      displayName: user.displayName,
      role: user.role,
      mustChangePin: user.mustChangePin,
    );

    // Simpan session ke SecureStorage (bukan SharedPreferences)
    await SecureSession.saveSession(
      userId: user.id,
      username: user.username,
      displayName: user.displayName,
      role: user.role,
    );
    return null;
  }

  /// Restore session setelah biometrik berhasil.
  /// WAJIB verifikasi ke DB (cegah session stale / user sudah dinonaktifkan).
  Future<bool> restoreSession(SavedSession saved) async {
    final user = await _db.usersDao.getUserById(saved.userId);
    if (user == null || !user.isActive) {
      await SecureSession.clearSession();
      return false;
    }
    state = ActiveUser(
      id: user.id,
      username: user.username,
      displayName: user.displayName,
      role: user.role,
      mustChangePin: user.mustChangePin,
    );
    return true;
  }

  Future<void> logout() async {
    final userId = state?.id;
    state = null;
    await SecureSession.clearSession();
    if (userId != null) {
      try {
        await _db.customStatement(
          "INSERT INTO audit_logs (user_id, action, description) "
          "VALUES ($userId, 'logout', 'User logout')",
        );
      } catch (_) {}
    }
  }

  /// Clear flag mustChangePin setelah user berhasil ganti PIN sendiri.
  void clearMustChangePin() {
    if (state == null) return;
    state = ActiveUser(
      id: state!.id,
      username: state!.username,
      displayName: state!.displayName,
      role: state!.role,
      mustChangePin: false,
    );
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, ActiveUser?>(
  (ref) => AuthNotifier(ref),
);

// ─── Derived providers ─────────────────────────────────────────────────────────

/// Shortcut: apakah user yang login adalah admin?
final isAdminProvider = Provider<bool>((ref) {
  return ref.watch(authProvider)?.isAdmin ?? false;
});

/// Apakah DB butuh Setup Wizard? (tidak ada user sama sekali)
final needsSetupProvider = FutureProvider<bool>((ref) {
  return ref.read(databaseProvider).needsSetup();
});

/// Daftar semua user. DIPROTEKSI: hanya admin yang dapat mengakses.
/// Jika kasir mengakses, throw UnauthorizedException.
final allUsersProvider = FutureProvider.autoDispose<List<User>>((ref) async {
  final isAdmin = ref.watch(isAdminProvider);
  if (!isAdmin) {
    throw UnauthorizedException(
        'allUsersProvider: hanya dapat diakses oleh admin');
  }
  return ref.read(databaseProvider).usersDao.getActiveUsers();
});
