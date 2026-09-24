// lib/presentation/providers/hutang_provider.dart
// ─────────────────────────────────────────────────────────────────────────────
// Provider untuk Manajemen Hutang Piutang (P1)
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/database/app_database.dart';
import 'database_provider.dart';

// ─── Model ────────────────────────────────────────────────────────────────────

class DebtWithCustomer {
  final Debt debt;
  final String customerName;

  const DebtWithCustomer({required this.debt, required this.customerName});
}

class HutangSummary {
  final double totalDebt;
  final double totalPaid;
  final double totalRemaining;
  final int totalCount;
  final int overdueCount;

  const HutangSummary({
    required this.totalDebt,
    required this.totalPaid,
    required this.totalRemaining,
    required this.totalCount,
    required this.overdueCount,
  });
}

/// Model untuk riwayat pembayaran (dari cash_flows)
class DebtPayment {
  final double amount;
  final String? description;
  final DateTime date;

  const DebtPayment({
    required this.amount,
    this.description,
    required this.date,
  });
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

Future<List<DebtWithCustomer>> _enrichDebts(
    List<Debt> debts, AppDatabase db) async {
  final customers = await db.customersDao.getAllCustomers();
  final customerMap = {for (final c in customers) c.id: c.name};

  return debts.map((d) {
    final name = customerMap[d.customerId] ?? 'Pelanggan #${d.customerId}';
    return DebtWithCustomer(debt: d, customerName: name);
  }).toList();
}

// ─── Providers ────────────────────────────────────────────────────────────────

/// Stream semua hutang (real-time)
final allDebtsStreamProvider = StreamProvider<List<Debt>>((ref) {
  return ref.watch(databaseProvider).debtsDao.watchDebts();
});

/// Semua hutang dengan nama pelanggan
final allDebtsWithCustomerProvider =
    FutureProvider<List<DebtWithCustomer>>((ref) async {
  final db = ref.watch(databaseProvider);
  final debts = await db.debtsDao.getAllDebts();
  return _enrichDebts(debts, db);
});

/// Hutang yang belum lunas
final unpaidDebtsWithCustomerProvider =
    FutureProvider<List<DebtWithCustomer>>((ref) async {
  // Invalidate setiap kali stream berubah
  ref.watch(allDebtsStreamProvider);
  
  final db = ref.read(databaseProvider);
  final debts = await db.debtsDao.getUnpaidDebts();
  return _enrichDebts(debts, db);
});

/// Hutang yang sudah jatuh tempo (dueDate <= hari ini, belum lunas)
final overdueDebtsWithCustomerProvider =
    FutureProvider<List<DebtWithCustomer>>((ref) async {
  ref.watch(allDebtsStreamProvider);

  final db = ref.read(databaseProvider);
  final now = DateTime.now();
  final allDebts = await db.debtsDao.getUnpaidDebts();
  final overdue = allDebts.where((d) {
    if (d.dueDate == null) return false;
    return d.dueDate!.isBefore(now) && d.status != 'paid';
  }).toList();

  return _enrichDebts(overdue, db);
});

/// Summary hutang keseluruhan
final hutangSummaryProvider = FutureProvider<HutangSummary>((ref) async {
  ref.watch(allDebtsStreamProvider);

  final db = ref.read(databaseProvider);
  final all = await db.debtsDao.getAllDebts();
  final now = DateTime.now();

  final totalDebt = all.fold<double>(0, (s, d) => s + d.amount);
  final totalPaid = all.fold<double>(0, (s, d) => s + d.paidAmount);
  final overdueCount = all
      .where((d) =>
          d.dueDate != null &&
          d.dueDate!.isBefore(now) &&
          d.status != 'paid')
      .length;

  return HutangSummary(
    totalDebt: totalDebt,
    totalPaid: totalPaid,
    totalRemaining: totalDebt - totalPaid,
    totalCount: all.length,
    overdueCount: overdueCount,
  );
});

/// Hutang per pelanggan
final customerDebtsProvider =
    FutureProvider.family<List<Debt>, int>((ref, customerId) async {
  ref.watch(allDebtsStreamProvider);

  final db = ref.read(databaseProvider);
  final all = await db.debtsDao.getAllDebts();
  return all.where((d) => d.customerId == customerId).toList();
});

/// Riwayat pembayaran untuk hutang tertentu (dari cash_flows)
final debtPaymentHistoryProvider =
    FutureProvider.family<List<DebtPayment>, int>((ref, debtId) async {
  // Listen ke changes
  ref.watch(allDebtsStreamProvider);

  final db = ref.read(databaseProvider);
  final now = DateTime.now();

  // Ambil semua cash_flows kategori pelunasan_hutang
  final flows = await db.reportsDao.watchCashFlows(
    DateTime(2020),
    now.add(const Duration(days: 1)),
  ).first;

  // BUG #3 FIX: Filter eksak berdasarkan marker [debt_id:X] di description.
  // Sebelumnya menggunakan OR dengan contains('Invoice') yang selalu true
  // untuk semua cash_flow pelunasan_hutang → riwayat bayar campur semua pelanggan.
  // Format description baru (dari hutang_screen.dart):
  //   'Bayar hutang ${customerName} [debt_id:${debt.id}]'
  //
  // Untuk backward-compatibility dengan entry lama (format: 'Invoice #X'),
  // tetap cek contains('$debtId') sebagai fallback, tapi TANPA contains('Invoice')
  // yang menjadi root cause bug (selalu true).
  final related = flows.where((f) {
    return f.category == 'pelunasan_hutang' &&
        ((f.description?.contains('[debt_id:$debtId]') ?? false) ||
         (f.description?.contains('$debtId') ?? false));
  }).toList();

  return related
      .map((f) => DebtPayment(
            amount: f.amount,
            description: f.description,
            date: f.createdAt,
          ))
      .toList();
});

/// Jumlah hutang jatuh tempo (untuk badge notifikasi)
final overdueCountProvider = FutureProvider<int>((ref) async {
  final summary = await ref.watch(hutangSummaryProvider.future);
  return summary.overdueCount;
});
