import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/database/app_database.dart';
import 'database_provider.dart';

// ─── Products ─────────────────────────────────────────────────────────────────

final productsStreamProvider = StreamProvider<List<Product>>((ref) {
  return ref.watch(databaseProvider).productsDao.watchAllProducts();
});

final productSearchProvider = StateProvider<String>((ref) => '');

final selectedCategoryProvider = StateProvider<int?>((ref) => null);

final filteredProductsProvider = FutureProvider<List<Product>>((ref) async {
  final query = ref.watch(productSearchProvider);
  final db = ref.watch(databaseProvider);
  if (query.isEmpty) return db.productsDao.getAllProducts();
  return db.productsDao.searchProducts(query);
});

final filteredStokProvider = Provider<AsyncValue<List<Product>>>((ref) {
  final products = ref.watch(productsStreamProvider);
  final query = ref.watch(productSearchProvider).toLowerCase();
  final categoryId = ref.watch(selectedCategoryProvider);

  return products.whenData((list) {
    return list.where((p) {
      final matchQuery = query.isEmpty ||
          p.name.toLowerCase().contains(query) ||
          (p.barcode?.contains(query) ?? false) ||
          (p.sku?.toLowerCase().contains(query) ?? false);
      final matchCategory =
          categoryId == null || p.categoryId == categoryId;
      return matchQuery && matchCategory;
    }).toList();
  });
});

final lowStockProvider = StreamProvider<List<Product>>((ref) {
  return ref.watch(databaseProvider).productsDao.watchLowStock();
});

// Produk yang stoknya habis total (stock == 0)
final outStockProvider = StreamProvider<List<Product>>((ref) {
  return ref.watch(databaseProvider).productsDao.watchAllProducts().map(
    (list) => list.where((p) => p.stock <= 0).toList(),
  );
});

// ─── Categories ───────────────────────────────────────────────────────────────

final categoriesProvider = StreamProvider<List<Category>>((ref) {
  return ref.watch(databaseProvider).categoriesDao.watchCategories();
});

// ─── Stock Movements ──────────────────────────────────────────────────────────

final stockMovementsProvider =
    FutureProvider.family<List<StockMovement>, int>((ref, productId) {
  return ref.watch(databaseProvider).stockMovementsDao
      .getMovementsByProduct(productId);
});
