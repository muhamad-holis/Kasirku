part of '../app_database.dart';

@DriftAccessor(tables: [Transactions, TransactionItems, Products, Customers, StockMovements])
class TransactionsDao extends DatabaseAccessor<AppDatabase>
    with _$TransactionsDaoMixin {
  TransactionsDao(super.db);

  /// Insert transaksi + kurangi stok + catat stock movement + beri poin otomatis ke pelanggan.
  /// [customerId] opsional — bisa diisi untuk semua metode pembayaran.
  /// Poin = 1 poin per Rp 10.000 yang dibayar.
  Future<int> insertTransaction(
    TransactionsCompanion transaction,
    List<TransactionItemsCompanion> items, {
    int? customerId,
    int? kasirId,
    String? kasirName,
  }) async {
    return db.transaction(() async {
      var txCompanion = transaction;
      if (customerId != null) {
        txCompanion = txCompanion.copyWith(customerId: Value(customerId));
      }
      if (kasirId != null) {
        txCompanion = txCompanion.copyWith(kasirId: Value(kasirId));
      }
      if (kasirName != null) {
        txCompanion = txCompanion.copyWith(kasirName: Value(kasirName));
      }

      final txId = await into(transactions).insert(txCompanion);

      // Ambil invoiceNumber dari companion jika tersedia, fallback ke txId
      final invoiceNumber = transaction.invoiceNumber.present
          ? transaction.invoiceNumber.value
          : 'TX-$txId';

      for (final item in items) {
        await into(transactionItems).insert(
          item.copyWith(transactionId: Value(txId)),
        );
        final product = await (select(products)
              ..where((t) => t.id.equals(item.productId.value)))
            .getSingle();

        // BUG #10 FIX: Catat ke stock_movements setiap ada penjualan.
        // Sebelumnya hanya update stock tanpa insert movement → riwayat stok kosong.
        final newStock = product.stock - item.quantity.value;
        await (update(products)
              ..where((t) => t.id.equals(item.productId.value)))
            .write(ProductsCompanion(
              stock: Value(newStock),
              updatedAt: Value(DateTime.now()),
            ));

        // Catat pergerakan stok keluar akibat penjualan
        await into(stockMovements).insert(
          StockMovementsCompanion.insert(
            productId: item.productId.value,
            type: 'keluar',
            quantity: item.quantity.value,
            stockBefore: product.stock,
            stockAfter: newStock,
            notes: Value('Penjualan - Invoice $invoiceNumber'),
          ),
        );
      }

      // Poin otomatis: 1 poin per Rp 10.000
      if (customerId != null) {
        final total = transaction.total.value;
        final earnedPoints = (total / 10000).floor();
        if (earnedPoints > 0) {
          final customer = await (select(customers)
                ..where((c) => c.id.equals(customerId)))
              .getSingleOrNull();
          if (customer != null) {
            await (update(customers)
                  ..where((c) => c.id.equals(customerId)))
                .write(CustomersCompanion(
                  points: Value(customer.points + earnedPoints),
                ));
          }
        }
      }

      return txId;
    });
  }

  Future<List<Transaction>> getTransactionsByDate(
      DateTime start, DateTime end) =>
      (select(transactions)
        ..where((t) => t.createdAt.isBetweenValues(start, end))
        ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
          .get();

  /// Riwayat transaksi per pelanggan
  Future<List<Transaction>> getTransactionsByCustomer(int customerId) =>
      (select(transactions)
        ..where((t) => t.customerId.equals(customerId))
        ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
          .get();

  Future<Map<String, dynamic>> getTodaySummary() async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(const Duration(days: 1));
    final txList = await getTransactionsByDate(start, end);
    final omzet = txList.fold<double>(0, (s, t) => s + t.total);
    return {'omzet': omzet, 'jumlah_transaksi': txList.length};
  }

  Future<List<TransactionItem>> getTransactionItems(int transactionId) =>
      (select(transactionItems)
        ..where((t) => t.transactionId.equals(transactionId)))
          .get();

  // BUG #6 FIX: Method baru untuk hitung total produk terjual dalam satu query aggregat.
  // Menggantikan loop N+1 query di dashboardStatsProvider.
  Future<int> getTotalProductsSold(List<int> txIds) async {
    if (txIds.isEmpty) return 0;
    final result = await (selectOnly(transactionItems)
      ..addColumns([transactionItems.quantity.sum()])
      ..where(transactionItems.transactionId.isIn(txIds)))
        .getSingle();
    return result.read(transactionItems.quantity.sum()) ?? 0;
  }

  // BUG-12 FIX: ganti SELECT MAX(id) dengan pendekatan COUNT + microsecond suffix.
  // SELECT MAX(id) tanpa lock tidak aman jika dua kasir submit transaksi bersamaan
  // — keduanya bisa mendapat maxId yang sama dan menghasilkan nomor invoice duplikat.
  //
  // Strategi baru:
  //   Prefix  = INVyyyyMMdd  (tanggal hari ini)
  //   Urutan  = COUNT(*) transaksi hari ini + 1  (aman karena hanya dipakai sebagai
  //             nomor urut tampilan, bukan primary key)
  //   Suffix  = 3 digit terakhir microsecond  (tiebreaker jika dua transaksi
  //             terjadi dalam waktu yang sangat berdekatan)
  //
  // Format akhir: INV20250622-0003-847
  // Kombinasi urutan + microsecond suffix secara praktis menghilangkan duplikat
  // tanpa perlu database lock.
  Future<String> generateInvoiceNumber() async {
    final now = DateTime.now();
    final prefix =
        'INV${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    final start = DateTime(now.year, now.month, now.day);

    // Hitung jumlah transaksi hari ini (lebih aman dari MAX karena tidak bergantung
    // pada urutan insert yang bisa race)
    final result = await (selectOnly(transactions)
          ..addColumns([transactions.id.count()])
          ..where(transactions.createdAt.isBiggerOrEqualValue(start)))
        .getSingle();
    final countToday = result.read(transactions.id.count()) ?? 0;
    final seq = (countToday + 1).toString().padLeft(4, '0');

    // Microsecond tiebreaker: 3 digit terakhir microsecond epoch
    final micro = (now.microsecondsSinceEpoch % 1000).toString().padLeft(3, '0');

    return '$prefix-$seq-$micro';
  }

  // BUG #7 FIX: Ubah menjadi async* generator yang loop ulang setiap tengah malam.
  // Sebelumnya: DateTime.now() dihitung sekali saat stream dibuat → tidak reset.
  // Sekarang: stream timeout menjelang tengah malam, lalu loop ulang dengan range baru.
  Stream<List<Transaction>> watchTodayTransactions() async* {
    while (true) {
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day);
      final end = start.add(const Duration(days: 1));
      final secondsUntilMidnight = end.difference(now).inSeconds + 1;

      bool timedOut = false;
      await for (final txList in (select(transactions)
            ..where((t) => t.createdAt.isBetweenValues(start, end))
            ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
          .watch()
          .timeout(
            Duration(seconds: secondsUntilMidnight),
            onTimeout: (sink) {
              timedOut = true;
              sink.close();
            },
          )) {
        yield txList;
      }
      if (!timedOut) break; // stream selesai normal, bukan karena midnight
      // lewat tengah malam → loop ulang dengan range hari baru
    }
  }
}
