part of '../app_database.dart';

@DriftAccessor(tables: [PrintLabelHistories])
class PrintLabelHistoriesDao extends DatabaseAccessor<AppDatabase>
    with _$PrintLabelHistoriesDaoMixin {
  PrintLabelHistoriesDao(super.db);

  Stream<List<PrintLabelHistory>> watchHistory() =>
      (select(printLabelHistories)
        ..orderBy([(t) => OrderingTerm.desc(t.printedAt)]))
          .watch();

  Future<void> addEntry({
    required String productName,
    required String unit,
    required double price,
    required int quantity,
  }) =>
      into(printLabelHistories).insert(PrintLabelHistoriesCompanion.insert(
        productName: productName,
        unit: unit,
        price: price,
        quantity: quantity,
      ));
}
