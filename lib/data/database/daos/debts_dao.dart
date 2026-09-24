part of '../app_database.dart';

@DriftAccessor(tables: [Debts, Customers])
class DebtsDao extends DatabaseAccessor<AppDatabase>
    with _$DebtsDaoMixin {
  DebtsDao(super.db);

  Future<List<Debt>> getAllDebts() => select(debts).get();
  Future<List<Debt>> getUnpaidDebts() =>
      (select(debts)..where((t) => t.status.equals('unpaid'))).get();
  Stream<List<Debt>> watchDebts() => select(debts).watch();
  Future<int> insertDebt(DebtsCompanion d) => into(debts).insert(d);

  // BUG #9 FIX: Tambahkan guard overpayment di layer DAO.
  // UI sudah memvalidasi, tapi DAO harus aman jika dipanggil dari konteks lain.
  // Gunakan clamp agar pembayaran tidak bisa melebihi sisa hutang.
  Future<void> payDebt(int id, double amount) async {
    final debt = await (select(debts)
      ..where((t) => t.id.equals(id))).getSingle();
    final remaining = debt.amount - debt.paidAmount;
    final actualPayment = amount.clamp(0.0, remaining); // tidak bisa bayar lebih
    final newPaid = debt.paidAmount + actualPayment;
    final newStatus = newPaid >= debt.amount ? 'paid' : 'partial';
    await (update(debts)..where((t) => t.id.equals(id)))
        .write(DebtsCompanion(
          paidAmount: Value(newPaid),
          status: Value(newStatus),
        ));
  }
}
