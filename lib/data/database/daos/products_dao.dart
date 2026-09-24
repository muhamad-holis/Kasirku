part of '../app_database.dart';

@DriftAccessor(tables: [Products, Categories])
class ProductsDao extends DatabaseAccessor<AppDatabase>
    with _$ProductsDaoMixin {
  ProductsDao(super.db);

  Future<List<Product>> getAllProducts() =>
      (select(products)..where((t) => t.isActive.equals(true))).get();

  Future<List<Product>> searchProducts(String query) =>
      (select(products)
        ..where((t) =>
            t.name.like('%$query%') |
            t.barcode.like('%$query%') |
            t.sku.like('%$query%'))
        ..where((t) => t.isActive.equals(true)))
          .get();

  Future<Product?> getByBarcode(String barcode) =>
      (select(products)
        ..where((t) => t.barcode.equals(barcode))
        ..where((t) => t.isActive.equals(true)))
          .getSingleOrNull();

  Future<List<Product>> getLowStockProducts() =>
      (select(products)
        ..where((t) => t.isActive.equals(true)))
          .get()
          .then((list) => list.where((p) => p.stock < p.minStock).toList());

  Future<Product?> getProductByName(String name) =>
      (select(products)
        ..where((t) => t.name.lower().equals(name.toLowerCase()))
        ..where((t) => t.isActive.equals(true)))
          .getSingleOrNull();

  Future<List<Product>> findSimilarByName(String name) =>
      (select(products)
        ..where((t) => t.name.like('%${name.toLowerCase()}%'))
        ..where((t) => t.isActive.equals(true)))
          .get();

  Future<int> insertProduct(ProductsCompanion product) =>
      into(products).insert(product);

  Future<bool> updateProduct(ProductsCompanion product) =>
      update(products).replace(product);

  Future<void> updateStock(int productId, int newStock) =>
      (update(products)..where((t) => t.id.equals(productId)))
          .write(ProductsCompanion(stock: Value(newStock)));

  Future<void> deleteProduct(int id) =>
      (update(products)..where((t) => t.id.equals(id)))
          .write(const ProductsCompanion(isActive: Value(false)));

  Future<List<Product>> getProductsPaginated(int limit, int offset) =>
      (select(products)
        ..where((t) => t.isActive.equals(true))
        ..limit(limit, offset: offset))
          .get();

  Stream<List<Product>> watchAllProducts() =>
      (select(products)..where((t) => t.isActive.equals(true))).watch();

  Stream<List<Product>> watchLowStock() =>
      (select(products)
        ..where((t) => t.isActive.equals(true)))
          .watch()
          .map((list) => list.where((p) => p.stock < p.minStock).toList());

  Future<Product?> getProductById(int id) =>
      (select(products)..where((t) => t.id.equals(id))).getSingleOrNull();
}
