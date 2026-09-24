import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/database/app_database.dart';
import 'database_provider.dart';

// ─── Stream semua supplier (real-time, sorted A-Z) ───────────────────────────

final suppliersStreamProvider = StreamProvider<List<Supplier>>((ref) {
  return ref.watch(databaseProvider).suppliersDao.watchSuppliersSorted();
});

// ─── State pencarian supplier ─────────────────────────────────────────────────

final supplierSearchProvider = StateProvider<String>((ref) => '');

// ─── Filtered suppliers berdasarkan query pencarian ───────────────────────────

final filteredSuppliersProvider = Provider<AsyncValue<List<Supplier>>>((ref) {
  final all   = ref.watch(suppliersStreamProvider);
  final query = ref.watch(supplierSearchProvider).toLowerCase().trim();

  return all.whenData((list) {
    if (query.isEmpty) return list;
    return list.where((s) {
      return s.name.toLowerCase().contains(query) ||
          (s.company?.toLowerCase().contains(query) ?? false) ||
          (s.products?.toLowerCase().contains(query) ?? false) ||
          (s.phone?.contains(query) ?? false);
    }).toList();
  });
});

// ─── Statistik supplier ───────────────────────────────────────────────────────

final supplierStatsProvider = Provider<AsyncValue<Map<String, int>>>((ref) {
  final all = ref.watch(suppliersStreamProvider);
  return all.whenData((list) => {
    'total': list.length,
    'withPhone': list.where((s) => s.phone != null && s.phone!.isNotEmpty).length,
    'withCompany': list.where((s) => s.company != null && s.company!.isNotEmpty).length,
  });
});
