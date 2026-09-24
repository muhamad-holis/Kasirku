// lib/presentation/screens/kas/kas_screen.dart
// ─────────────────────────────────────────────────────────────────────────────
// Layar Kas Masuk & Kas Keluar — Fitur Prioritas Kasirku
// Tab: Semua | Kas Masuk | Kas Keluar
// Fitur: Tambah, Hapus, Filter periode, Summary bar, Breakdown kategori
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency.dart';
import '../../../data/database/app_database.dart';
import '../../providers/database_provider.dart';
import '../../providers/kas_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MAIN SCREEN
// ─────────────────────────────────────────────────────────────────────────────

class KasScreen extends ConsumerStatefulWidget {
  const KasScreen({super.key});

  @override
  ConsumerState<KasScreen> createState() => _KasScreenState();
}

class _KasScreenState extends ConsumerState<KasScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  String _period = '7d';

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

  DateRange get _range => DateRange(start: _start, end: DateTime.now());

  @override
  Widget build(BuildContext context) {
    final summaryAsync = ref.watch(kasSummaryProvider(_range));

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('Kas & Keuangan',
            style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: 'Catat Kas',
            onSelected: (type) => _showForm(type),
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'income',
                child: Row(children: [
                  Icon(Icons.arrow_circle_down_rounded,
                      color: AppColors.success, size: 18),
                  const SizedBox(width: 8),
                  const Text('Kas Masuk'),
                ]),
              ),
              PopupMenuItem(
                value: 'expense',
                child: Row(children: [
                  Icon(Icons.arrow_circle_up_rounded,
                      color: AppColors.danger, size: 18),
                  const SizedBox(width: 8),
                  const Text('Kas Keluar'),
                ]),
              ),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tab,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          tabs: const [
            Tab(text: 'Semua'),
            Tab(text: 'Masuk'),
            Tab(text: 'Keluar'),
          ],
        ),
      ),
      body: Column(
        children: [
          // ── Period filter ──────────────────────────────────────────────────
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Row(
              children: [
                _PeriodChip('Hari Ini', 'today', _period,
                    (v) => setState(() => _period = v)),
                _PeriodChip('7 Hari', '7d', _period,
                    (v) => setState(() => _period = v)),
                _PeriodChip('30 Hari', '30d', _period,
                    (v) => setState(() => _period = v)),
                _PeriodChip('Bulan Ini', 'month', _period,
                    (v) => setState(() => _period = v)),
              ],
            ),
          ),

          // ── Summary bar ────────────────────────────────────────────────────
          summaryAsync.when(
            data: (s) => _SummaryBar(summary: s),
            loading: () => const SizedBox(height: 76),
            error: (_, __) => const SizedBox(),
          ),

          // ── Tab views ──────────────────────────────────────────────────────
          Expanded(
            child: TabBarView(
              controller: _tab,
              children: [
                _KasListTab(range: _range, type: null),
                _KasListTab(range: _range, type: 'income'),
                _KasListTab(range: _range, type: 'expense'),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.small(
            heroTag: 'fab_kas_keluar',
            backgroundColor: AppColors.danger,
            foregroundColor: Colors.white,
            onPressed: () => _showForm('expense'),
            tooltip: 'Kas Keluar',
            child: const Icon(Icons.arrow_circle_up_rounded),
          ),
          const SizedBox(height: 8),
          FloatingActionButton.extended(
            heroTag: 'fab_kas_masuk',
            backgroundColor: AppColors.success,
            foregroundColor: Colors.white,
            onPressed: () => _showForm('income'),
            icon: const Icon(Icons.arrow_circle_down_rounded),
            label: const Text('Kas Masuk',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }

  void _showForm(String type) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ProviderScope(
        parent: ProviderScope.containerOf(context),
        child: _KasFormSheet(initialType: type),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SUMMARY BAR
// ─────────────────────────────────────────────────────────────────────────────

class _SummaryBar extends StatelessWidget {
  final KasSummary summary;
  const _SummaryBar({required this.summary});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      child: Row(
        children: [
          _MiniCard(
            label: 'Kas Masuk',
            value: CurrencyFormatter.formatCompact(summary.totalIncome),
            color: AppColors.success,
            icon: Icons.arrow_circle_down_rounded,
          ),
          const SizedBox(width: 8),
          _MiniCard(
            label: 'Kas Keluar',
            value: CurrencyFormatter.formatCompact(summary.totalExpense),
            color: AppColors.danger,
            icon: Icons.arrow_circle_up_rounded,
          ),
          const SizedBox(width: 8),
          _MiniCard(
            label: 'Saldo',
            value: CurrencyFormatter.formatCompact(summary.saldo),
            color:
                summary.saldo >= 0 ? AppColors.primary : AppColors.danger,
            icon: Icons.account_balance_wallet_outlined,
          ),
        ],
      ),
    );
  }
}

class _MiniCard extends StatelessWidget {
  final String label, value;
  final Color color;
  final IconData icon;
  const _MiniCard(
      {required this.label,
      required this.value,
      required this.color,
      required this.icon});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(height: 4),
            Text(value,
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                    color: color)),
            Text(label,
                style: const TextStyle(
                    fontSize: 9, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// KAS LIST TAB
// ─────────────────────────────────────────────────────────────────────────────

class _KasListTab extends ConsumerWidget {
  final DateRange range;
  final String? type; // null = semua

  const _KasListTab({required this.range, required this.type});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stream = type != null
        ? ref
            .read(databaseProvider)
            .reportsDao
            .watchCashFlowsByType(range.start, range.end, type!)
        : ref
            .read(databaseProvider)
            .reportsDao
            .watchCashFlows(range.start, range.end);

    return StreamBuilder<List<CashFlow>>(
      stream: stream,
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final flows = snap.data!;

        if (flows.isEmpty) {
          return _EmptyState(type: type);
        }

        // Group by tanggal
        final grouped = <String, List<CashFlow>>{};
        for (final f in flows) {
          final key = DateFormat('yyyy-MM-dd').format(f.createdAt);
          grouped.putIfAbsent(key, () => []).add(f);
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 100),
          itemCount: grouped.length,
          itemBuilder: (context, i) {
            final date = grouped.keys.elementAt(i);
            final items = grouped[date]!;
            final dayTotal = items.fold<double>(0, (s, f) {
              return s + (f.type == 'income' ? f.amount : -f.amount);
            });

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Date header ──
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Row(
                    children: [
                      Text(
                        _formatDateGroup(date),
                        style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                            color: AppColors.textSecondary),
                      ),
                      const Spacer(),
                      Text(
                        (dayTotal >= 0 ? '+' : '') +
                            CurrencyFormatter.format(dayTotal),
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                            color: dayTotal >= 0
                                ? AppColors.success
                                : AppColors.danger),
                      ),
                    ],
                  ),
                ),
                // ── Items ──
                ...items.map(
                    (f) => _KasRow(flow: f, onDelete: () => _delete(context, ref, f))),
                const SizedBox(height: 4),
              ],
            );
          },
        );
      },
    );
  }

  String _formatDateGroup(String dateStr) {
    final dt = DateTime.parse(dateStr);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final d = DateTime(dt.year, dt.month, dt.day);
    if (d == today) return 'Hari Ini';
    if (d == yesterday) return 'Kemarin';
    return DateFormat('EEEE, dd MMM yyyy', 'id').format(dt);
  }

  Future<void> _delete(
      BuildContext context, WidgetRef ref, CashFlow flow) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hapus Entri Kas?'),
        content: Text(
            '${labelKategoriKas(flow.category)}\n${CurrencyFormatter.format(flow.amount)}\n\nData ini tidak dapat dikembalikan.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Batal')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(
                  foregroundColor: AppColors.danger),
              child: const Text('Hapus')),
        ],
      ),
    );
    if (confirm == true && context.mounted) {
      try {
        await ref.read(databaseProvider).reportsDao.deleteCashFlow(flow.id);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Entri kas dihapus'),
            behavior: SnackBarBehavior.floating,
          ));
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Gagal hapus: $e')));
        }
      }
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// KAS ROW
// ─────────────────────────────────────────────────────────────────────────────

class _KasRow extends StatelessWidget {
  final CashFlow flow;
  final VoidCallback onDelete;
  const _KasRow({required this.flow, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final isIncome = flow.type == 'income';
    final color = isIncome ? AppColors.success : AppColors.danger;

    return Dismissible(
      key: Key('kas_${flow.id}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        onDelete();
        return false; // Hapus dari dalam dialog, bukan auto-dismiss
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: AppColors.danger.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(Icons.delete_outline, color: AppColors.danger),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border, width: 0.5),
        ),
        child: Row(
          children: [
            // Icon
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                isIncome
                    ? Icons.arrow_circle_down_rounded
                    : Icons.arrow_circle_up_rounded,
                size: 20,
                color: color,
              ),
            ),
            const SizedBox(width: 10),
            // Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    labelKategoriKas(flow.category),
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 13),
                  ),
                  if (flow.description != null &&
                      flow.description!.isNotEmpty)
                    Text(
                      flow.description!,
                      style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.textSecondary),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  Text(
                    DateFormat('HH:mm', 'id').format(flow.createdAt),
                    style: const TextStyle(
                        fontSize: 10, color: AppColors.textHint),
                  ),
                ],
              ),
            ),
            // Nominal
            Text(
              '${isIncome ? '+' : '-'} ${CurrencyFormatter.format(flow.amount)}',
              style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                  color: color),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// EMPTY STATE
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final String? type;
  const _EmptyState({this.type});

  @override
  Widget build(BuildContext context) {
    final label = type == 'income'
        ? 'Belum ada kas masuk'
        : type == 'expense'
            ? 'Belum ada kas keluar'
            : 'Belum ada catatan kas';
    final icon = type == 'income'
        ? Icons.arrow_circle_down_outlined
        : type == 'expense'
            ? Icons.arrow_circle_up_outlined
            : Icons.account_balance_wallet_outlined;
    final color = type == 'income'
        ? AppColors.success
        : type == 'expense'
            ? AppColors.danger
            : AppColors.primary;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 54, color: color.withOpacity(0.25)),
          const SizedBox(height: 12),
          Text(label,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 14)),
          const SizedBox(height: 4),
          const Text('Tekan tombol + untuk menambah',
              style: TextStyle(
                  color: AppColors.textHint, fontSize: 12)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FORM SHEET — Tambah Kas Masuk / Kas Keluar
// ─────────────────────────────────────────────────────────────────────────────

class _KasFormSheet extends ConsumerStatefulWidget {
  final String initialType;
  const _KasFormSheet({required this.initialType});

  @override
  ConsumerState<_KasFormSheet> createState() => _KasFormSheetState();
}

class _KasFormSheetState extends ConsumerState<_KasFormSheet> {
  late String _type;
  final _amountCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  String _category = '';
  bool _loading = false;

  static const _incomeCategories = [
    'Penjualan',
    'Pelunasan Hutang',
    'Tambah Modal',
    'Pinjaman',
    'Lainnya',
  ];

  static const _expenseCategories = [
    'Pembelian Stok',
    'Biaya Operasional',
    'Gaji Karyawan',
    'Biaya Sewa',
    'Listrik & Air',
    'Lainnya',
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
    final raw =
        _amountCtrl.text.replaceAll(RegExp(r'[^\d]'), '');
    final amount = double.tryParse(raw) ?? 0;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Masukkan jumlah kas')));
      return;
    }
    setState(() => _loading = true);
    try {
      await ref.read(databaseProvider).reportsDao.addCashFlow(
            type: _type,
            category: _category,
            amount: amount,
            description: _descCtrl.text.trim().isEmpty
                ? null
                : _descCtrl.text.trim(),
          );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '${_type == 'income' ? '✅ Kas masuk' : '🔴 Kas keluar'} ${CurrencyFormatter.format(amount)} dicatat'),
          backgroundColor:
              _type == 'income' ? AppColors.success : AppColors.danger,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isIncome = _type == 'income';
    final color = isIncome ? AppColors.success : AppColors.danger;

    return Container(
      padding: EdgeInsets.only(
        top: 20,
        left: 20,
        right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 28,
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
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
          const SizedBox(height: 14),

          // Header row
          Row(
            children: [
              Expanded(
                child: Text(
                  isIncome ? 'Catat Kas Masuk' : 'Catat Kas Keluar',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close)),
            ],
          ),
          const SizedBox(height: 12),

          // Toggle Masuk / Keluar
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() {
                    _type = 'income';
                    _category = _incomeCategories.first;
                  }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: _type == 'income'
                          ? AppColors.success
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.arrow_circle_down_rounded,
                            size: 16,
                            color: _type == 'income'
                                ? Colors.white
                                : Colors.grey),
                        const SizedBox(width: 4),
                        Text('Kas Masuk',
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: _type == 'income'
                                    ? Colors.white
                                    : Colors.grey)),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() {
                    _type = 'expense';
                    _category = _expenseCategories.first;
                  }),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: _type == 'expense'
                          ? AppColors.danger
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.arrow_circle_up_rounded,
                            size: 16,
                            color: _type == 'expense'
                                ? Colors.white
                                : Colors.grey),
                        const SizedBox(width: 4),
                        Text('Kas Keluar',
                            style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: _type == 'expense'
                                    ? Colors.white
                                    : Colors.grey)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Kategori (chip selector)
          const Text('Kategori',
              style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _categories.map((cat) {
              final sel = cat == _category;
              return GestureDetector(
                onTap: () => setState(() => _category = cat),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: sel
                        ? color.withOpacity(0.1)
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: sel ? color : Colors.transparent),
                  ),
                  child: Text(cat,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color:
                              sel ? color : AppColors.textSecondary)),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),

          // Input Jumlah
          TextField(
            controller: _amountCtrl,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style:
                const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            decoration: InputDecoration(
              labelText: 'Jumlah',
              prefixText: 'Rp ',
              hintText: '0',
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: color, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Input Keterangan
          TextField(
            controller: _descCtrl,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: 'Keterangan (opsional)',
              hintText: 'cth: Bayar tagihan listrik bulan Mei',
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: color, width: 1.5),
              ),
            ),
          ),
          const SizedBox(height: 18),

          // Tombol Simpan
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: color,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: _loading ? null : _save,
              child: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : Text(
                      isIncome
                          ? 'Simpan Kas Masuk'
                          : 'Simpan Kas Keluar',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// PERIOD CHIP
// ─────────────────────────────────────────────────────────────────────────────

class _PeriodChip extends StatelessWidget {
  final String label, value, current;
  final void Function(String) onChanged;
  const _PeriodChip(this.label, this.value, this.current, this.onChanged);

  @override
  Widget build(BuildContext context) {
    final isSelected = value == current;
    return GestureDetector(
      onTap: () => onChanged(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(right: 8),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
              color: isSelected
                  ? AppColors.primary
                  : Colors.grey.shade300),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isSelected
                    ? Colors.white
                    : Colors.grey.shade700)),
      ),
    );
  }
}
