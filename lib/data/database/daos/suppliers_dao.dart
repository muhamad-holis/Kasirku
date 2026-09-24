part of '../app_database.dart';

@DriftAccessor(tables: [Suppliers])
class SuppliersDao extends DatabaseAccessor<AppDatabase>
    with _$SuppliersDaoMixin {
  SuppliersDao(super.db);

  // Stream semua supplier (real-time, sorted A-Z berdasarkan nama)
  Stream<List<Supplier>> watchSuppliersSorted() {
    return (select(suppliers)
          ..orderBy([
            (s) => OrderingTerm(
                  expression: s.name,
                  mode: OrderingMode.asc,
                ),
          ]))
        .watch();
  }

  // Semua supplier (future)
  Future<List<Supplier>> getAllSuppliers() => select(suppliers).get();

  // Insert
  Future<int> insertSupplier(SuppliersCompanion s) =>
      into(suppliers).insert(s);

  // Update
  Future<bool> updateSupplier(SuppliersCompanion s) =>
      update(suppliers).replace(s);

  // Delete
  Future<int> deleteSupplier(int id) =>
      (delete(suppliers)..where((s) => s.id.equals(id))).go();

  // Search by nama, perusahaan, atau produk
  Future<List<Supplier>> searchSuppliers(String q) =>
      (select(suppliers)
            ..where((s) =>
                s.name.like('%$q%') |
                s.company.like('%$q%') |
                s.products.like('%$q%')))
          .get();
}
