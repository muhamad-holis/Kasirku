part of '../app_database.dart';

@DriftAccessor(tables: [Customers])
class CustomersDao extends DatabaseAccessor<AppDatabase>
    with _$CustomersDaoMixin {
  CustomersDao(super.db);

  // Semua pelanggan (future)
  Future<List<Customer>> getAllCustomers() => select(customers).get();

  // ✅ Ambil satu pelanggan by id (dipakai untuk menampilkan nama pelanggan
  // pada struk PDF — lihat receipt_pdf_builder.dart)
  Future<Customer?> getCustomerById(int id) =>
      (select(customers)..where((c) => c.id.equals(id))).getSingleOrNull();

  // Stream biasa
  Stream<List<Customer>> watchCustomers() => select(customers).watch();

  // ✅ FIX: method yang dipanggil customers_provider.dart
  Stream<List<Customer>> watchCustomersSorted() {
    return (select(customers)
          ..orderBy([
            (c) => OrderingTerm(
                  expression: c.name,
                  mode: OrderingMode.asc,
                ),
          ]))
        .watch();
  }

  // Insert
  Future<int> insertCustomer(CustomersCompanion c) =>
      into(customers).insert(c);

  // Update
  Future<bool> updateCustomer(CustomersCompanion c) =>
      update(customers).replace(c);

  // ✅ FIX: method yang dipanggil pelanggan_screen.dart
  Future<int> deleteCustomer(int id) =>
      (delete(customers)..where((c) => c.id.equals(id))).go();

  // Search
  Future<List<Customer>> searchCustomers(String q) =>
      (select(customers)
            ..where((t) => t.name.like('%$q%') | t.phone.like('%$q%')))
          .get();
}
