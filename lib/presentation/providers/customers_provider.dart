import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/database/app_database.dart';
import 'database_provider.dart';

// ─── Stream semua pelanggan (real-time, sorted A-Z) ──────────────────────────

final customersStreamProvider = StreamProvider<List<Customer>>((ref) {
  return ref.watch(databaseProvider).customersDao.watchCustomersSorted();
});

// ─── State pencarian pelanggan ────────────────────────────────────────────────

final customerSearchProvider = StateProvider<String>((ref) => '');

// ─── Filtered customers berdasarkan query pencarian ───────────────────────────

final filteredCustomersProvider = Provider<AsyncValue<List<Customer>>>((ref) {
  final all   = ref.watch(customersStreamProvider);
  final query = ref.watch(customerSearchProvider).toLowerCase().trim();

  return all.whenData((list) {
    if (query.isEmpty) return list;
    return list.where((c) {
      return c.name.toLowerCase().contains(query) ||
          (c.phone?.contains(query) ?? false) ||
          (c.address?.toLowerCase().contains(query) ?? false);
    }).toList();
  });
});

// ─── Statistik pelanggan ──────────────────────────────────────────────────────

final customerStatsProvider = Provider<AsyncValue<Map<String, int>>>((ref) {
  final all = ref.watch(customersStreamProvider);
  return all.whenData((list) => {
    'total': list.length,
    'withPhone': list.where((c) => c.phone != null && c.phone!.isNotEmpty).length,
    'withPoints': list.where((c) => c.points > 0).length,
  });
});
