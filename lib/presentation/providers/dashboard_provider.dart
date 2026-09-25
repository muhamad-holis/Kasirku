import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/database/app_database.dart';
import '../models/riwayat_entry.dart';
import 'database_provider.dart';

final dashboardSummaryProvider = FutureProvider<Map<String, dynamic>>((ref) =>
    ref.watch(databaseProvider).transactionsDao.getTodaySummary());

final topProductsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final db = ref.watch(databaseProvider);
  final now = DateTime.now();
  return db.reportsDao.getTopProducts(
    DateTime(now.year, now.month, 1), now, limit: 5);
});

/// "Transaksi Terakhir" di Dashboard — gabungan transaksi Kasir Otomatis +
/// Nota Manual hari ini, reaktif (update otomatis begitu ada yang baru).
final todayTransactionsProvider = StreamProvider<List<RiwayatEntry>>((ref) {
  final db = ref.watch(databaseProvider);
  return combineRiwayat(
    db.transactionsDao.watchTodayTransactions(),
    db.manualNotasDao.watchToday(),
  );
});
