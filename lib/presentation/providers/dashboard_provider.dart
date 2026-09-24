import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/database/app_database.dart';
import 'database_provider.dart';

final dashboardSummaryProvider = FutureProvider<Map<String, dynamic>>((ref) =>
    ref.watch(databaseProvider).transactionsDao.getTodaySummary());

final topProductsProvider = FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final db = ref.watch(databaseProvider);
  final now = DateTime.now();
  return db.reportsDao.getTopProducts(
    DateTime(now.year, now.month, 1), now, limit: 5);
});

final todayTransactionsProvider = StreamProvider<List<Transaction>>((ref) =>
    ref.watch(databaseProvider).transactionsDao.watchTodayTransactions());
