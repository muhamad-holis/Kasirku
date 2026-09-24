part of '../app_database.dart';

// ─── Login Result ──────────────────────────────────────────────────────────────

class LoginResult {
  final bool isSuccess;
  final User? user;
  final String? errorMessage;

  const LoginResult._({required this.isSuccess, this.user, this.errorMessage});

  factory LoginResult.success(User user) =>
      LoginResult._(isSuccess: true, user: user);

  factory LoginResult.failure(String message) =>
      LoginResult._(isSuccess: false, errorMessage: message);
}

// ─── Custom Exceptions ─────────────────────────────────────────────────────────

class UnauthorizedException implements Exception {
  final String message;
  const UnauthorizedException(this.message);
  @override
  String toString() => 'UnauthorizedException: $message';
}

class LastAdminException implements Exception {
  const LastAdminException();
  @override
  String toString() => 'LastAdminException: Tidak bisa menghapus admin terakhir';
}

class UsernameTakenException implements Exception {
  final String username;
  const UsernameTakenException(this.username);
  @override
  String toString() => 'UsernameTakenException: Username "$username" sudah dipakai';
}

// ─── DAO ───────────────────────────────────────────────────────────────────────

@DriftAccessor(tables: [Users])
class UsersDao extends DatabaseAccessor<AppDatabase> with _$UsersDaoMixin {
  UsersDao(super.db);

  // ── Queries ────────────────────────────────────────────────────────────────

  Future<List<User>> getAllUsers() =>
      (select(users)..orderBy([(u) => OrderingTerm.asc(u.displayName)])).get();

  Future<List<User>> getActiveUsers() =>
      (select(users)
        ..where((u) => u.isActive.equals(true))
        ..orderBy([(u) => OrderingTerm.asc(u.displayName)]))
          .get();

  Future<User?> getUserById(int id) =>
      (select(users)..where((u) => u.id.equals(id))).getSingleOrNull();

  Future<User?> getUserByUsername(String username) =>
      (select(users)..where((u) => u.username.equals(username))).getSingleOrNull();

  // ── needsSetup: true jika belum ada user ──────────────────────────────────

  Future<bool> needsSetup() async {
    final list = await (select(users)).get();
    return list.isEmpty;
  }

  // ── Cek username unik (exclude id tertentu saat edit) ─────────────────────

  Future<void> _checkUsernameTaken(String username, {int? excludeId}) async {
    final existing = await getUserByUsername(username);
    if (existing != null && existing.id != excludeId) {
      throw UsernameTakenException(username);
    }
  }

  // ── Insert first admin (Setup Wizard) ─────────────────────────────────────

  Future<int> insertFirstAdmin(UsersCompanion companion) async {
    final username = companion.username.value;
    await _checkUsernameTaken(username);
    return into(users).insert(companion);
  }

  // ── Insert kasir biasa (oleh admin) ───────────────────────────────────────

  Future<int> insertUser(UsersCompanion companion,
      {required int actorId}) async {
    final username = companion.username.value;
    await _checkUsernameTaken(username);
    final id = await into(users).insert(companion);
    await _audit(actorId, 'insert_user', 'Tambah user: $username');
    return id;
  }

  // ── Update user (oleh admin) ───────────────────────────────────────────────

  Future<bool> updateUser(UsersCompanion companion,
      {required int actorId}) async {
    final id       = companion.id.value;
    final username = companion.username.value;
    await _checkUsernameTaken(username, excludeId: id);
    final result = await update(users).replace(companion);
    await _audit(actorId, 'update_user', 'Edit user id: $id');
    return result;
  }

  // ── Soft delete dengan guard admin terakhir ────────────────────────────────

  Future<void> softDeleteUser(int id, {required int actorId}) async {
    final target = await getUserById(id);
    if (target == null) return;

    if (target.role == 'admin') {
      final admins = await (select(users)
        ..where((u) => u.role.equals('admin') & u.isActive.equals(true))).get();
      if (admins.length <= 1) throw const LastAdminException();
    }

    await (update(users)..where((u) => u.id.equals(id)))
        .write(const UsersCompanion(isActive: Value(false)));
    await _audit(actorId, 'delete_user', 'Hapus user: ${target.username}');
  }

  // ── Reset PIN oleh admin ───────────────────────────────────────────────────

  Future<void> adminResetPin(int targetId, String newHashedPin,
      {required int actorId}) async {
    await (update(users)..where((u) => u.id.equals(targetId))).write(
      UsersCompanion(
        pin:           Value(newHashedPin),
        mustChangePin: const Value(true),
        failedAttempts: const Value(0),
        lockedUntil:   const Value(null),
      ),
    );
    await _audit(actorId, 'reset_pin', 'Reset PIN user id: $targetId');
  }

  // ── Ganti PIN oleh user sendiri ────────────────────────────────────────────

  Future<void> changePin(int userId, String newHashedPin) async {
    await (update(users)..where((u) => u.id.equals(userId))).write(
      UsersCompanion(
        pin:            Value(newHashedPin),
        mustChangePin:  const Value(false),
        failedAttempts: const Value(0),
        lockedUntil:    const Value(null),
      ),
    );
  }

  // ── attemptLogin dengan rate-limit brute-force ─────────────────────────────

  static const int _maxAttempts  = 5;
  static const int _lockDuration = 5 * 60 * 1000; // 5 menit dalam ms

  /// [pin] adalah PIN MENTAH (plain text) dari input user — bukan hash.
  /// Verifikasi dilakukan di sini dengan PinHasher.verifyPin(),
  /// yang mendukung format hash lama (SHA-256) maupun baru (PBKDF2)
  /// serta otomatis upgrade hash lama ke PBKDF2 saat login berhasil.
  Future<LoginResult> attemptLogin(String username, String pin) async {
    final user = await getUserByUsername(username);

    if (user == null || !user.isActive) {
      return LoginResult.failure('Username atau PIN salah');
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    if (user.lockedUntil != null && user.lockedUntil! > now) {
      final sisaMenit = ((user.lockedUntil! - now) / 60000).ceil();
      return LoginResult.failure(
          'Akun terkunci. Coba lagi dalam $sisaMenit menit.');
    }

    // PBKDF2 (100.000 iterasi) cukup berat secara CPU — jalankan di isolate
    // terpisah lewat compute() agar UI tidak freeze/terasa "buffering"
    // saat tombol Masuk ditekan.
    final verify = await compute(verifyPinIsolate, PinVerifyArgs(pin, user.pin));

    if (!verify.match) {
      final attempts = user.failedAttempts + 1;
      final locked   = attempts >= _maxAttempts;
      await (update(users)..where((u) => u.id.equals(user.id))).write(
        UsersCompanion(
          failedAttempts: Value(locked ? 0 : attempts),
          lockedUntil:    Value(locked ? now + _lockDuration : null),
        ),
      );
      if (locked) {
        return LoginResult.failure(
            'Terlalu banyak percobaan. Akun terkunci 5 menit.');
      }
      final sisa = _maxAttempts - attempts;
      return LoginResult.failure('PIN salah. $sisa percobaan tersisa.');
    }

    // Berhasil — reset counter, dan upgrade hash jika perlu (legacy SHA-256/iterasi lama)
    await (update(users)..where((u) => u.id.equals(user.id))).write(
      UsersCompanion(
        failedAttempts: const Value(0),
        lockedUntil:    const Value(null),
        pin: verify.needsUpgrade
            ? Value(await compute(hashPinIsolate, PinHashArgs(pin)))
            : const Value.absent(),
      ),
    );

    return LoginResult.success(user);
  }

  // ── Helper audit log ───────────────────────────────────────────────────────

  Future<void> _audit(int userId, String action, String description) async {
    try {
      await attachedDatabase.customStatement(
        "INSERT INTO audit_logs (user_id, action, description) "
        "VALUES (?, ?, ?)",
        [userId, action, description],
      );
    } catch (_) {
      // Jangan crash karena gagal audit
    }
  }
}
