import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:image/image.dart' as img;
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/utils/receipt_pdf_builder.dart';
import '../../providers/database_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/manual_nota_provider.dart';
import '../../../core/utils/manual_nota_printer.dart';
import '../kasir/manual_nota_screen.dart';
import '../../../data/database/app_database.dart';
import '../../../core/utils/bluetooth_permission.dart';

/// Warna khas untuk membedakan entri "Nota Manual" dari transaksi kasir
/// otomatis di daftar Riwayat (lihat _RiwayatEntry).
const _manualColor = Color(0xFF8B5CF6);

// ─────────────────────────────────────────────────────────────────────────────
// Provider
// ─────────────────────────────────────────────────────────────────────────────

final _riwayatStartProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day).subtract(const Duration(days: 6));
});

final _riwayatEndProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day, 23, 59, 59);
});

final _riwayatSearchProvider = StateProvider<String>((ref) => '');

/// Jenis entri di daftar Riwayat gabungan — transaksi Kasir Otomatis
/// (tabel `transactions`) atau Nota Manual (tabel `manual_notas`).
enum _RiwayatKind { transaksi, manual }

/// Wrapper supaya Transaction & ManualNota bisa ditampilkan dalam satu
/// daftar/urutan waktu yang sama tanpa mengubah dua model Drift tersebut.
class _RiwayatEntry {
  final _RiwayatKind kind;
  final DateTime createdAt;
  final String invoiceNumber;
  final double total;
  final Transaction? tx;
  final ManualNota? nota;

  _RiwayatEntry.transaksi(Transaction t)
      : kind = _RiwayatKind.transaksi,
        createdAt = t.createdAt,
        invoiceNumber = t.invoiceNumber,
        total = t.total,
        tx = t,
        nota = null;

  _RiwayatEntry.manual(ManualNota n)
      : kind = _RiwayatKind.manual,
        createdAt = n.createdAt,
        invoiceNumber = n.invoiceNumber,
        total = n.total,
        tx = null,
        nota = n;
}

final _riwayatListProvider = FutureProvider.autoDispose<List<_RiwayatEntry>>((ref) async {
  final db    = ref.watch(databaseProvider);
  final start = ref.watch(_riwayatStartProvider);
  final end   = ref.watch(_riwayatEndProvider);
  final txList   = await db.transactionsDao.getTransactionsByDate(start, end);
  final notaList = await db.manualNotasDao.getBetween(start, end);
  final entries = <_RiwayatEntry>[
    ...txList.map((t) => _RiwayatEntry.transaksi(t)),
    ...notaList.map((n) => _RiwayatEntry.manual(n)),
  ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return entries;
});

// ─────────────────────────────────────────────────────────────────────────────
// Screen Utama
// ─────────────────────────────────────────────────────────────────────────────

class RiwayatScreen extends ConsumerStatefulWidget {
  const RiwayatScreen({super.key});

  @override
  ConsumerState<RiwayatScreen> createState() => _RiwayatScreenState();
}

class _RiwayatScreenState extends ConsumerState<RiwayatScreen> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDateRange(BuildContext context) async {
    final start = ref.read(_riwayatStartProvider);
    final end   = ref.read(_riwayatEndProvider);

    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: start, end: end),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: AppColors.primary),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      ref.read(_riwayatStartProvider.notifier).state = picked.start;
      ref.read(_riwayatEndProvider.notifier).state =
          DateTime(picked.end.year, picked.end.month, picked.end.day, 23, 59, 59);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark     = Theme.of(context).brightness == Brightness.dark;
    final entriesAsync = ref.watch(_riwayatListProvider);
    final start      = ref.watch(_riwayatStartProvider);
    final end        = ref.watch(_riwayatEndProvider);
    final query      = ref.watch(_riwayatSearchProvider).toLowerCase().trim();
    final fmt        = DateFormat('dd/MM/yyyy');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Riwayat Transaksi',
            style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: Column(
        children: [
          // ── Filter tanggal ──────────────────────────────────────────────
          Container(
            margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkCard : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: isDark ? AppColors.darkBorder : AppColors.border,
                  width: 0.5),
            ),
            child: Row(
              children: [
                const Icon(Icons.calendar_today_outlined,
                    size: 16, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${fmt.format(start)}  →  ${fmt.format(end)}',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
                GestureDetector(
                  onTap: () => _pickDateRange(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('Ubah',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700)),
                  ),
                ),
              ],
            ),
          ),

          // ── Search ──────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) =>
                  ref.read(_riwayatSearchProvider.notifier).state = v,
              decoration: InputDecoration(
                hintText: 'Cari no. invoice atau metode...',
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          ref.read(_riwayatSearchProvider.notifier).state = '';
                        },
                      )
                    : null,
              ),
            ),
          ),

          // ── List transaksi ──────────────────────────────────────────────
          Expanded(
            child: entriesAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) =>
                  Center(child: Text('Error: $e')),
              data: (list) {
                // Filter by search
                final filtered = query.isEmpty
                    ? list
                    : list.where((e) =>
                        e.invoiceNumber.toLowerCase().contains(query) ||
                        (e.tx?.paymentMethod.toLowerCase().contains(query) ?? false) ||
                        (e.kind == _RiwayatKind.manual && 'manual'.contains(query))).toList();

                if (filtered.isEmpty) {
                  return _EmptyState(isSearching: query.isNotEmpty);
                }

                // Summary omzet
                final totalOmzet =
                    filtered.fold<double>(0, (s, t) => s + t.total);

                return Column(
                  children: [
                    // Banner omzet
                    _OmzetBanner(
                      total: totalOmzet,
                      count: filtered.length,
                      start: start,
                      end: end,
                    ),
                    // List
                    Expanded(
                      child: ListView.separated(
                        padding:
                            const EdgeInsets.fromLTRB(12, 8, 12, 80),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 8),
                        itemBuilder: (_, i) => _TrxCard(
                          entry: filtered[i],
                          onCetak: () =>
                              _showCetakSheet(context, filtered[i]),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showCetakSheet(BuildContext context, _RiwayatEntry entry) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ProviderScope(
        parent: ProviderScope.containerOf(context),
        child: entry.kind == _RiwayatKind.transaksi
            ? _CetakSheet(tx: entry.tx!)
            : _ManualNotaSheet(nota: entry.nota!),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Banner Omzet
// ─────────────────────────────────────────────────────────────────────────────

class _OmzetBanner extends StatelessWidget {
  final double total;
  final int count;
  final DateTime start;
  final DateTime end;

  const _OmzetBanner({
    required this.total,
    required this.count,
    required this.start,
    required this.end,
  });

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd/MM/yyyy');
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.trending_up_rounded,
                size: 16, color: Colors.white70),
            const SizedBox(width: 6),
            const Text('Total Omzet (hasil filter)',
                style: TextStyle(fontSize: 12, color: Colors.white70)),
          ]),
          const SizedBox(height: 6),
          Text(
            CurrencyFormatter.format(total),
            style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: Colors.white),
          ),
          const SizedBox(height: 4),
          Text(
            '$count transaksi · ${fmt.format(start)} s/d ${fmt.format(end)}',
            style: const TextStyle(fontSize: 12, color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Transaction Card
// ─────────────────────────────────────────────────────────────────────────────

/// Item generik untuk ditampilkan di detail kartu — dipetakan dari
/// TransactionItem (kasir otomatis) ATAU ManualNotaItem (nota manual) supaya
/// kode tampilan di bawah tidak perlu bercabang per jenis.
class _DisplayItem {
  final String name;
  final int qty;
  final double subtotal;
  const _DisplayItem({required this.name, required this.qty, required this.subtotal});
}

class _TrxCard extends ConsumerStatefulWidget {
  final _RiwayatEntry entry;
  final VoidCallback onCetak;

  const _TrxCard({required this.entry, required this.onCetak});

  @override
  ConsumerState<_TrxCard> createState() => _TrxCardState();
}

class _TrxCardState extends ConsumerState<_TrxCard> {
  bool _expanded = false;
  List<_DisplayItem>? _items;
  bool _loadingItems = false;

  Future<void> _loadItems() async {
    if (_items != null) return;
    setState(() => _loadingItems = true);
    if (widget.entry.kind == _RiwayatKind.transaksi) {
      final db = ref.read(databaseProvider);
      final items = await db.transactionsDao.getTransactionItems(widget.entry.tx!.id);
      if (mounted) {
        setState(() {
          _items = items
              .map((i) => _DisplayItem(name: i.productName, qty: i.quantity, subtotal: i.subtotal))
              .toList();
          _loadingItems = false;
        });
      }
    } else {
      final decoded = decodeManualNotaItems(widget.entry.nota!.itemsJson);
      if (mounted) {
        setState(() {
          _items = decoded
              .map((i) => _DisplayItem(name: i.name, qty: i.qty, subtotal: i.total))
              .toList();
          _loadingItems = false;
        });
      }
    }
  }

  String _methodLabel() {
    if (widget.entry.kind == _RiwayatKind.manual) return 'Manual';
    switch (widget.entry.tx!.paymentMethod) {
      case 'tunai':    return 'Tunai';
      case 'qris':     return 'QRIS';
      case 'transfer': return 'Transfer';
      case 'hutang':   return 'Hutang';
      default:         return widget.entry.tx!.paymentMethod;
    }
  }

  Color _methodColor() {
    if (widget.entry.kind == _RiwayatKind.manual) return _manualColor;
    switch (widget.entry.tx!.paymentMethod) {
      case 'tunai':    return AppColors.success;
      case 'qris':     return AppColors.primary;
      case 'transfer': return AppColors.info;
      case 'hutang':   return AppColors.warning;
      default:         return AppColors.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark   = Theme.of(context).brightness == Brightness.dark;
    final cardBg   = isDark ? AppColors.darkCard : Colors.white;
    final fmtDate  = DateFormat('dd MMM yyyy, HH.mm', 'id');

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: isDark ? AppColors.darkBorder : AppColors.border,
            width: 0.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          )
        ],
      ),
      child: Column(
        children: [
          // ── Header kartu ──────────────────────────────────────────────
          InkWell(
            onTap: () async {
              setState(() => _expanded = !_expanded);
              if (!_expanded) return;
              await _loadItems();
            },
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  // Icon invoice
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: (widget.entry.kind == _RiwayatKind.manual
                              ? _manualColor
                              : AppColors.primary)
                          .withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                        widget.entry.kind == _RiwayatKind.manual
                            ? Icons.edit_note_outlined
                            : Icons.receipt_long_outlined,
                        size: 20,
                        color: widget.entry.kind == _RiwayatKind.manual
                            ? _manualColor
                            : AppColors.primary),
                  ),
                  const SizedBox(width: 12),
                  // Invoice + tanggal
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.entry.invoiceNumber,
                            style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(
                          fmtDate.format(widget.entry.createdAt.toLocal()),
                          style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  // Badge metode + total
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _methodColor().withOpacity(0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _methodLabel(),
                          style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: _methodColor()),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        CurrencyFormatter.format(widget.entry.total),
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary),
                      ),
                    ],
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 20,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ),
          ),

          // ── Detail items (expanded) ────────────────────────────────────
          if (_expanded) ...[
            Divider(
                height: 1,
                color: isDark ? AppColors.darkBorder : AppColors.border),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
              child: Row(children: [
                const Icon(Icons.inventory_2_outlined,
                    size: 13, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                const Text('DETAIL ITEM',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textSecondary,
                        letterSpacing: 0.5)),
              ]),
            ),
            _loadingItems
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(
                        child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2))))
                : _items == null || _items!.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: Text('Tidak ada item',
                            style: TextStyle(
                                color: AppColors.textSecondary,
                                fontSize: 12)))
                    : ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
                        itemCount: _items!.length,
                        itemBuilder: (_, i) {
                          final item = _items![i];
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(children: [
                              Expanded(
                                child: Text(item.name,
                                    style: const TextStyle(fontSize: 13)),
                              ),
                              Text('${item.qty}x',
                                  style: const TextStyle(
                                      fontSize: 12,
                                      color: AppColors.textSecondary)),
                              const SizedBox(width: 8),
                              Text(
                                CurrencyFormatter.format(item.subtotal),
                                style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600),
                              ),
                            ]),
                          );
                        },
                      ),

            // ── Summary total ────────────────────────────────────────────
            if (_items != null) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
                child: Row(children: [
                  const Expanded(
                      child: Text('Total',
                          style: TextStyle(fontWeight: FontWeight.w700))),
                  Text(
                    CurrencyFormatter.format(widget.entry.total),
                    style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary),
                  ),
                ]),
              ),
            ],

            // ── Tombol Cetak Ulang Struk ──────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: Icon(
                      widget.entry.kind == _RiwayatKind.manual
                          ? Icons.more_horiz_rounded
                          : Icons.print_outlined,
                      size: 18),
                  label: Text(widget.entry.kind == _RiwayatKind.manual
                      ? 'Detail / Kelola Nota'
                      : 'Cetak Ulang Struk'),
                  onPressed: widget.onCetak,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sheet Cetak Ulang Struk
// ─────────────────────────────────────────────────────────────────────────────

class _CetakSheet extends ConsumerStatefulWidget {
  final Transaction tx;
  const _CetakSheet({required this.tx});

  @override
  ConsumerState<_CetakSheet> createState() => _CetakSheetState();
}

class _CetakSheetState extends ConsumerState<_CetakSheet> {
  bool _printing  = false;
  bool _pdfing    = false;
  List<TransactionItem> _items = [];
  bool _loaded = false;
  String? _customerName;

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    final db = ref.read(databaseProvider);
    final items = await db.transactionsDao.getTransactionItems(widget.tx.id);

    // PERUBAHAN #4: ambil nama pelanggan (jika transaksi ini terkait
    // pelanggan tertentu) untuk ditampilkan di struk — murni untuk
    // tampilan, tidak memengaruhi data transaksi yang sudah tersimpan.
    String? customerName;
    final customerId = widget.tx.customerId;
    if (customerId != null) {
      final customer = await db.customersDao.getCustomerById(customerId);
      customerName = customer?.name;
    }

    if (mounted) {
      setState(() {
        _items = items;
        _loaded = true;
        _customerName = customerName;
      });
    }
  }

  String _methodLabel(String m) {
    switch (m) {
      case 'tunai':    return 'Tunai';
      case 'qris':     return 'QRIS';
      case 'transfer': return 'Transfer Bank';
      case 'hutang':   return 'Hutang';
      default:         return m;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark   = Theme.of(context).brightness == Brightness.dark;
    final sheetBg  = isDark ? AppColors.darkSurface : Colors.white;
    final fmtDate  = DateFormat('dd MMM yyyy, HH:mm', 'id');
    final bottomPad = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: BoxDecoration(
        color: sheetBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(bottom: bottomPad + 16),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Center(
              child: Container(
                width: 36, height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Judul
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Cetak Ulang Struk',
                    style: TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w800)),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Info transaksi
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: AppColors.primary.withOpacity(0.2), width: 0.5),
              ),
              child: Column(
                children: [
                  _InfoRow2(label: 'No. Invoice',
                      value: widget.tx.invoiceNumber),
                  const SizedBox(height: 6),
                  _InfoRow2(
                      label: 'Tanggal',
                      value: fmtDate.format(widget.tx.createdAt.toLocal())),
                  const SizedBox(height: 6),
                  _InfoRow2(
                      label: 'Metode',
                      value: _methodLabel(widget.tx.paymentMethod)),
                  const SizedBox(height: 6),
                  _InfoRow2(
                      label: 'Total',
                      value: CurrencyFormatter.format(widget.tx.total),
                      bold: true),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Item list
            if (!_loaded)
              const Center(child: CircularProgressIndicator())
            else ...[
              ...(_items.map((item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  Expanded(
                    child: Text(item.productName,
                        style: const TextStyle(fontSize: 13)),
                  ),
                  Text('${item.quantity}x ',
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textSecondary)),
                  Text(CurrencyFormatter.format(item.subtotal),
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600)),
                ]),
              ))),
              const Divider(height: 20),
            ],
            const SizedBox(height: 8),

            // Tombol cetak Bluetooth
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: _printing
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.print_outlined, size: 18),
                label:
                    Text(_printing ? 'Mencetak...' : 'Cetak Struk (Bluetooth)'),
                onPressed: _printing ? null : _cetakBluetooth,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Tombol share PDF
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: _pdfing
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.picture_as_pdf_outlined, size: 18),
                label: Text(_pdfing ? 'Membuat PDF...' : 'Simpan / Share PDF'),
                onPressed: _pdfing ? null : _sharePdf,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.info,
                  side: const BorderSide(color: AppColors.info),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Load logo ─────────────────────────────────────────────────────────────

  Future<img.Image?> _loadLogoImage(int maxWidth) async {
    try {
      final store = ref.read(storeSettingsProvider);
      img.Image? original;
      if (store.logoPath.isNotEmpty && File(store.logoPath).existsSync()) {
        final bytes = await File(store.logoPath).readAsBytes();
        original = img.decodeImage(bytes);
      } else {
        // Fallback ke logo header dari assets/logo/header.png
        final data = await rootBundle.load('assets/logo/header.png');
        final bytes = data.buffer.asUint8List();
        original = img.decodeImage(bytes);
      }
      if (original == null) return null;
      original = img.trim(original, mode: img.TrimMode.transparent);
      if (original.width > maxWidth) {
        original = img.copyResize(original, width: maxWidth);
      }
      return img.grayscale(original);
    } catch (_) {
      return null;
    }
  }

  // Footer logo PERMANEN KasirKu Pro — selalu dari assets/logo/footer.png,
  // tidak mengikuti logo custom toko, tidak memakai app_icon.png.
  Future<img.Image?> _loadFooterAppIcon({int maxWidth = 220}) async {
    try {
      final data = await rootBundle.load('assets/logo/footer.png');
      final bytes = data.buffer.asUint8List();
      var original = img.decodeImage(bytes);
      if (original == null) return null;
      original = img.trim(original, mode: img.TrimMode.transparent);
      if (original.width > maxWidth) {
        original = img.copyResize(original, width: maxWidth);
      }
      return img.grayscale(original);
    } catch (_) {
      return null;
    }
  }

  // ── Cetak Bluetooth ───────────────────────────────────────────────────────

  Future<void> _cetakBluetooth() async {
    setState(() => _printing = true);
    try {
      final connected = await PrintBluetoothThermal.connectionStatus;
      if (!connected) {
        if (context.mounted) await _showPrinterDialog();
        return;
      }
      await _doPrint();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal cetak: $e'),
              backgroundColor: AppColors.danger));
      }
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  Future<void> _showPrinterDialog() async {
    final granted = await ensureBluetoothPermission();
    if (!context.mounted) return;
    if (!granted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Izin Bluetooth ditolak. Aktifkan lewat Pengaturan '
              'HP > Aplikasi > KasirKu Pro > Izin.'),
          backgroundColor: AppColors.danger));
      return;
    }
    final devices = await PrintBluetoothThermal.pairedBluetooths;
    if (!context.mounted) return;
    if (devices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Tidak ada printer Bluetooth yang dipasangkan'),
          backgroundColor: AppColors.warning));
      return;
    }
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Pilih Printer',
            style: TextStyle(fontWeight: FontWeight.w700)),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: devices.length,
            itemBuilder: (_, i) {
              final d = devices[i];
              return ListTile(
                leading: const Icon(Icons.print_outlined,
                    color: AppColors.primary),
                title: Text(d.name ?? 'Printer ${i + 1}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(d.macAdress ?? '',
                    style: const TextStyle(fontSize: 12)),
                onTap: () async {
                  Navigator.pop(context);
                  final ok = await PrintBluetoothThermal.connect(
                      macPrinterAddress: d.macAdress ?? '');
                  if (ok) {
                    await _doPrint();
                  } else {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                            content: Text('Gagal terhubung ke printer'),
                            backgroundColor: AppColors.danger));
                    }
                  }
                },
              );
            },
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal')),
        ],
      ),
    );
  }

  Future<void> _doPrint() async {
    final settings    = ref.read(storeSettingsProvider);
    final storeName   = settings.storeName.isEmpty ? 'KasirKu' : settings.storeName;
    final storeAddress = settings.storeAddress;
    final storePhone  = settings.storePhone;
    final storeNote   = settings.storeNote;
    final paperSize   = settings.receiptSize == '80mm'
        ? PaperSize.mm80 : PaperSize.mm58;
    final logoMaxWidth = settings.receiptSize == '80mm' ? 300 : 200;

    final profile   = await CapabilityProfile.load();
    final generator = Generator(paperSize, profile);
    var bytes = <int>[];

    final dateStr = DateFormat('dd/MM/yyyy HH:mm')
        .format(widget.tx.createdAt.toLocal());

    if (settings.showLogo) {
      final logoImg = await _loadLogoImage(logoMaxWidth);
      if (logoImg != null) {
        bytes += generator.image(logoImg);
        bytes += generator.feed(1);
      }
    }

    bytes += generator.text(storeName,
        styles: const PosStyles(
            align: PosAlign.center, bold: true,
            height: PosTextSize.size2, width: PosTextSize.size2));
    if (storeAddress.isNotEmpty) {
      bytes += generator.text(storeAddress,
          styles: const PosStyles(align: PosAlign.center));
    }
    if (storePhone.isNotEmpty) {
      bytes += generator.text('Telp: $storePhone',
          styles: const PosStyles(align: PosAlign.center));
    }
    bytes += generator.hr();
    bytes += generator.text('No: ${widget.tx.invoiceNumber}',
        styles: const PosStyles(align: PosAlign.center));
    bytes += generator.text(dateStr,
        styles: const PosStyles(align: PosAlign.center));
    bytes += generator.hr();

    for (final item in _items) {
      bytes += generator.text(item.productName,
          styles: const PosStyles(bold: true));
      bytes += generator.row([
        PosColumn(
            text: '  ${item.quantity} x ${CurrencyFormatter.format(item.price)}',
            width: 8,
            styles: const PosStyles(align: PosAlign.left)),
        PosColumn(
            text: CurrencyFormatter.format(item.subtotal),
            width: 4,
            styles: const PosStyles(align: PosAlign.right)),
      ]);
    }
    bytes += generator.hr();

    bytes += generator.row([
      PosColumn(text: 'TOTAL', width: 6,
          styles: const PosStyles(bold: true, align: PosAlign.left)),
      PosColumn(
          text: CurrencyFormatter.format(widget.tx.total),
          width: 6,
          styles: const PosStyles(bold: true, align: PosAlign.right)),
    ]);
    bytes += generator.hr();

    if (storeNote.isNotEmpty) {
      bytes += generator.text(storeNote,
          styles: const PosStyles(align: PosAlign.center, bold: true));
    }
    bytes += generator.feed(3);
    bytes += generator.cut();

    await PrintBluetoothThermal.writeBytes(bytes);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Struk berhasil dicetak!'),
          backgroundColor: AppColors.success));
    }
  }

  // ── Share PDF ─────────────────────────────────────────────────────────────

  // ── PERUBAHAN: _sharePdf sekarang hanya menyiapkan data & memanggil
  // ReceiptPdfBuilder (lib/core/utils/receipt_pdf_builder.dart) untuk urusan
  // layout/tampilan. Semua angka (subtotal/diskon/pajak/total/dibayar/
  // kembali) tetap dibaca apa adanya dari widget.tx yang sudah tersimpan di
  // database — TIDAK ada perhitungan ulang/baru di sini maupun di builder.
  Future<void> _sharePdf() async {
    setState(() => _pdfing = true);
    try {
      await initializeDateFormatting('id', null);
      final settings    = ref.read(storeSettingsProvider);
      final storeName   = settings.storeName.isEmpty ? 'KasirKu' : settings.storeName;
      final storeAddress = settings.storeAddress ?? '';
      final storePhone  = settings.storePhone ?? '';
      final storeNote   = settings.storeNote ?? '';
      final logoMaxWidth = settings.receiptSize == '80mm' ? 300 : 200;

      // Logo header: custom (mengikuti Pengaturan > Struk), opsional.
      pw.MemoryImage? logoImage;
      if (settings.showLogo) {
        final logoImg = await _loadLogoImage(logoMaxWidth);
        if (logoImg != null) {
          logoImage = pw.MemoryImage(img.encodePng(logoImg));
        }
      }

      // Logo footer: PERMANEN, selalu assets/images/app_icon.png.
      pw.MemoryImage? footerLogoImage;
      final footerIcon = await _loadFooterAppIcon();
      if (footerIcon != null) {
        footerLogoImage = pw.MemoryImage(img.encodePng(footerIcon));
      }

      final items = _items
          .map((item) => ReceiptPdfItem(
                name: item.productName,
                quantity: item.quantity,
                price: item.price,
                subtotal: item.subtotal,
              ))
          .toList();

      // Persentase pajak hanya untuk label tampilan (mis. "Pajak (5%)"),
      // dihitung dari subtotal & taxAmount yang SUDAH tersimpan — bukan
      // perhitungan transaksi baru.
      final taxPercent = widget.tx.subtotal > 0
          ? (widget.tx.taxAmount / widget.tx.subtotal * 100)
          : 0.0;

      final pdfBytes = await ReceiptPdfBuilder.build(
        storeName: storeName,
        storeAddress: storeAddress,
        storePhone: storePhone,
        storeNote: storeNote,
        invoiceNumber: widget.tx.invoiceNumber,
        date: widget.tx.createdAt.toLocal(),
        paymentMethodLabel: _methodLabel(widget.tx.paymentMethod),
        kasirName: widget.tx.kasirName,
        customerName: _customerName,
        items: items,
        discount: widget.tx.discountAmount,
        tax: widget.tx.taxAmount,
        taxPercent: taxPercent,
        total: widget.tx.total,
        amountPaid: widget.tx.amountPaid,
        change: widget.tx.change,
        receiptSize: settings.receiptSize,
        logoImage: logoImage,
        footerLogoImage: footerLogoImage,
      );

      final dir  = await getTemporaryDirectory();
      final file = File('${dir.path}/${widget.tx.invoiceNumber}.pdf');
      await file.writeAsBytes(pdfBytes);
      await Share.shareXFiles(
          [XFile(file.path)], text: 'Struk ${widget.tx.invoiceNumber}');
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal buat PDF: $e'),
              backgroundColor: AppColors.danger));
      }
    } finally {
      if (mounted) setState(() => _pdfing = false);
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sheet Detail Nota Manual (Edit / Hapus / Cetak Ulang / Bagikan)
// ─────────────────────────────────────────────────────────────────────────────

class _ManualNotaSheet extends ConsumerStatefulWidget {
  final ManualNota nota;
  const _ManualNotaSheet({required this.nota});

  @override
  ConsumerState<_ManualNotaSheet> createState() => _ManualNotaSheetState();
}

class _ManualNotaSheetState extends ConsumerState<_ManualNotaSheet> {
  bool _printing = false;
  bool _pdfing   = false;
  bool _deleting = false;
  late final List<ManualNotaItem> _items;

  @override
  void initState() {
    super.initState();
    _items = decodeManualNotaItems(widget.nota.itemsJson);
  }

  double? get _kembalian {
    final paid = widget.nota.amountPaid;
    if (paid == null) return null;
    return paid - widget.nota.total;
  }

  // ── Edit ─────────────────────────────────────────────────────────────────
  Future<void> _edit() async {
    final navigator = Navigator.of(context);
    final container = ProviderScope.containerOf(context);
    navigator.pop(); // tutup sheet dulu
    final changed = await navigator.push<bool>(
      MaterialPageRoute(
        builder: (_) => ProviderScope(
          parent: container,
          child: ManualNotaScreen(editingNota: widget.nota),
        ),
      ),
    );
    if (changed == true) {
      container.invalidate(_riwayatListProvider);
    }
  }

  // ── Hapus ────────────────────────────────────────────────────────────────
  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Hapus Nota?'),
        content: Text('Nota ${widget.nota.invoiceNumber} akan dihapus permanen.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Batal')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _deleting = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await ref.read(databaseProvider).manualNotasDao.deleteNota(widget.nota.id);
      ref.invalidate(_riwayatListProvider);
      navigator.pop();
      messenger.showSnackBar(const SnackBar(
          content: Text('Nota dihapus'), backgroundColor: AppColors.success));
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(
            content: Text('Gagal menghapus: $e'), backgroundColor: AppColors.danger));
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  // ── Cetak Ulang (Bluetooth) ──────────────────────────────────────────────
  Future<void> _cetakUlang() async {
    setState(() => _printing = true);
    try {
      final settings = ref.read(storeSettingsProvider);
      await ManualNotaPrinter.print(nota: widget.nota, items: _items, settings: settings);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Struk berhasil dicetak!'), backgroundColor: AppColors.success));
      }
    } catch (_) {
      if (context.mounted) await _showPrinterDialog();
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  Future<void> _showPrinterDialog() async {
    final granted = await ensureBluetoothPermission();
    if (!context.mounted) return;
    if (!granted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Izin Bluetooth ditolak. Aktifkan lewat Pengaturan '
              'HP > Aplikasi > KasirKu Pro > Izin.'),
          backgroundColor: AppColors.danger));
      return;
    }
    final devices = await PrintBluetoothThermal.pairedBluetooths;
    if (!context.mounted) return;
    if (devices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Tidak ada printer Bluetooth yang dipasangkan'),
          backgroundColor: AppColors.warning));
      return;
    }
    await showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Pilih Printer', style: TextStyle(fontWeight: FontWeight.w700)),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: devices.length,
            itemBuilder: (_, i) {
              final d = devices[i];
              return ListTile(
                leading: const Icon(Icons.print_outlined, color: AppColors.primary),
                title: Text(d.name ?? 'Printer ${i + 1}',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(d.macAdress ?? '', style: const TextStyle(fontSize: 12)),
                onTap: () async {
                  Navigator.pop(context);
                  final ok = await PrintBluetoothThermal.connect(macPrinterAddress: d.macAdress ?? '');
                  if (ok && mounted) {
                    final settings = ref.read(storeSettingsProvider);
                    try {
                      await ManualNotaPrinter.print(nota: widget.nota, items: _items, settings: settings);
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                            content: Text('Struk berhasil dicetak!'), backgroundColor: AppColors.success));
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text('Gagal cetak: $e'), backgroundColor: AppColors.danger));
                      }
                    }
                  } else if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text('Gagal terhubung ke printer'), backgroundColor: AppColors.danger));
                  }
                },
              );
            },
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Batal'))],
      ),
    );
  }

  // ── Load logo (sama seperti _CetakSheet, untuk konsistensi tampilan PDF) ──
  Future<img.Image?> _loadLogoImage(int maxWidth) async {
    try {
      final store = ref.read(storeSettingsProvider);
      img.Image? original;
      if (store.logoPath.isNotEmpty && File(store.logoPath).existsSync()) {
        final bytes = await File(store.logoPath).readAsBytes();
        original = img.decodeImage(bytes);
      } else {
        final data = await rootBundle.load('assets/logo/header.png');
        original = img.decodeImage(data.buffer.asUint8List());
      }
      if (original == null) return null;
      original = img.trim(original, mode: img.TrimMode.transparent);
      if (original.width > maxWidth) original = img.copyResize(original, width: maxWidth);
      return img.grayscale(original);
    } catch (_) {
      return null;
    }
  }

  Future<img.Image?> _loadFooterAppIcon({int maxWidth = 220}) async {
    try {
      final data = await rootBundle.load('assets/logo/footer.png');
      var original = img.decodeImage(data.buffer.asUint8List());
      if (original == null) return null;
      original = img.trim(original, mode: img.TrimMode.transparent);
      if (original.width > maxWidth) original = img.copyResize(original, width: maxWidth);
      return img.grayscale(original);
    } catch (_) {
      return null;
    }
  }

  // ── Bagikan PDF ──────────────────────────────────────────────────────────
  Future<void> _sharePdf() async {
    setState(() => _pdfing = true);
    try {
      await initializeDateFormatting('id', null);
      final settings = ref.read(storeSettingsProvider);
      final storeName = settings.storeName.isEmpty ? 'KasirKu' : settings.storeName;
      final logoMaxWidth = settings.receiptSize == '80mm' ? 300 : 200;

      pw.MemoryImage? logoImage;
      if (settings.showLogo) {
        final logoImg = await _loadLogoImage(logoMaxWidth);
        if (logoImg != null) logoImage = pw.MemoryImage(img.encodePng(logoImg));
      }
      pw.MemoryImage? footerLogoImage;
      final footerIcon = await _loadFooterAppIcon();
      if (footerIcon != null) footerLogoImage = pw.MemoryImage(img.encodePng(footerIcon));

      final items = _items
          .map((item) => ReceiptPdfItem(
                name: item.name,
                quantity: item.qty,
                price: item.price,
                subtotal: item.total,
              ))
          .toList();

      final pdfBytes = await ReceiptPdfBuilder.build(
        storeName: storeName,
        storeAddress: settings.storeAddress,
        storePhone: settings.storePhone,
        storeNote: settings.storeNote,
        invoiceNumber: widget.nota.invoiceNumber,
        date: widget.nota.createdAt.toLocal(),
        paymentMethodLabel: 'Manual',
        customerName: widget.nota.customerName,
        items: items,
        total: widget.nota.total,
        amountPaid: widget.nota.amountPaid,
        change: _kembalian != null && _kembalian! > 0 ? _kembalian : null,
        receiptSize: settings.receiptSize,
        logoImage: logoImage,
        footerLogoImage: footerLogoImage,
      );

      final dir  = await getTemporaryDirectory();
      final file = File('${dir.path}/${widget.nota.invoiceNumber}.pdf');
      await file.writeAsBytes(pdfBytes);
      await Share.shareXFiles([XFile(file.path)], text: 'Nota ${widget.nota.invoiceNumber}');
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal buat PDF: $e'), backgroundColor: AppColors.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _pdfing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark    = Theme.of(context).brightness == Brightness.dark;
    final sheetBg   = isDark ? AppColors.darkSurface : Colors.white;
    final fmtDate   = DateFormat('dd MMM yyyy, HH:mm', 'id');
    final bottomPad = MediaQuery.of(context).viewInsets.bottom;
    final kembalian = _kembalian;

    return Container(
      decoration: BoxDecoration(
        color: sheetBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(bottom: bottomPad + 16),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 36, height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                    color: AppColors.border, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Nota Manual', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _manualColor.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _manualColor.withOpacity(0.25), width: 0.5),
              ),
              child: Column(
                children: [
                  _InfoRow2(label: 'No. Invoice', value: widget.nota.invoiceNumber),
                  const SizedBox(height: 6),
                  _InfoRow2(label: 'Tanggal', value: fmtDate.format(widget.nota.createdAt.toLocal())),
                  if ((widget.nota.customerName ?? '').isNotEmpty) ...[
                    const SizedBox(height: 6),
                    _InfoRow2(label: 'Pelanggan', value: widget.nota.customerName!),
                  ],
                  const SizedBox(height: 6),
                  _InfoRow2(label: 'Total', value: CurrencyFormatter.format(widget.nota.total), bold: true),
                  if (widget.nota.amountPaid != null) ...[
                    const SizedBox(height: 6),
                    _InfoRow2(label: 'Dibayar', value: CurrencyFormatter.format(widget.nota.amountPaid!)),
                  ],
                  if (kembalian != null && kembalian > 0) ...[
                    const SizedBox(height: 6),
                    _InfoRow2(label: 'Kembali', value: CurrencyFormatter.format(kembalian), bold: true),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            ..._items.map((item) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    Expanded(child: Text(item.name, style: const TextStyle(fontSize: 13))),
                    Text('${item.qty}x ',
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                    Text(CurrencyFormatter.format(item.total),
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  ]),
                )),
            const Divider(height: 20),

            // Edit + Hapus
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Edit'),
                  onPressed: _edit,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  icon: _deleting
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.delete_outline, size: 18),
                  label: Text(_deleting ? 'Menghapus...' : 'Hapus'),
                  onPressed: _deleting ? null : _delete,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    side: const BorderSide(color: AppColors.danger),
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 10),

            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: _printing
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.print_outlined, size: 18),
                label: Text(_printing ? 'Mencetak...' : 'Cetak Ulang (Bluetooth)'),
                onPressed: _printing ? null : _cetakUlang,
                style: OutlinedButton.styleFrom(
                  foregroundColor: _manualColor,
                  side: const BorderSide(color: _manualColor),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            const SizedBox(height: 10),

            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: _pdfing
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.picture_as_pdf_outlined, size: 18),
                label: Text(_pdfing ? 'Membuat PDF...' : 'Bagikan (PDF / WhatsApp)'),
                onPressed: _pdfing ? null : _sharePdf,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.info,
                  side: const BorderSide(color: AppColors.info),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

class _InfoRow2 extends StatelessWidget {
  final String label;
  final String value;
  final bool bold;
  const _InfoRow2({required this.label, required this.value, this.bold = false});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 12, color: AppColors.textSecondary)),
        Text(value,
            style: TextStyle(
                fontSize: 12,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                color: bold ? AppColors.primary : null)),
      ],
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool isSearching;
  const _EmptyState({required this.isSearching});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            isSearching
                ? Icons.search_off_rounded
                : Icons.receipt_long_outlined,
            size: 60,
            color: AppColors.textHint,
          ),
          const SizedBox(height: 12),
          Text(
            isSearching
                ? 'Transaksi tidak ditemukan'
                : 'Belum ada transaksi',
            style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.textSecondary),
          ),
          const SizedBox(height: 6),
          Text(
            isSearching
                ? 'Coba kata kunci yang berbeda'
                : 'Transaksi akan muncul di sini',
            style: const TextStyle(
                fontSize: 12, color: AppColors.textHint),
          ),
        ],
      ),
    );
  }
}
