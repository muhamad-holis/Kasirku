part of '../app_database.dart';

// Tabel untuk fitur "Nota Manual" — nota tulis tangan cepat (nama & harga
// barang diketik bebas, TIDAK terhubung ke tabel Products/stok). Dipakai saat
// kasir memilih mode "Manual" di popup Kasir, sebagai alternatif dari alur
// Kasir Otomatis (scan barcode + potong stok).
class ManualNotas extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get invoiceNumber => text()();
  TextColumn get customerName => text().nullable()();
  // Daftar item (nama, harga, qty, totalOverride) disimpan sebagai JSON —
  // sengaja tidak dipecah ke tabel terpisah karena item nota manual bersifat
  // bebas/tidak terhubung ke produk, mengikuti desain asli Nota Tulis.
  TextColumn get itemsJson => text()();
  RealColumn get total => real().withDefault(const Constant(0))();
  RealColumn get amountPaid => real().nullable()();
  BoolColumn get isSynced => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
