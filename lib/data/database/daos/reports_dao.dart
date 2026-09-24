part of '../app_database.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ReportsDao — DAO untuk laporan keuangan Kasirku
// Mendukung: Kas Masuk/Keluar, Arus Kas, Laba Rugi
// Tidak mengubah struktur tabel yang sudah ada.
// ─────────────────────────────────────────────────────────────────────────────

@DriftAccessor(
    tables: [Transactions, TransactionItems, Products, StockMovements, CashFlows, Categories])
class ReportsDao extends DatabaseAccessor<AppDatabase>
    with _$ReportsDaoMixin {
  ReportsDao(super.db);

  // ─── Produk Terlaris ────────────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getTopProducts(
      DateTime start, DateTime end, {int limit = 10}) async {
    final query = db.customSelect(
      '''
      SELECT p.id, p.name,
        SUM(ti.quantity) as total_qty,
        SUM(ti.subtotal) as total_omzet
      FROM transaction_items ti
      JOIN products p ON ti.product_id = p.id
      JOIN transactions t ON ti.transaction_id = t.id
      WHERE t.created_at BETWEEN ? AND ?
      GROUP BY p.id ORDER BY total_qty DESC LIMIT ?
      ''',
      variables: [
        Variable<DateTime>(start),
        Variable<DateTime>(end),
        Variable<int>(limit),
      ],
      readsFrom: {transactionItems, products, transactions},
    );
    return query.get().then((rows) => rows.map((r) => r.data).toList());
  }

  // ─── Penjualan per Kategori ─────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getSalesByCategory(
      DateTime start, DateTime end) async {
    final query = db.customSelect(
      '''
      SELECT
        COALESCE(c.name, 'Tanpa Kategori') as category_name,
        SUM(ti.quantity)  as total_qty,
        SUM(ti.subtotal)  as total_omzet
      FROM transaction_items ti
      JOIN products p ON ti.product_id = p.id
      LEFT JOIN categories c ON p.category_id = c.id
      JOIN transactions t ON ti.transaction_id = t.id
      WHERE t.created_at BETWEEN ? AND ?
      GROUP BY COALESCE(c.name, 'Tanpa Kategori')
      ORDER BY total_omzet DESC
      ''',
      variables: [
        Variable<DateTime>(start),
        Variable<DateTime>(end),
      ],
      readsFrom: {transactionItems, products, transactions, categories},
    );
    return query.get().then((rows) => rows.map((r) => r.data).toList());
  }

  // ─── Grafik Penjualan Harian ────────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getDailySalesChart(
      DateTime start, DateTime end) async {
    final query = db.customSelect(
      '''
      SELECT DATE(created_at / 1000, 'unixepoch', 'localtime') as tanggal,
        SUM(total) as omzet, COUNT(*) as jumlah
      FROM transactions
      WHERE created_at BETWEEN ? AND ? AND status = 'completed'
      GROUP BY DATE(created_at / 1000, 'unixepoch', 'localtime') ORDER BY tanggal ASC
      ''',
      variables: [
        Variable<DateTime>(start),
        Variable<DateTime>(end),
      ],
      readsFrom: {transactions},
    );
    return query.get().then((rows) => rows.map((r) => r.data).toList());
  }

  // ─── Stream Grafik Penjualan Harian (reaktif) ───────────────────────────────
  // Digunakan agar tab Penjualan di Laporan & Dashboard langsung update
  // tanpa perlu restart aplikasi setiap kali ada transaksi baru.

  Stream<List<Map<String, dynamic>>> watchDailySalesChart(
      DateTime start, DateTime end) {
    final query = db.customSelect(
      '''
      SELECT DATE(created_at / 1000, 'unixepoch', 'localtime') as tanggal,
        SUM(total) as omzet, COUNT(*) as jumlah
      FROM transactions
      WHERE created_at BETWEEN ? AND ? AND status = 'completed'
      GROUP BY DATE(created_at / 1000, 'unixepoch', 'localtime') ORDER BY tanggal ASC
      ''',
      variables: [
        Variable<DateTime>(start),
        Variable<DateTime>(end),
      ],
      readsFrom: {transactions},
    );
    return query.watch().map((rows) => rows.map((r) => r.data).toList());
  }

  // ─── Ringkasan Kas (Masuk, Keluar, Saldo) ──────────────────────────────────
  // FIX: Gunakan single-quotes untuk string literal SQLite (bukan double-quotes)
  // FIX: Gunakan Variable<DateTime> agar Drift mengkonversi ke integer epoch

  Future<Map<String, double>> getCashReport(
      DateTime start, DateTime end) async {
    final inc = await db.customSelect(
      "SELECT COALESCE(SUM(amount),0) as total FROM cash_flows WHERE type='income' AND created_at BETWEEN ? AND ?",
      variables: [
        Variable<DateTime>(start),
        Variable<DateTime>(end),
      ],
      readsFrom: {cashFlows},
    ).getSingle();
    final exp = await db.customSelect(
      "SELECT COALESCE(SUM(amount),0) as total FROM cash_flows WHERE type='expense' AND created_at BETWEEN ? AND ?",
      variables: [
        Variable<DateTime>(start),
        Variable<DateTime>(end),
      ],
      readsFrom: {cashFlows},
    ).getSingle();
    final i = (inc.data['total'] as num).toDouble();
    final e = (exp.data['total'] as num).toDouble();
    return {'income': i, 'expense': e, 'saldo': i - e};
  }

  // ─── Ringkasan Kas per Kategori (untuk detail Arus Kas) ────────────────────

  Future<List<Map<String, dynamic>>> getCashFlowByCategory(
      DateTime start, DateTime end, String type) async {
    final query = db.customSelect(
      '''
      SELECT category, SUM(amount) as total, COUNT(*) as jumlah
      FROM cash_flows
      WHERE type = ? AND created_at BETWEEN ? AND ?
      GROUP BY category
      ORDER BY total DESC
      ''',
      variables: [
        Variable<String>(type),
        Variable<DateTime>(start),
        Variable<DateTime>(end),
      ],
      readsFrom: {cashFlows},
    );
    return query.get().then((rows) => rows.map((r) => r.data).toList());
  }

  // ─── Arus Kas Harian (grafik) ───────────────────────────────────────────────

  Future<List<Map<String, dynamic>>> getDailyCashFlowChart(
      DateTime start, DateTime end) async {
    final query = db.customSelect(
      '''
      SELECT
        DATE(created_at / 1000, 'unixepoch', 'localtime') as tanggal,
        SUM(CASE WHEN type = 'income' THEN amount ELSE 0 END) as total_masuk,
        SUM(CASE WHEN type = 'expense' THEN amount ELSE 0 END) as total_keluar
      FROM cash_flows
      WHERE created_at BETWEEN ? AND ?
      GROUP BY DATE(created_at / 1000, 'unixepoch', 'localtime')
      ORDER BY tanggal ASC
      ''',
      variables: [
        Variable<DateTime>(start),
        Variable<DateTime>(end),
      ],
      readsFrom: {cashFlows},
    );
    return query.get().then((rows) => rows.map((r) => r.data).toList());
  }

  // ─── HPP: Harga Pokok Penjualan dari transaction_items + products ───────────

  Future<double> getHPP(DateTime start, DateTime end) async {
    final result = await db.customSelect(
      '''
      SELECT COALESCE(SUM(ti.quantity * p.buy_price), 0) as total_hpp
      FROM transaction_items ti
      JOIN products p ON ti.product_id = p.id
      JOIN transactions t ON ti.transaction_id = t.id
      WHERE t.created_at BETWEEN ? AND ?
        AND t.status = 'completed'
      ''',
      variables: [
        Variable<DateTime>(start),
        Variable<DateTime>(end),
      ],
      readsFrom: {transactionItems, products, transactions},
    ).getSingle();
    return (result.data['total_hpp'] as num).toDouble();
  }

  // ─── Omzet Penjualan dari tabel transactions ────────────────────────────────

  Future<double> getOmzet(DateTime start, DateTime end) async {
    final result = await db.customSelect(
      '''
      SELECT COALESCE(SUM(total), 0) as total_omzet
      FROM transactions
      WHERE created_at BETWEEN ? AND ?
        AND status = 'completed'
      ''',
      variables: [
        Variable<DateTime>(start),
        Variable<DateTime>(end),
      ],
      readsFrom: {transactions},
    ).getSingle();
    return (result.data['total_omzet'] as num).toDouble();
  }

  // ─── Laba Rugi Lengkap (single query composite) ─────────────────────────────

  Future<Map<String, double>> getLabaRugiReport(
      DateTime start, DateTime end) async {
    final omzet = await getOmzet(start, end);
    final hpp = await getHPP(start, end);
    final cashReport = await getCashReport(start, end);

    // Kas non-penjualan: exclude kategori 'penjualan' dan 'Penjualan'
    final allFlows = await (select(cashFlows)
          ..where((t) => t.createdAt.isBetweenValues(start, end)))
        .get();

    double kasIncomeNonSales = 0;
    double kasExpense = 0;

    for (final f in allFlows) {
      // BUG #4 FIX: Exclude 'pelunasan_hutang' dari kasIncomeNonSales.
      // Omzet dari transaksi hutang sudah dihitung di getOmzet().
      // Pembayaran hutang bukan pendapatan baru — hanya konversi piutang → kas.
      // Tanpa fix ini, hutang yang dibayar dalam periode yang sama dihitung 2x
      // → inflasi laba bersih sebesar nilai pembayaran.
      if (f.type == 'income' &&
          f.category.toLowerCase() != 'penjualan' &&
          f.category.toLowerCase() != 'pelunasan_hutang') {
        kasIncomeNonSales += f.amount;
      } else if (f.type == 'expense') {
        kasExpense += f.amount;
      }
    }

    final labaKotor = omzet - hpp;
    final labaBersih = labaKotor + kasIncomeNonSales - kasExpense;
    final margin = omzet == 0 ? 0.0 : (labaBersih / omzet) * 100;

    return {
      'omzet': omzet,
      'hpp': hpp,
      'laba_kotor': labaKotor,
      'kas_income_non_sales': kasIncomeNonSales,
      'kas_expense': kasExpense,
      'laba_bersih': labaBersih,
      'margin_persen': margin,
      'total_kas_masuk': cashReport['income'] ?? 0,
      'total_kas_keluar': cashReport['expense'] ?? 0,
      'saldo_kas': cashReport['saldo'] ?? 0,
    };
  }

  // ─── Tambah Entri Kas ───────────────────────────────────────────────────────

  Future<int> addCashFlow({
    required String type,
    required String category,
    required double amount,
    String? description,
  }) {
    return into(cashFlows).insert(
      CashFlowsCompanion.insert(
        type: type,
        category: category,
        amount: amount,
        description: Value(description),
      ),
    );
  }

  // ─── Hapus Entri Kas ────────────────────────────────────────────────────────

  Future<int> deleteCashFlow(int id) {
    return (delete(cashFlows)..where((t) => t.id.equals(id))).go();
  }

  // ─── Stream semua kas dalam rentang tanggal ─────────────────────────────────

  Stream<List<CashFlow>> watchCashFlows(DateTime start, DateTime end) {
    return (select(cashFlows)
          ..where((t) => t.createdAt.isBetweenValues(start, end))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .watch();
  }

  // ─── Stream kas per tipe (income / expense) ─────────────────────────────────

  Stream<List<CashFlow>> watchCashFlowsByType(
      DateTime start, DateTime end, String type) {
    return (select(cashFlows)
          ..where((t) =>
              t.createdAt.isBetweenValues(start, end) &
              t.type.equals(type))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .watch();
  }
}
