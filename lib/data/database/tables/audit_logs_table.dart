part of '../app_database.dart';

/// Tabel audit log — mencatat setiap aksi penting di sistem.
/// Tidak boleh dihapus oleh kasir maupun admin biasa.
class AuditLogs extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// ID user yang melakukan aksi (nullable jika sistem yang melakukan)
  IntColumn get userId => integer().nullable()();

  /// Aksi yang dilakukan: 'login', 'logout', 'create_user', 'delete_user',
  /// 'reset_pin', 'change_role', 'update_settings', 'stock_adjustment',
  /// 'transaction_cancel', 'login_failed', 'account_locked'
  TextColumn get action => text()();

  /// ID entitas yang menjadi target (misal: userId yang dihapus)
  IntColumn get targetId => integer().nullable()();

  /// Deskripsi bebas
  TextColumn get description => text().withDefault(const Constant(''))();

  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();
}
