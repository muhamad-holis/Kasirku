part of '../app_database.dart';

/// SECURITY PATCH v2:
/// - Tambah kolom `username` (UNIQUE) sebagai identifier login
/// - Tambah kolom `display_name` untuk tampilan UI
/// - Tambah kolom `failed_attempts` & `locked_until` untuk rate-limit brute-force
/// - Tambah kolom `must_change_pin` untuk paksa ganti PIN saat pertama login
/// - Ganti PIN minimum 4 → 6 digit (divalidasi di layer aplikasi)
class Users extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Username unik — dipakai untuk login. Tidak boleh duplikat.
  TextColumn get username => text().unique()();

  /// Nama tampilan (boleh duplikat, hanya untuk UI)
  TextColumn get displayName => text()();

  TextColumn get pin => text()();
  TextColumn get role => text().withDefault(const Constant('kasir'))();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  /// Jumlah gagal login berturut-turut (reset saat login berhasil)
  IntColumn get failedAttempts =>
      integer().withDefault(const Constant(0))();

  /// Timestamp (milis) sampai kapan akun terkunci. Null = tidak terkunci.
  IntColumn get lockedUntil => integer().nullable()();

  /// Apakah user WAJIB ganti PIN di login berikutnya?
  BoolColumn get mustChangePin =>
      boolean().withDefault(const Constant(false))();

  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
}
