part of '../app_database.dart';

@DriftAccessor(tables: [StockMovements, Products])
class StockMovementsDao extends DatabaseAccessor<AppDatabase>
    with _$StockMovementsDaoMixin {
  StockMovementsDao(super.db);

  Future<List<StockMovement>> getMovementsByProduct(int productId) =>
      (select(stockMovements)
        ..where((t) => t.productId.equals(productId))
        ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
        ..limit(50))
          .get();

  Future<List<StockMovement>> getRecentMovements({int limit = 30}) =>
      (select(stockMovements)
        ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
        ..limit(limit))
          .get();

  Future<int> addMovement({
    required int productId,
    required String type,
    required int quantity,
    required int stockBefore,
    required int stockAfter,
    String? notes,
  }) =>
      into(stockMovements).insert(
        StockMovementsCompanion.insert(
          productId: productId,
          type: type,
          quantity: quantity,
          stockBefore: stockBefore,
          stockAfter: stockAfter,
          notes: Value(notes),
        ),
      );

  Future<void> adjustStock({
    required AppDatabase db,
    required int productId,
    required int newStock,
    required int oldStock,
    required String type,
    String? notes,
  }) async {
    await db.transaction(() async {
      await (update(products)
            ..where((t) => t.id.equals(productId)))
          .write(ProductsCompanion(stock: Value(newStock)));
      await addMovement(
        productId: productId,
        type: type,
        quantity: (newStock - oldStock).abs(),
        stockBefore: oldStock,
        stockAfter: newStock,
        notes: notes,
      );
    });
  }
}
