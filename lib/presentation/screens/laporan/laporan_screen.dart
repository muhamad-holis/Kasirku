import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency.dart';
import '../../../data/database/app_database.dart';
import '../../providers/database_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/kas_provider.dart';
import '../../providers/manual_nota_provider.dart';
import '../../navigation/app_router.dart';

/// Warna khas nota manual — sama dengan yang dipakai di Riwayat Transaksi
/// (riwayat_screen.dart) supaya konsisten secara visual di seluruh app.
const _manualColor = Color(0xFF8B5CF6);

class LaporanScreen extends ConsumerStatefulWidget {
  const LaporanScreen({super.key});

  @override
  ConsumerState<LaporanScreen> createState() => _LaporanScreenState();
}

class _LaporanScreenState extends ConsumerState<LaporanScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  String _period = '7d';
  bool _exportingPdf = false;

  static const _pdfPrimary   = PdfColor.fromInt(0xFF0D9488);
  static const _pdfSuccess   = PdfColor.fromInt(0xFF10B981);
  static const _pdfDanger    = PdfColor.fromInt(0xFFEF4444);
  static const _pdfWarning   = PdfColor.fromInt(0xFFF59E0B);
  static const _pdfGrey      = PdfColor.fromInt(0xFF6B7280);
  static const _pdfLightGrey = PdfColor.fromInt(0xFFF3F4F6);

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  DateTime get _start {
    final now = DateTime.now();
    switch (_period) {
      case 'today':
        return DateTime(now.year, now.month, now.day);
      case '7d':
        return now.subtract(const Duration(days: 7));
      case '30d':
        return now.subtract(const Duration(days: 30));
      default:
        return DateTime(now.year, now.month, 1);
    }
  }

  String get _periodLabel {
    switch (_period) {
      case 'today':
        return 'Hari Ini';
      case '7d':
        return '7 Hari Terakhir';
      case '30d':
        return '30 Hari Terakhir';
      default:
        return 'Bulan Ini';
    }
  }

  DateRange get _range =>
      DateRange(start: _start, end: DateTime.now());

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Laporan',
            style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: const Icon(Icons.account_balance_wallet_outlined),
            tooltip: 'Kelola Kas',
            onPressed: () => MainNavigation.navigateToKas(context),
          ),
          _exportingPdf
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2)))
              : IconButton(
                  icon: const Icon(Icons.picture_as_pdf_outlined),
                  tooltip: 'Export PDF',
                  onPressed: _exportPdf,
                ),
        ],
        bottom: TabBar(
          controller: _tab,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: const [
            Tab(text: 'Penjualan'),
            Tab(text: 'Laba Rugi'),
            Tab(text: 'Kas'),
          ],
        ),
      ),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Row(
              children: [
                _Chip('Hari Ini', 'today', _period,
                    (v) => setState(() => _period = v)),
                _Chip('7 Hari', '7d', _period,
                    (v) => setState(() => _period = v)),
                _Chip('30 Hari', '30d', _period,
                    (v) => setState(() => _period = v)),
                _Chip('Bulan Ini', 'month', _period,
                    (v) => setState(() => _period = v)),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                _SalesTab(start: _start, end: DateTime.now()),
                _LabaRugiTab(range: _range),
                _CashTab(start: _start, end: DateTime.now(), range: _range),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Export PDF ────────────────────────────────────────────────────────────

  Future<void> _exportPdf() async {
    setState(() => _exportingPdf = true);
    try {
      final db = ref.read(databaseProvider);
      final end = DateTime.now();
      final salesData =
          await db.reportsDao.getDailySalesChart(_start, end);
      final cashData = await db.reportsDao.getCashReport(_start, end);
      final labaData =
          await db.reportsDao.getLabaRugiReport(_start, end);
      final lowStock = await db.productsDao.getLowStockProducts();
      final settings = ref.read(storeSettingsProvider);
      final storeName = settings.storeName;
      final storeAddress = settings.storeAddress;

      final pdfBytes = await _buildLaporanPdf(
        storeName: storeName,
        storeAddress: storeAddress,
        periodLabel: _periodLabel,
        salesData: salesData,
        cashData: cashData,
        labaData: labaData,
        lowStockProducts: lowStock,
      );

      final now = DateTime.now();
      final filename =
          'laporan_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}.pdf';

      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/$filename');
      await file.writeAsBytes(pdfBytes);
      await Share.shareXFiles([XFile(file.path)], text: 'Laporan $filename');
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Gagal export PDF: $e'),
            backgroundColor: AppColors.danger));
      }
    } finally {
      if (mounted) setState(() => _exportingPdf = false);
    }
  }

  Future<Uint8List> _buildLaporanPdf({
    required String storeName,
    required String storeAddress,
    required String periodLabel,
    required List<Map<String, dynamic>> salesData,
    required Map<String, double> cashData,
    required Map<String, double> labaData,
    required List<dynamic> lowStockProducts,
  }) async {
    await initializeDateFormatting('id', null);
    final doc = pw.Document();
    final now = DateTime.now();
    final printDate = DateFormat('dd MMMM yyyy, HH:mm', 'id').format(now);

    final omzet = salesData.fold<double>(0, (s, r) => s + (r['omzet'] as num));
    final txCount = salesData.fold<int>(0, (s, r) => s + (r['jumlah'] as int));
    final avgTx = txCount > 0 ? omzet / txCount : 0.0;
    final income = cashData['income'] ?? 0;
    final expense = cashData['expense'] ?? 0;
    final saldo = cashData['saldo'] ?? 0;
    final hpp = labaData['hpp'] ?? 0;
    final labaKotor = labaData['laba_kotor'] ?? 0;
    final labaBersih = labaData['laba_bersih'] ?? 0;
    final margin = labaData['margin_persen'] ?? 0;

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(32),
      header: (ctx) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Container(
            padding: const pw.EdgeInsets.all(16),
            decoration: const pw.BoxDecoration(
              color: _pdfPrimary,
              borderRadius: pw.BorderRadius.all(pw.Radius.circular(10)),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(storeName,
                        style: pw.TextStyle(
                            fontSize: 20,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.white)),
                    if (storeAddress.isNotEmpty)
                      pw.Text(storeAddress,
                          style: pw.TextStyle(
                              fontSize: 10,
                              color: const PdfColor(1, 1, 1, 0.7))),
                  ],
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('LAPORAN KEUANGAN',
                        style: pw.TextStyle(
                            fontSize: 12,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.white)),
                    pw.Text(periodLabel,
                        style: pw.TextStyle(
                            fontSize: 10,
                            color: const PdfColor(1, 1, 1, 0.7))),
                    pw.Text('Dicetak: $printDate',
                        style: pw.TextStyle(
                            fontSize: 8,
                            color: const PdfColor(1, 1, 1, 0.6))),
                  ],
                ),
              ],
            ),
          ),
          pw.SizedBox(height: 16),
        ],
      ),
      build: (ctx) => [
        _pdfSectionTitle('Ringkasan Penjualan', _pdfPrimary),
        pw.SizedBox(height: 8),
        pw.Row(children: [
          pw.Expanded(
              child: _pdfSummaryCard('Total Omzet',
                  CurrencyFormatter.format(omzet), _pdfSuccess, _pdfLightGrey)),
          pw.SizedBox(width: 8),
          pw.Expanded(
              child: _pdfSummaryCard('Transaksi', '$txCount',
                  _pdfPrimary, _pdfLightGrey)),
          pw.SizedBox(width: 8),
          pw.Expanded(
              child: _pdfSummaryCard('Rata-rata/Transaksi',
                  CurrencyFormatter.format(avgTx), _pdfWarning, _pdfLightGrey)),
        ]),
        pw.SizedBox(height: 16),

        _pdfSectionTitle('Laporan Laba Rugi', _pdfPrimary),
        pw.SizedBox(height: 8),
        pw.Container(
          padding: const pw.EdgeInsets.all(14),
          decoration: pw.BoxDecoration(
            color: _pdfLightGrey,
            borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
          ),
          child: pw.Column(
            children: [
              _pdfLRRow('Omzet Penjualan',
                  CurrencyFormatter.format(omzet), _pdfSuccess),
              _pdfLRRow('HPP (Harga Pokok Penjualan)',
                  '- ${CurrencyFormatter.format(hpp)}', _pdfDanger),
              pw.Divider(thickness: 0.5, color: _pdfGrey),
              _pdfLRRow('Laba Kotor',
                  CurrencyFormatter.format(labaKotor),
                  labaKotor >= 0 ? _pdfSuccess : _pdfDanger,
                  bold: true),
              pw.SizedBox(height: 4),
              _pdfLRRow('Kas Masuk (non-penjualan)',
                  CurrencyFormatter.format(
                      labaData['kas_income_non_sales'] ?? 0),
                  _pdfSuccess),
              _pdfLRRow('Kas Keluar (operasional)',
                  '- ${CurrencyFormatter.format(labaData['kas_expense'] ?? 0)}',
                  _pdfDanger),
              pw.Divider(thickness: 0.5, color: _pdfGrey),
              _pdfLRRow('LABA BERSIH',
                  CurrencyFormatter.format(labaBersih),
                  labaBersih >= 0 ? _pdfSuccess : _pdfDanger,
                  bold: true),
              _pdfLRRow('Margin Laba Bersih',
                  '${margin.toStringAsFixed(1)}%',
                  margin >= 10 ? _pdfSuccess : _pdfDanger),
            ],
          ),
        ),
        pw.SizedBox(height: 16),

        _pdfSectionTitle('Laporan Kas', _pdfPrimary),
        pw.SizedBox(height: 8),
        pw.Row(children: [
          pw.Expanded(
              child: _pdfSummaryCard('Kas Masuk',
                  CurrencyFormatter.format(income), _pdfSuccess, _pdfLightGrey)),
          pw.SizedBox(width: 8),
          pw.Expanded(
              child: _pdfSummaryCard('Kas Keluar',
                  CurrencyFormatter.format(expense), _pdfDanger, _pdfLightGrey)),
          pw.SizedBox(width: 8),
          pw.Expanded(
              child: _pdfSummaryCard(
                  'Saldo Bersih',
                  CurrencyFormatter.format(saldo),
                  saldo >= 0 ? _pdfSuccess : _pdfDanger,
                  _pdfLightGrey)),
        ]),
        pw.SizedBox(height: 16),

        if (lowStockProducts.isNotEmpty) ...[
          _pdfSectionTitle('Produk Stok Hampir Habis', _pdfWarning),
          pw.SizedBox(height: 8),
          pw.Table(
            border: pw.TableBorder.all(color: _pdfLightGrey, width: 0.5),
            children: [
              pw.TableRow(
                decoration: pw.BoxDecoration(color: _pdfWarning.shade(0.8)),
                children: [
                  _pdfTableCell('Nama Produk', isHeader: true),
                  _pdfTableCell('Stok', isHeader: true),
                  _pdfTableCell('Min.', isHeader: true),
                  _pdfTableCell('Status', isHeader: true),
                ],
              ),
              ...lowStockProducts.map((p) {
                final isOut = p.stock == 0;
                return pw.TableRow(children: [
                  _pdfTableCell(p.name),
                  _pdfTableCell('${p.stock} ${p.unit}',
                      color: isOut ? _pdfDanger : _pdfWarning),
                  _pdfTableCell('${p.minStock} ${p.unit}'),
                  _pdfTableCell(
                      isOut ? 'Habis' : 'Hampir Habis',
                      color: isOut ? _pdfDanger : _pdfWarning,
                      bold: true),
                ]);
              }),
            ],
          ),
        ] else ...[
          _pdfSectionTitle('Status Stok', _pdfPrimary),
          pw.SizedBox(height: 8),
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: _pdfSuccess.shade(0.1),
              borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
            ),
            child: pw.Text('✓  Semua stok dalam kondisi aman',
                style: pw.TextStyle(
                    color: _pdfSuccess,
                    fontWeight: pw.FontWeight.bold,
                    fontSize: 10)),
          ),
        ],
        pw.SizedBox(height: 20),
        pw.Divider(thickness: 0.5, color: _pdfGrey),
        pw.SizedBox(height: 6),
        pw.Text(
          'Laporan digenerate otomatis oleh $storeName • $printDate',
          style: const pw.TextStyle(fontSize: 8, color: _pdfGrey),
          textAlign: pw.TextAlign.center,
        ),
      ],
    ));

    return doc.save();
  }

  pw.Widget _pdfSectionTitle(String title, PdfColor color) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: pw.BoxDecoration(
        color: color.shade(0.15),
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(6)),
        border: pw.Border(left: pw.BorderSide(color: color, width: 4)),
      ),
      child: pw.Text(title,
          style: pw.TextStyle(
              fontSize: 12,
              fontWeight: pw.FontWeight.bold,
              color: color)),
    );
  }

  pw.Widget _pdfSummaryCard(
      String label, String value, PdfColor color, PdfColor bg) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        color: bg,
        borderRadius: const pw.BorderRadius.all(pw.Radius.circular(8)),
        border: pw.Border.all(color: color.shade(0.3), width: 0.5),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(label, style: const pw.TextStyle(fontSize: 8, color: _pdfGrey)),
          pw.SizedBox(height: 4),
          pw.Text(value,
              style: pw.TextStyle(
                  fontSize: 11,
                  fontWeight: pw.FontWeight.bold,
                  color: color)),
        ],
      ),
    );
  }

  pw.Widget _pdfLRRow(String label, String value, PdfColor color,
      {bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label,
              style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
                  color: const PdfColor.fromInt(0xFF374151))),
          pw.Text(value,
              style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
                  color: color)),
        ],
      ),
    );
  }

  pw.Widget _pdfTableCell(String text,
      {bool isHeader = false, bool bold = false, PdfColor? color}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: isHeader ? 9 : 8,
          fontWeight: (isHeader || bold)
              ? pw.FontWeight.bold
              : pw.FontWeight.normal,
          color: isHeader
              ? PdfColors.white
              : color ?? const PdfColor.fromInt(0xFF111827),
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final String label, value, current;
  final void Function(String) onTap;
  const _Chip(this.label, this.value, this.current, this.onTap);

  @override
  Widget build(BuildContext context) {
    final sel = value == current;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: sel ? Colors.white : null,
            )),
        selected: sel,
        onSelected: (_) => onTap(value),
        selectedColor: AppColors.primary,
      ),
    );
  }
}

class _DateRange {
  final DateTime start, end;
  const _DateRange(this.start, this.end);

  @override
  bool operator ==(Object other) =>
      other is _DateRange &&
      other.start.isAtSameMomentAs(start) &&
      other.end.isAtSameMomentAs(end);

  @override
  int get hashCode => Object.hash(start, end);
}

final _salesChartProvider =
    StreamProvider.autoDispose.family<List<Map<String, dynamic>>, _DateRange>(
  (ref, range) => ref
      .watch(databaseProvider)
      .reportsDao
      .watchDailySalesChart(range.start, range.end),
);

// ── PROVIDER BARU UNTUK METODE PEMBAYARAN DAN PRODUK TERLARIS ────────────────

final _paymentMethodProvider = FutureProvider.autoDispose.family<Map<String, double>, _DateRange>((ref, range) async {
  final db = ref.watch(databaseProvider);
  final txList = await db.transactionsDao.getTransactionsByDate(range.start, range.end);
  double tunai = 0, qris = 0, transfer = 0, hutang = 0;
  for (final tx in txList) {
    final m = tx.paymentMethod?.toLowerCase() ?? 'tunai';
    if (m == 'tunai') tunai += tx.total;
    else if (m == 'qris') qris += tx.total;
    else if (m == 'transfer') transfer += tx.total;
    else if (m == 'hutang') hutang += tx.total;
    else tunai += tx.total;
  }
  // Nota Manual dihitung terpisah (bukan Tunai) supaya tetap kelihatan
  // transparan mana omzet dari kasir otomatis vs nota manual.
  final notaList = await db.manualNotasDao.getBetween(range.start, range.end);
  final manual = notaList.fold<double>(0, (s, n) => s + n.total);
  return {'Tunai': tunai, 'QRIS': qris, 'Transfer': transfer, 'Hutang': hutang, 'Manual': manual};
});

final _topProductsProvider = FutureProvider.autoDispose.family<List<Map<String, dynamic>>, _DateRange>((ref, range) async {
  final db = ref.watch(databaseProvider);
  final txList = await db.transactionsDao.getTransactionsByDate(range.start, range.end);
  Map<String, int> productQty = {};
  Map<String, double> productOmzet = {};
  for (final tx in txList) {
    final items = await db.transactionsDao.getTransactionItems(tx.id);
    for (final item in items) {
      productQty[item.productName] = (productQty[item.productName] ?? 0) + item.quantity;
      productOmzet[item.productName] = (productOmzet[item.productName] ?? 0) + item.subtotal;
    }
  }
  // Item nota manual (ketik bebas, tidak terhubung Products) ikut dihitung
  // supaya "Produk Terlaris" mencerminkan seluruh penjualan, bukan cuma
  // kasir otomatis.
  final notaList = await db.manualNotasDao.getBetween(range.start, range.end);
  for (final nota in notaList) {
    for (final item in decodeManualNotaItems(nota.itemsJson)) {
      if (item.name.trim().isEmpty) continue;
      productQty[item.name] = (productQty[item.name] ?? 0) + item.qty;
      productOmzet[item.name] = (productOmzet[item.name] ?? 0) + item.total;
    }
  }
  final sorted = productQty.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
  return sorted.take(5).map((e) => {
    'name': e.key,
    'qty': e.value,
    'omzet': productOmzet[e.key]!
  }).toList();
});

/// Agregasi omzet & jumlah nota manual PER HARI (key format 'yyyy-MM-dd',
/// sama seperti kolom `tanggal` dari reportsDao.watchDailySalesChart) —
/// dipakai untuk digabung ke grafik & ringkasan penjualan harian.
final _manualNotaChartProvider = FutureProvider.autoDispose
    .family<Map<String, Map<String, dynamic>>, _DateRange>((ref, range) async {
  final db = ref.watch(databaseProvider);
  final notaList = await db.manualNotasDao.getBetween(range.start, range.end);
  final fmt = DateFormat('yyyy-MM-dd');
  final Map<String, double> omzetByDay = {};
  final Map<String, int> countByDay = {};
  for (final n in notaList) {
    final key = fmt.format(n.createdAt.toLocal());
    omzetByDay[key] = (omzetByDay[key] ?? 0) + n.total;
    countByDay[key] = (countByDay[key] ?? 0) + 1;
  }
  return {
    for (final k in omzetByDay.keys) k: {'omzet': omzetByDay[k]!, 'jumlah': countByDay[k]!}
  };
});

/// Gabungkan baris chart harian dari transaksi (SQL, live via Stream) dengan
/// agregasi harian nota manual (Dart, FutureProvider) jadi satu daftar
/// terurut tanggal — supaya Total Omzet/Transaksi/grafik/detail-harian di
/// Laporan mencerminkan SELURUH penjualan (otomatis + manual).
List<Map<String, dynamic>> _mergeDailySales(
    List<Map<String, dynamic>> txRows, Map<String, Map<String, dynamic>> manualByDay) {
  if (manualByDay.isEmpty) return txRows;
  final Map<String, Map<String, dynamic>> merged = {
    for (final r in txRows) r['tanggal'] as String: Map<String, dynamic>.from(r)
  };
  manualByDay.forEach((day, v) {
    if (merged.containsKey(day)) {
      merged[day]!['omzet'] = (merged[day]!['omzet'] as num) + (v['omzet'] as num);
      merged[day]!['jumlah'] = (merged[day]!['jumlah'] as num) + (v['jumlah'] as num);
    } else {
      merged[day] = {'tanggal': day, 'omzet': v['omzet'], 'jumlah': v['jumlah']};
    }
  });
  final rows = merged.values.toList()
    ..sort((a, b) => (a['tanggal'] as String).compareTo(b['tanggal'] as String));
  return rows;
}

class _SalesTab extends ConsumerWidget {
  final DateTime start, end;
  const _SalesTab({required this.start, required this.end});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final salesAsync  = ref.watch(_salesChartProvider(_DateRange(start, end)));
    final manualAsync = ref.watch(_manualNotaChartProvider(_DateRange(start, end)));

    return salesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Text('Error: $e',
            style: const TextStyle(color: AppColors.danger)),
      ),
      data: (txData) {
        // Nota manual digabung ke data chart transaksi per-hari begitu
        // sudah termuat; selama masih loading, tampilkan dulu data
        // transaksi saja (tidak nge-block seluruh tab).
        final data = _mergeDailySales(txData, manualAsync.asData?.value ?? {});
        final omzet = data.fold<double>(0, (s, r) => s + (r['omzet'] as num));
        final count = data.fold<int>(0, (s, r) => s + (r['jumlah'] as int));
        final avg = count > 0 ? omzet / count : 0.0;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(children: [
                Expanded(
                    child: _InfoCard(
                  title: 'Total Omzet',
                  value: CurrencyFormatter.formatCompact(omzet),
                  icon: Icons.trending_up_rounded,
                  color: AppColors.success,
                )),
                const SizedBox(width: 10),
                Expanded(
                    child: _InfoCard(
                  title: 'Transaksi',
                  value: '$count',
                  icon: Icons.receipt_long_rounded,
                  color: AppColors.primary,
                )),
              ]),
              const SizedBox(height: 10),
              _InfoCard(
                title: 'Rata-rata per Transaksi',
                value: CurrencyFormatter.format(avg.toDouble()),
                icon: Icons.analytics_outlined,
                color: AppColors.warning,
              ),
              const SizedBox(height: 20),

              if (data.isNotEmpty) ...[
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Grafik Penjualan',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 180,
                  child: BarChart(BarChartData(
                    barGroups: data.asMap().entries.map((e) {
                      return BarChartGroupData(
                        x: e.key,
                        barRods: [
                          BarChartRodData(
                            toY: (e.value['omzet'] as num).toDouble(),
                            color: AppColors.primary,
                            width: 14,
                            borderRadius: BorderRadius.circular(4),
                          )
                        ],
                      );
                    }).toList(),
                    titlesData: FlTitlesData(
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 55,
                          getTitlesWidget: (v, _) => Text(
                              CurrencyFormatter.formatCompact(v),
                              style: const TextStyle(fontSize: 9)),
                        ),
                      ),
                      bottomTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                    ),
                    gridData: FlGridData(
                        getDrawingHorizontalLine: (_) => FlLine(
                            color: Colors.grey.shade200,
                            strokeWidth: 1)),
                    borderData: FlBorderData(show: false),
                  )),
                ),
                const SizedBox(height: 20),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Detail Harian',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 8),
                ...data.map((row) {
                  final dateRaw = row['tanggal'];
                  String dateStr = '';
                  if (dateRaw is String) {
                    try {
                      final dt = DateTime.parse(dateRaw);
                      dateStr = DateFormat('EEE, dd MMM', 'id').format(dt);
                    } catch (_) {
                      dateStr = dateRaw.toString();
                    }
                  }
                  return Builder(builder: (context) {
                    final isDark = Theme.of(context).brightness == Brightness.dark;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 4),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: isDark ? AppColors.darkBorder : Colors.grey.shade100),
                      ),
                      child: Row(children: [
                        Expanded(
                            child: Text(dateStr,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13))),
                        Text('${row['jumlah']} transaksi',
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade500)),
                        const SizedBox(width: 12),
                        Text(
                            CurrencyFormatter.formatCompact(
                                (row['omzet'] as num).toDouble()),
                            style: const TextStyle(
                                color: AppColors.success,
                                fontWeight: FontWeight.w700,
                                fontSize: 13)),
                      ]),
                    );
                  });
                }),
                
                const SizedBox(height: 24),
                // ── TAMBAHAN FITUR: DONUT CHART METODE PEMBAYARAN ────────────
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Metode Pembayaran',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 12),
                Consumer(builder: (ctx, ref, _) {
                  final pmAsync = ref.watch(_paymentMethodProvider(_DateRange(start, end)));
                  return pmAsync.when(
                    loading: () => const CircularProgressIndicator(),
                    error: (e, _) => Text('Error: $e'),
                    data: (pm) {
                      final total = pm.values.fold(0.0, (a, b) => a + b);
                      if (total == 0) return const Text('Belum ada data', style: TextStyle(color: Colors.grey));
                      return Container(
                        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                        decoration: BoxDecoration(
                          color: Theme.of(ctx).cardColor,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: Theme.of(ctx).brightness == Brightness.dark ? AppColors.darkBorder : Colors.grey.shade200),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 1,
                              child: SizedBox(
                                height: 120,
                                child: PieChart(
                                  PieChartData(
                                    sectionsSpace: 2,
                                    centerSpaceRadius: 35,
                                    sections: [
                                      if (pm['Tunai']! > 0) PieChartSectionData(value: pm['Tunai']!, color: AppColors.success, title: '${(pm['Tunai']!/total*100).toStringAsFixed(0)}%', radius: 25, titleStyle: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
                                      if (pm['QRIS']! > 0) PieChartSectionData(value: pm['QRIS']!, color: AppColors.info, title: '${(pm['QRIS']!/total*100).toStringAsFixed(0)}%', radius: 25, titleStyle: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
                                      if (pm['Transfer']! > 0) PieChartSectionData(value: pm['Transfer']!, color: AppColors.primary, title: '${(pm['Transfer']!/total*100).toStringAsFixed(0)}%', radius: 25, titleStyle: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
                                      if (pm['Hutang']! > 0) PieChartSectionData(value: pm['Hutang']!, color: AppColors.warning, title: '${(pm['Hutang']!/total*100).toStringAsFixed(0)}%', radius: 25, titleStyle: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
                                      if (pm['Manual']! > 0) PieChartSectionData(value: pm['Manual']!, color: _manualColor, title: '${(pm['Manual']!/total*100).toStringAsFixed(0)}%', radius: 25, titleStyle: const TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
                                    ],
                                  )
                                )
                              )
                            ),
                            const SizedBox(width: 20),
                            Expanded(
                              flex: 1,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _Legend('Tunai (${CurrencyFormatter.formatCompact(pm['Tunai']!)})', AppColors.success), const SizedBox(height: 6),
                                  _Legend('QRIS (${CurrencyFormatter.formatCompact(pm['QRIS']!)})', AppColors.info), const SizedBox(height: 6),
                                  _Legend('Transfer (${CurrencyFormatter.formatCompact(pm['Transfer']!)})', AppColors.primary), const SizedBox(height: 6),
                                  _Legend('Hutang (${CurrencyFormatter.formatCompact(pm['Hutang']!)})', AppColors.warning), const SizedBox(height: 6),
                                  _Legend('Manual (${CurrencyFormatter.formatCompact(pm['Manual']!)})', _manualColor),
                                ]
                              )
                            )
                          ]
                        ),
                      );
                    }
                  );
                }),
                
                const SizedBox(height: 24),
                // ── TAMBAHAN FITUR: PRODUK TERLARIS ──────────────────────────
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Produk Terlaris',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                ),
                const SizedBox(height: 12),
                Consumer(builder: (ctx, ref, _) {
                  final tpAsync = ref.watch(_topProductsProvider(_DateRange(start, end)));
                  return tpAsync.when(
                    loading: () => const CircularProgressIndicator(),
                    error: (e, _) => Text('Error: $e'),
                    data: (products) {
                      if (products.isEmpty) return const Text('Belum ada data', style: TextStyle(color: Colors.grey));
                      return Column(
                        children: products.map((p) => Builder(builder: (context) {
                          final isDark = Theme.of(context).brightness == Brightness.dark;
                          return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(context).cardColor,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: isDark ? AppColors.darkBorder : Colors.grey.shade100),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                                child: const Icon(Icons.star_rounded, color: AppColors.primary, size: 20),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(p['name'], style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                    const SizedBox(height: 2),
                                    Text('${p['qty']} terjual', style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
                                  ]
                                )
                              ),
                              Text(CurrencyFormatter.formatCompact(p['omzet']), style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.success, fontSize: 13)),
                            ],
                          ),
                        );
                        })).toList()
                      );
                    }
                  );
                }),
                const SizedBox(height: 100),

              ] else
                const Padding(
                  padding: EdgeInsets.all(40),
                  child: Text('Belum ada data penjualan',
                      style: TextStyle(color: Colors.grey)),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ArusKasSection extends ConsumerWidget {
  final DateRange range;
  const _ArusKasSection({required this.range});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final arusAsync = ref.watch(arusKasHarianProvider(range));
    final incKatAsync = ref.watch(kasIncomeByKategoriProvider(range));
    final expKatAsync = ref.watch(kasExpenseByKategoriProvider(range));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Arus Kas Harian',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        const SizedBox(height: 12),

        arusAsync.when(
          data: (rows) {
            if (rows.isEmpty) return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: Text('Belum ada data arus kas', style: TextStyle(color: AppColors.textSecondary))),
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 180,
                  child: BarChart(BarChartData(
                    barGroups: rows.asMap().entries.map((e) {
                      return BarChartGroupData(
                        x: e.key,
                        barsSpace: 4,
                        barRods: [
                          BarChartRodData(
                            toY: e.value.masuk,
                            color: AppColors.success,
                            width: 9,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          BarChartRodData(
                            toY: e.value.keluar,
                            color: AppColors.danger,
                            width: 9,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ],
                      );
                    }).toList(),
                    titlesData: FlTitlesData(
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 55,
                          getTitlesWidget: (v, _) => Text(
                              CurrencyFormatter.formatCompact(v),
                              style: const TextStyle(fontSize: 8)),
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 22,
                          getTitlesWidget: (v, _) {
                            final i = v.toInt();
                            if (i >= rows.length) return const SizedBox();
                            final dt = DateTime.tryParse(rows[i].tanggal);
                            if (dt == null) return const SizedBox();
                            return Text(
                              DateFormat('dd/MM').format(dt),
                              style: const TextStyle(fontSize: 8),
                            );
                          },
                        ),
                      ),
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    ),
                    gridData: FlGridData(
                        getDrawingHorizontalLine: (_) => FlLine(
                            color: Colors.grey.shade100, strokeWidth: 1)),
                    borderData: FlBorderData(show: false),
                  )),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _Legend('Masuk', AppColors.success),
                    const SizedBox(width: 16),
                    _Legend('Keluar', AppColors.danger),
                  ],
                ),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text('Error: \$e'),
        ),
        const SizedBox(height: 16),

        incKatAsync.when(
          data: (items) {
            if (items.isEmpty) return const SizedBox();
            final total = items.fold<double>(0, (s, k) => s + k.total);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Breakdown Kas Masuk',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                const SizedBox(height: 8),
                ...items.map((k) => _KatRow(item: k, total: total, color: AppColors.success)),
                const SizedBox(height: 12),
              ],
            );
          },
          loading: () => const SizedBox(),
          error: (_, __) => const SizedBox(),
        ),

        expKatAsync.when(
          data: (items) {
            if (items.isEmpty) return const SizedBox();
            final total = items.fold<double>(0, (s, k) => s + k.total);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Breakdown Kas Keluar',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                const SizedBox(height: 8),
                ...items.map((k) => _KatRow(item: k, total: total, color: AppColors.danger)),
              ],
            );
          },
          loading: () => const SizedBox(),
          error: (_, __) => const SizedBox(),
        ),
      ],
    );
  }
}

class _ArusKasTab extends ConsumerWidget {
  final DateRange range;
  const _ArusKasTab({required this.range});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(kasSummaryProvider(range));
    final arusAsync = ref.watch(arusKasHarianProvider(range));
    final incKatAsync = ref.watch(kasIncomeByKategoriProvider(range));
    final expKatAsync = ref.watch(kasExpenseByKategoriProvider(range));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          summaryAsync.when(
            data: (s) => Column(children: [
              Row(children: [
                Expanded(
                    child: _InfoCard(
                  title: 'Kas Masuk',
                  value: CurrencyFormatter.formatCompact(s.totalIncome),
                  icon: Icons.arrow_circle_down_rounded,
                  color: AppColors.success,
                )),
                const SizedBox(width: 10),
                Expanded(
                    child: _InfoCard(
                  title: 'Kas Keluar',
                  value: CurrencyFormatter.formatCompact(s.totalExpense),
                  icon: Icons.arrow_circle_up_rounded,
                  color: AppColors.danger,
                )),
              ]),
              const SizedBox(height: 10),
              _InfoCard(
                title: 'Saldo Bersih',
                value: CurrencyFormatter.format(s.saldo),
                icon: Icons.account_balance_wallet_rounded,
                color: s.saldo >= 0 ? AppColors.primary : AppColors.danger,
              ),
            ]),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Error: $e'),
          ),
          const SizedBox(height: 20),

          arusAsync.when(
            data: (rows) {
              if (rows.isEmpty) return const SizedBox();
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Arus Kas Harian',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 14)),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 200,
                    child: BarChart(BarChartData(
                      barGroups: rows.asMap().entries.map((e) {
                        return BarChartGroupData(
                          x: e.key,
                          barsSpace: 4,
                          barRods: [
                            BarChartRodData(
                              toY: e.value.masuk,
                              color: AppColors.success,
                              width: 9,
                              borderRadius: BorderRadius.circular(3),
                            ),
                            BarChartRodData(
                              toY: e.value.keluar,
                              color: AppColors.danger,
                              width: 9,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ],
                        );
                      }).toList(),
                      titlesData: FlTitlesData(
                        leftTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 55,
                            getTitlesWidget: (v, _) => Text(
                                CurrencyFormatter.formatCompact(v),
                                style: const TextStyle(fontSize: 8)),
                          ),
                        ),
                        bottomTitles: AxisTitles(
                          sideTitles: SideTitles(
                            showTitles: true,
                            reservedSize: 22,
                            getTitlesWidget: (v, _) {
                              final i = v.toInt();
                              if (i >= rows.length) return const SizedBox();
                              final dt = DateTime.tryParse(rows[i].tanggal);
                              if (dt == null) return const SizedBox();
                              return Text(
                                DateFormat('dd/MM').format(dt),
                                style: const TextStyle(fontSize: 8),
                              );
                            },
                          ),
                        ),
                        topTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                        rightTitles: const AxisTitles(
                            sideTitles: SideTitles(showTitles: false)),
                      ),
                      gridData: FlGridData(
                          getDrawingHorizontalLine: (_) => FlLine(
                              color: Colors.grey.shade100, strokeWidth: 1)),
                      borderData: FlBorderData(show: false),
                    )),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _Legend('Masuk', AppColors.success),
                      const SizedBox(width: 16),
                      _Legend('Keluar', AppColors.danger),
                    ],
                  ),
                  const SizedBox(height: 20),

                  const Text('Detail Arus Kas',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 14)),
                  const SizedBox(height: 8),
                  ...rows.map((r) {
                    final dt = DateTime.tryParse(r.tanggal);
                    final label = dt != null
                        ? DateFormat('EEE, dd MMM yyyy', 'id').format(dt)
                        : r.tanggal;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).cardColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Theme.of(context).brightness == Brightness.dark ? AppColors.darkBorder : Colors.grey.shade100),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(label,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 12,
                                  color: AppColors.textSecondary)),
                          const SizedBox(height: 6),
                          Row(children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Masuk',
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: AppColors.textHint)),
                                  Text(CurrencyFormatter.format(r.masuk),
                                      style: const TextStyle(
                                          color: AppColors.success,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13)),
                                ],
                              ),
                            ),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Keluar',
                                      style: TextStyle(
                                          fontSize: 10,
                                          color: AppColors.textHint)),
                                  Text(CurrencyFormatter.format(r.keluar),
                                      style: const TextStyle(
                                          color: AppColors.danger,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 13)),
                                ],
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                const Text('Net',
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: AppColors.textHint)),
                                Text(
                                  (r.saldo >= 0 ? '+' : '') +
                                      CurrencyFormatter.format(r.saldo),
                                  style: TextStyle(
                                      color: r.saldo >= 0
                                          ? AppColors.success
                                          : AppColors.danger,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13),
                                ),
                              ],
                            ),
                          ]),
                        ],
                      ),
                    );
                  }),
                ],
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Text('Error: $e'),
          ),

          const SizedBox(height: 20),

          incKatAsync.when(
            data: (items) {
              if (items.isEmpty) return const SizedBox();
              final total = items.fold<double>(0, (s, k) => s + k.total);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Breakdown Kas Masuk',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 14)),
                  const SizedBox(height: 8),
                  ...items.map((k) => _KatRow(
                      item: k, total: total, color: AppColors.success)),
                  const SizedBox(height: 16),
                ],
              );
            },
            loading: () => const SizedBox(),
            error: (_, __) => const SizedBox(),
          ),

          expKatAsync.when(
            data: (items) {
              if (items.isEmpty) return const SizedBox();
              final total = items.fold<double>(0, (s, k) => s + k.total);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Breakdown Kas Keluar',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 14)),
                  const SizedBox(height: 8),
                  ...items.map((k) => _KatRow(
                      item: k, total: total, color: AppColors.danger)),
                  const SizedBox(height: 80),
                ],
              );
            },
            loading: () => const SizedBox(),
            error: (_, __) => const SizedBox(),
          ),
        ],
      ),
    );
  }
}

class _LabaRugiTab extends ConsumerWidget {
  final DateRange range;
  const _LabaRugiTab({required this.range});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final labaAsync = ref.watch(labaRugiProvider(range));

    return labaAsync.when(
      data: (lr) => SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _LabaRugiCard(data: lr),
            const SizedBox(height: 16),
            _PenjelasanKaruCard(data: lr),
            const SizedBox(height: 80),
          ],
        ),
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }
}

class _LabaRugiCard extends StatelessWidget {
  final LabaRugiData data;
  const _LabaRugiCard({required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 12,
              offset: const Offset(0, 3)),
        ],
      ),
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                const Icon(Icons.bar_chart_rounded,
                    color: Colors.white, size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text('Laporan Laba Rugi',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 15)),
                ),
                Text(
                  DateFormat('dd MMM yyyy', 'id').format(DateTime.now()),
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _LRRow(
                  label: 'Total Penjualan (Omzet)',
                  value: data.omzet,
                  color: AppColors.success,
                ),
                _LRRow(
                  label: 'HPP (Harga Pokok Penjualan)',
                  value: -data.hpp,
                  color: AppColors.danger,
                  prefix: '- ',
                ),
                const Divider(height: 20),
                _LRRow(
                  label: 'Laba Kotor',
                  value: data.labaKotor,
                  color: data.labaKotor >= 0
                      ? AppColors.success
                      : AppColors.danger,
                  bold: true,
                ),
                const SizedBox(height: 8),
                if (data.kasIncomeNonSales > 0)
                  _LRRow(
                    label: 'Pendapatan Lain (non-penjualan)',
                    value: data.kasIncomeNonSales,
                    color: AppColors.success,
                  ),
                if (data.kasExpense > 0)
                  _LRRow(
                    label: 'Biaya Operasional',
                    value: -data.kasExpense,
                    color: AppColors.danger,
                    prefix: '- ',
                  ),
                const Divider(height: 20),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: (data.labaBersih >= 0
                            ? AppColors.success
                            : AppColors.danger)
                        .withOpacity(0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: (data.labaBersih >= 0
                              ? AppColors.success
                              : AppColors.danger)
                          .withOpacity(0.2),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        data.labaBersih >= 0
                            ? Icons.trending_up_rounded
                            : Icons.trending_down_rounded,
                        color: data.labaBersih >= 0
                            ? AppColors.success
                            : AppColors.danger,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text('LABA BERSIH',
                            style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 14)),
                      ),
                      Text(
                        CurrencyFormatter.format(data.labaBersih.abs()),
                        style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                            color: data.labaBersih >= 0
                                ? AppColors.success
                                : AppColors.danger),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _MarginBar(margin: data.marginPersen, omzet: data.omzet),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PenjelasanKaruCard extends StatelessWidget {
  final LabaRugiData data;
  const _PenjelasanKaruCard({required this.data});

  @override
  Widget build(BuildContext context) {
    if (data.omzet == 0 && data.hpp == 0) return const SizedBox();

    String status;
    String deskripsi;
    Color color;
    IconData icon;

    if (data.labaBersih > 0 && data.marginPersen >= 15) {
      status = 'Usaha Berjalan Baik 🎉';
      deskripsi = 'Margin laba bersih ${data.marginPersen.toStringAsFixed(1)}% — cukup sehat untuk warung/UMKM. Pertahankan pengelolaan biaya operasional!';
      color = AppColors.success;
      icon = Icons.thumb_up_rounded;
    } else if (data.labaBersih > 0) {
      status = 'Usaha Menguntungkan ✅';
      deskripsi = 'Margin ${data.marginPersen.toStringAsFixed(1)}% — masih untung, namun bisa ditingkatkan dengan mengurangi biaya atau menaikkan harga jual produk.';
      color = AppColors.warning;
      icon = Icons.info_outline_rounded;
    } else {
      status = 'Perlu Perhatian ⚠️';
      deskripsi = 'Usaha mengalami kerugian. Tinjau kembali harga jual, biaya operasional, dan HPP untuk meningkatkan profitabilitas.';
      color = AppColors.danger;
      icon = Icons.warning_amber_rounded;
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(status,
                    style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: color)),
                const SizedBox(height: 4),
                Text(deskripsi,
                    style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                        height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LRRow extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  final bool bold;
  final String prefix;
  const _LRRow({
    required this.label,
    required this.value,
    required this.color,
    this.bold = false,
    this.prefix = '',
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: TextStyle(
                    fontSize: bold ? 13 : 12,
                    fontWeight: bold ? FontWeight.w700 : FontWeight.normal,
                    color: bold
                        ? (isDark ? Colors.white : Colors.black87)
                        : (isDark ? Colors.grey.shade400 : Colors.grey.shade700))),
          ),
          Text(
            '$prefix${CurrencyFormatter.format(value.abs())}',
            style: TextStyle(
                fontSize: bold ? 14 : 12,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                color: color),
          ),
        ],
      ),
    );
  }
}

class _MarginBar extends StatelessWidget {
  final double margin, omzet;
  const _MarginBar({required this.margin, required this.omzet});

  @override
  Widget build(BuildContext context) {
    if (omzet == 0) return const SizedBox();
    final pct = margin.clamp(0.0, 100.0);
    final color = margin >= 20
        ? AppColors.success
        : margin >= 10
            ? AppColors.warning
            : AppColors.danger;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Margin Laba Bersih: ',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
            Text('${margin.toStringAsFixed(1)}%',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: color)),
            const Spacer(),
            Text(
              margin >= 20
                  ? '🟢 Baik'
                  : margin >= 10
                      ? '🟡 Cukup'
                      : '🔴 Rendah',
              style: TextStyle(fontSize: 11, color: color),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: pct / 100,
            backgroundColor: Colors.grey.shade200,
            valueColor: AlwaysStoppedAnimation(color),
            minHeight: 6,
          ),
        ),
      ],
    );
  }
}

class _CashTab extends ConsumerStatefulWidget {
  final DateTime start, end;
  final DateRange range;
  const _CashTab({required this.start, required this.end, required this.range});

  @override
  ConsumerState<_CashTab> createState() => _CashTabState();
}

class _CashTabState extends ConsumerState<_CashTab> {
  int _refreshKey = 0;

  void _refresh() => setState(() => _refreshKey++);

  void _openForm({String? initialType}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ProviderScope(
        parent: ProviderScope.containerOf(context),
        child: _CashFlowForm(
          initialType: initialType ?? 'income',
          onSaved: _refresh,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Tambah Kas',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      ),
      body: FutureBuilder<Map<String, double>>(
        key: ValueKey(_refreshKey),
        future: ref
            .read(databaseProvider)
            .reportsDao
            .getCashReport(widget.start, widget.end),
        builder: (_, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final d = snap.data!;
          final saldo = d['saldo'] ?? 0;

          return StreamBuilder<List<CashFlow>>(
            stream: ref
                .read(databaseProvider)
                .reportsDao
                .watchCashFlows(widget.start, widget.end),
            builder: (_, listSnap) {
              final flows = listSnap.data ?? [];

              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                children: [
                  _ArusKasSection(range: widget.range),
                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 12),
                  const Text('Kas Manual',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  const SizedBox(height: 12),
                  Row(children: [
                    Expanded(
                        child: _InfoCard(
                      title: 'Kas Masuk',
                      value: CurrencyFormatter.format(d['income']!),
                      icon: Icons.arrow_circle_down_rounded,
                      color: AppColors.success,
                    )),
                    const SizedBox(width: 10),
                    Expanded(
                        child: _InfoCard(
                      title: 'Kas Keluar',
                      value: CurrencyFormatter.format(d['expense']!),
                      icon: Icons.arrow_circle_up_rounded,
                      color: AppColors.danger,
                    )),
                  ]),
                  const SizedBox(height: 10),
                  _InfoCard(
                    title: 'Saldo Bersih',
                    value: CurrencyFormatter.format(saldo),
                    icon: Icons.account_balance_wallet_rounded,
                    color: saldo >= 0 ? AppColors.primary : AppColors.danger,
                  ),
                  const SizedBox(height: 20),

                  Row(children: [
                    Expanded(
                        child: _ActionBtn(
                      label: '+ Kas Masuk',
                      color: AppColors.success,
                      icon: Icons.add_circle_outline_rounded,
                      onTap: () => _openForm(initialType: 'income'),
                    )),
                    const SizedBox(width: 10),
                    Expanded(
                        child: _ActionBtn(
                      label: '− Kas Keluar',
                      color: AppColors.danger,
                      icon: Icons.remove_circle_outline_rounded,
                      onTap: () => _openForm(initialType: 'expense'),
                    )),
                  ]),
                  const SizedBox(height: 20),

                  const Text('Riwayat',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary)),
                  const SizedBox(height: 10),

                  if (flows.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 32),
                      child: Column(
                        children: [
                          Icon(Icons.receipt_long_outlined,
                              size: 48, color: Colors.grey.shade300),
                          const SizedBox(height: 8),
                          Text('Belum ada catatan kas',
                              style: TextStyle(color: Colors.grey.shade400)),
                        ],
                      ),
                    )
                  else
                    ...flows.map((f) => _CashFlowTile(flow: f)),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;
  const _ActionBtn(
      {required this.label,
      required this.color,
      required this.icon,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w700,
                    fontSize: 13)),
          ],
        ),
      ),
    );
  }
}

class _CashFlowTile extends StatelessWidget {
  final CashFlow flow;
  const _CashFlowTile({required this.flow});

  @override
  Widget build(BuildContext context) {
    final isIncome = flow.type == 'income';
    final color = isIncome ? AppColors.success : AppColors.danger;
    final sign = isIncome ? '+' : '-';

    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isDark ? AppColors.darkBorder : AppColors.border, width: 0.5),
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            isIncome
                ? Icons.arrow_circle_down_rounded
                : Icons.arrow_circle_up_rounded,
            color: color,
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(flow.category,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 13)),
              if (flow.description != null && flow.description!.isNotEmpty)
                Text(flow.description!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary)),
            ],
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '$sign${CurrencyFormatter.format(flow.amount)}',
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: color),
            ),
            Text(
              _fmtDate(flow.createdAt),
              style: const TextStyle(
                  fontSize: 10, color: AppColors.textSecondary),
            ),
          ],
        ),
      ]),
    );
  }

  String _fmtDate(DateTime dt) {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Ags', 'Sep', 'Okt', 'Nov', 'Des'];
    return '${dt.day} ${months[dt.month - 1]} • ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

class _CashFlowForm extends ConsumerStatefulWidget {
  final String initialType;
  final VoidCallback onSaved;
  const _CashFlowForm(
      {required this.initialType, required this.onSaved});

  @override
  ConsumerState<_CashFlowForm> createState() => _CashFlowFormState();
}

class _CashFlowFormState extends ConsumerState<_CashFlowForm> {
  late String _type;
  final _amountCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String _category = '';
  bool _saving = false;

  static const _incomeCategories = [
    'Penjualan', 'Modal Awal', 'Pinjaman', 'Lainnya',
  ];
  static const _expenseCategories = [
    'Pembelian Stok', 'Biaya Operasional', 'Gaji', 'Utilitas', 'Lainnya',
  ];

  List<String> get _categories =>
      _type == 'income' ? _incomeCategories : _expenseCategories;

  @override
  void initState() {
    super.initState();
    _type = widget.initialType;
    _category = _categories.first;
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final raw = _amountCtrl.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (raw.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Masukkan jumlah kas')));
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(databaseProvider).reportsDao.addCashFlow(
            type: _type,
            category: _category,
            amount: double.parse(raw),
            description: _descCtrl.text.trim().isEmpty
                ? null
                : _descCtrl.text.trim(),
          );
      if (mounted) {
        Navigator.pop(context);
        widget.onSaved();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal menyimpan: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isIncome = _type == 'income';
    final accentColor = isIncome ? AppColors.success : AppColors.danger;

    return Container(
      padding: EdgeInsets.only(
        top: 20,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text('Tambah Catatan Kas',
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary)),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() {
                  _type = 'income';
                  _category = _incomeCategories.first;
                }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: _type == 'income'
                        ? AppColors.success
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('↓ Kas Masuk',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: _type == 'income'
                              ? Colors.white
                              : AppColors.textSecondary)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() {
                  _type = 'expense';
                  _category = _expenseCategories.first;
                }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: BoxDecoration(
                    color: _type == 'expense'
                        ? AppColors.danger
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text('↑ Kas Keluar',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: _type == 'expense'
                              ? Colors.white
                              : AppColors.textSecondary)),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _categories.map((cat) {
              final sel = cat == _category;
              return GestureDetector(
                onTap: () => setState(() => _category = cat),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: sel
                        ? accentColor.withOpacity(0.1)
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: sel ? accentColor : Colors.transparent),
                  ),
                  child: Text(cat,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: sel
                              ? accentColor
                              : AppColors.textSecondary)),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _amountCtrl,
            keyboardType: TextInputType.number,
            style: const TextStyle(
                fontWeight: FontWeight.w700, fontSize: 16),
            decoration: InputDecoration(
              prefixText: 'Rp ',
              hintText: '0',
              filled: true,
              fillColor: Colors.grey.shade50,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade200),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade200),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: accentColor, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descCtrl,
            decoration: InputDecoration(
              hintText: 'Keterangan (opsional)',
              filled: true,
              fillColor: Colors.grey.shade50,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade200),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade200),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: accentColor, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: accentColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : Text(
                      isIncome ? 'Simpan Kas Masuk' : 'Simpan Kas Keluar',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }
}

class _StockTab extends ConsumerWidget {
  const _StockTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder(
      future: ref.read(databaseProvider).productsDao.getLowStockProducts(),
      builder: (_, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final list = snap.data!;
        if (list.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle_outline,
                    size: 60, color: AppColors.success),
                SizedBox(height: 12),
                Text('Semua stok aman!',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600)),
                SizedBox(height: 6),
                Text('Tidak ada produk yang hampir habis',
                    style: TextStyle(color: AppColors.textSecondary)),
              ],
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: list.length,
          itemBuilder: (_, i) {
            final p = list[i];
            final isOut = p.stock == 0;
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: (isOut ? AppColors.danger : AppColors.warning)
                            .withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    isOut
                        ? Icons.remove_circle_outline
                        : Icons.warning_amber_rounded,
                    color: isOut ? AppColors.danger : AppColors.warning,
                    size: 20,
                  ),
                ),
                title: Text(p.name,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('Stok minimum: ${p.minStock} ${p.unit}'),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('${p.stock} ${p.unit}',
                        style: TextStyle(
                            color: isOut ? AppColors.danger : AppColors.warning,
                            fontWeight: FontWeight.w700,
                            fontSize: 15)),
                    Text(isOut ? 'Habis' : 'Hampir habis',
                        style: TextStyle(
                            fontSize: 10,
                            color: isOut ? AppColors.danger : AppColors.warning)),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _CategoryTab extends StatelessWidget {
  final DateTime start, end;
  const _CategoryTab({required this.start, required this.end});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _load(context),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snap.data!;
        if (data.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.category_outlined,
                    size: 64, color: Colors.grey.shade300),
                const SizedBox(height: 16),
                Text('Belum ada data penjualan',
                    style: TextStyle(color: Colors.grey.shade400)),
              ],
            ),
          );
        }

        final totalOmzet = data.fold<double>(
            0, (s, r) => s + (r['total_omzet'] as num).toDouble());

        final colors = [
          AppColors.primary, AppColors.success, AppColors.warning,
          AppColors.danger, AppColors.info,
          const Color(0xFF8B5CF6), const Color(0xFFEC4899),
          const Color(0xFF14B8A6), const Color(0xFFF97316),
        ];

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Total Omzet Semua Kategori',
                          style: TextStyle(
                              fontSize: 12, color: AppColors.primary)),
                      const SizedBox(height: 4),
                      Text(CurrencyFormatter.format(totalOmzet),
                          style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: AppColors.primary)),
                    ],
                  ),
                  Text('${data.length} kategori',
                      style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ...data.asMap().entries.map((entry) {
              final i = entry.key;
              final row = entry.value;
              final color = colors[i % colors.length];
              final omzet = (row['total_omzet'] as num).toDouble();
              final qty = (row['total_qty'] as num).toInt();
              final pct = totalOmzet > 0 ? omzet / totalOmzet : 0.0;

              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: color.withOpacity(0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                              color: color, shape: BoxShape.circle)),
                      const SizedBox(width: 8),
                      Expanded(
                          child: Text(row['category_name'] ?? '-',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14))),
                      Text(CurrencyFormatter.format(omzet),
                          style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: color,
                              fontSize: 14)),
                    ]),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: pct,
                        minHeight: 6,
                        backgroundColor: color.withOpacity(0.1),
                        valueColor: AlwaysStoppedAnimation(color),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('$qty item terjual',
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade500)),
                        Text(
                          '${(pct * 100).toStringAsFixed(1)}%',
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: color),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
          ],
        );
      },
    );
  }

  Future<List<Map<String, dynamic>>> _load(BuildContext context) {
    final db = ProviderScope.containerOf(context).read(databaseProvider);
    return db.reportsDao.getSalesByCategory(start, end);
  }
}

class _InfoCard extends StatelessWidget {
  final String title, value;
  final IconData icon;
  final Color color;
  const _InfoCard(
      {required this.title,
      required this.value,
      required this.icon,
      required this.color});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                        fontWeight: FontWeight.w500)),
                const SizedBox(height: 2),
                Text(value,
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: color)),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

class _KatRow extends StatelessWidget {
  final KasKategori item;
  final double total;
  final Color color;
  const _KatRow(
      {required this.item,
      required this.total,
      required this.color});

  @override
  Widget build(BuildContext context) {
    final pct = total > 0 ? item.total / total : 0.0;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(
                child: Text(labelKategoriKas(item.kategori),
                    style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 13))),
            Text(CurrencyFormatter.format(item.total),
                style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: color,
                    fontSize: 13)),
          ]),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 5,
              backgroundColor: color.withOpacity(0.1),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
          const SizedBox(height: 4),
          Text('${item.jumlah}x • ${(pct * 100).toStringAsFixed(1)}%',
              style: const TextStyle(
                  fontSize: 10, color: AppColors.textHint)),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  final String label;
  final Color color;
  const _Legend(this.label, this.color);

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(label,
            style: const TextStyle(
                fontSize: 11, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
      ],
    );
  }
}
