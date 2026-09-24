import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import '../../core/utils/pin_hasher.dart';

part 'tables/categories_table.dart';
part 'tables/products_table.dart';
part 'tables/customers_table.dart';
part 'tables/transactions_table.dart';
part 'tables/transaction_items_table.dart';
part 'tables/debts_table.dart';
part 'tables/stock_movements_table.dart';
part 'tables/cash_flows_table.dart';
part 'tables/settings_table.dart';
part 'tables/sync_queue_table.dart';
part 'tables/users_table.dart';
part 'tables/audit_logs_table.dart';
part 'tables/suppliers_table.dart';
part 'tables/manual_notas_table.dart';

part 'daos/products_dao.dart';
part 'daos/categories_dao.dart';
part 'daos/transactions_dao.dart';
part 'daos/customers_dao.dart';
part 'daos/debts_dao.dart';
part 'daos/reports_dao.dart';
part 'daos/sync_dao.dart';
part 'daos/stock_movements_dao.dart';
part 'daos/settings_dao.dart';
part 'daos/users_dao.dart';
part 'daos/suppliers_dao.dart';
part 'daos/manual_notas_dao.dart';

part 'app_database.g.dart';

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, 'kasirku.db'));
    return NativeDatabase(file);
  });
}

@DriftDatabase(
  tables: [
    Categories, Products, Customers, Transactions,
    TransactionItems, Debts, StockMovements,
    CashFlows, Settings, SyncQueue, Users, AuditLogs,
    Suppliers, ManualNotas,
  ],
  daos: [
    ProductsDao, CategoriesDao, TransactionsDao,
    CustomersDao, DebtsDao, ReportsDao, SyncDao,
    StockMovementsDao, SettingsDao, UsersDao,
    SuppliersDao, ManualNotasDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 8;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (Migrator m) async {
      await m.createAll();
      await _insertDefaults();
    },
    onUpgrade: (Migrator m, int from, int to) async {
      if (from < 2) {
        await customStatement(
          "CREATE TABLE IF NOT EXISTS users ("
          "id INTEGER PRIMARY KEY AUTOINCREMENT,"
          "name TEXT NOT NULL,"
          "pin TEXT NOT NULL,"
          "role TEXT NOT NULL DEFAULT 'kasir',"
          "is_active INTEGER NOT NULL DEFAULT 1,"
          "created_at INTEGER NOT NULL DEFAULT (strftime('%s','now') * 1000)"
          ")"
        );
        await customStatement(
          "CREATE TABLE IF NOT EXISTS sync_queue ("
          "id INTEGER PRIMARY KEY AUTOINCREMENT,"
          "table_name TEXT NOT NULL,"
          "record_id INTEGER NOT NULL,"
          "action TEXT NOT NULL,"
          "created_at INTEGER NOT NULL DEFAULT (strftime('%s','now') * 1000)"
          ")"
        );
      }
      if (from < 3) {
        await customStatement(
          "ALTER TABLE transactions ADD COLUMN kasir_id INTEGER REFERENCES users(id)"
        );
        await customStatement(
          "ALTER TABLE transactions ADD COLUMN kasir_name TEXT"
        );
      }
      if (from < 4) {
        // Migrasi kolom baru di tabel users
        await customStatement("ALTER TABLE users ADD COLUMN username TEXT");
        await customStatement("ALTER TABLE users ADD COLUMN display_name TEXT");
        await customStatement(
            "ALTER TABLE users ADD COLUMN failed_attempts INTEGER NOT NULL DEFAULT 0");
        await customStatement(
            "ALTER TABLE users ADD COLUMN locked_until INTEGER");
        await customStatement(
            "ALTER TABLE users ADD COLUMN must_change_pin INTEGER NOT NULL DEFAULT 0");

        // Isi username dari name yang lama (fallback)
        await customStatement(
            "UPDATE users SET username = lower(replace(name,' ','_')), "
            "display_name = name WHERE username IS NULL");

        // Buat tabel audit_logs
        await customStatement(
          "CREATE TABLE IF NOT EXISTS audit_logs ("
          "id INTEGER PRIMARY KEY AUTOINCREMENT,"
          "user_id INTEGER REFERENCES users(id),"
          "action TEXT NOT NULL,"
          "description TEXT,"
          "created_at INTEGER NOT NULL DEFAULT (strftime('%s','now') * 1000)"
          ")"
        );
      }
      if (from < 5) {
        // Fix cash_flows: pastikan kolom type dan category ada
        try {
          await customStatement(
            "ALTER TABLE cash_flows ADD COLUMN type TEXT NOT NULL DEFAULT 'income'"
          );
        } catch (_) {}
        try {
          await customStatement(
            "ALTER TABLE cash_flows ADD COLUMN category TEXT NOT NULL DEFAULT 'Lainnya'"
          );
        } catch (_) {}
      }
      if (from < 6) {
        // Tambah tabel suppliers (pemasok)
        await customStatement(
          "CREATE TABLE IF NOT EXISTS suppliers ("
          "id INTEGER PRIMARY KEY AUTOINCREMENT,"
          "name TEXT NOT NULL,"
          "company TEXT,"
          "products TEXT,"
          "phone TEXT,"
          "address TEXT,"
          "notes TEXT,"
          "created_at INTEGER NOT NULL DEFAULT (strftime('%s','now') * 1000)"
          ")"
        );
      }
      if (from < 7) {
        // CATATAN-02 FIX: Tambah trigger BEFORE INSERT/UPDATE untuk cegah stok negatif.
        // SQLite tidak mendukung ALTER TABLE ADD CONSTRAINT CHECK pada tabel yang
        // sudah ada, jadi kita pakai trigger sebagai penegak aturan yang setara.
        // Pada install fresh, Drift sudah menerapkan CHECK via definisi kolom di Products.
        await customStatement(
          "CREATE TRIGGER IF NOT EXISTS prevent_negative_stock_insert "
          "BEFORE INSERT ON products "
          "FOR EACH ROW WHEN NEW.stock < 0 "
          "BEGIN SELECT RAISE(ABORT, 'Stok tidak boleh negatif'); END"
        );
        await customStatement(
          "CREATE TRIGGER IF NOT EXISTS prevent_negative_stock_update "
          "BEFORE UPDATE OF stock ON products "
          "FOR EACH ROW WHEN NEW.stock < 0 "
          "BEGIN SELECT RAISE(ABORT, 'Stok tidak boleh negatif'); END"
        );
      }
      if (from < 8) {
        // Fitur Nota Manual: nota tulis-tangan cepat, terpisah dari
        // Transactions karena item-nya bebas (tidak terhubung ke Products/stok).
        await customStatement(
          "CREATE TABLE IF NOT EXISTS manual_notas ("
          "id INTEGER PRIMARY KEY AUTOINCREMENT,"
          "invoice_number TEXT NOT NULL,"
          "customer_name TEXT,"
          "items_json TEXT NOT NULL,"
          "total REAL NOT NULL DEFAULT 0,"
          "amount_paid REAL,"
          "is_synced INTEGER NOT NULL DEFAULT 0,"
          "created_at INTEGER NOT NULL DEFAULT (strftime('%s','now') * 1000),"
          "updated_at INTEGER NOT NULL DEFAULT (strftime('%s','now') * 1000)"
          ")"
        );
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  /// Cek apakah DB belum ada user (dipakai oleh needsSetupProvider)
  Future<bool> needsSetup() => usersDao.needsSetup();

  Future<void> _insertDefaults() async {
    final cats = ['Makanan', 'Minuman', 'Snack', 'Rokok',
                  'Sembako', 'Kebersihan', 'Kesehatan', 'Lainnya'];
    for (final cat in cats) {
      await into(categories).insert(CategoriesCompanion.insert(name: cat));
    }
    await into(settings).insert(
      SettingsCompanion.insert(key: 'toko_nama', value: const Value('KasirKu')));
    // TIDAK ada insert admin default — admin pertama dibuat via SetupWizardScreen
  }

  Future<void> resetAllData() async {
    await transaction(() async {
      await delete(transactionItems).go();
      await delete(transactions).go();
      await delete(debts).go();
      await delete(stockMovements).go();
      await delete(syncQueue).go();
      await delete(cashFlows).go();
      await delete(auditLogs).go();
      await (update(products)).write(const ProductsCompanion(stock: Value(0)));
      await (update(customers)).write(const CustomersCompanion(points: Value(0)));
    });
  }
}
