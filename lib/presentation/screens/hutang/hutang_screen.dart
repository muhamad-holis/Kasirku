// lib/presentation/screens/hutang/hutang_screen.dart
// ─────────────────────────────────────────────────────────────────────────────
// Manajemen Hutang Piutang — P1
// Fitur: Daftar hutang, Bayar hutang, Riwayat pelunasan, Tagihan jatuh tempo
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' show Value;
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency.dart';
import '../../../core/utils/responsive.dart';
import '../../../data/database/app_database.dart';
import '../../providers/database_provider.dart';
import '../../providers/hutang_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SCREEN UTAMA
// ─────────────────────────────────────────────────────────────────────────────

// FITUR TABLET: provider lokal untuk menyimpan hutang yang sedang dipilih
// di layout master-detail tablet. Null = belum ada yang dipilih.
// Dipakai oleh _DebtCard untuk "memberi tahu" screen utama hutang mana
// yang ingin ditampilkan di panel detail kanan. Di mobile, provider ini
// tetap ada tapi tidak digunakan (_DebtCard tetap buka bottom sheet biasa).
final _selectedDebtProvider =
    StateProvider<({Debt debt, String customerName})?>((ref) => null);

class HutangScreen extends ConsumerStatefulWidget {
  const HutangScreen({super.key});

  @override
  ConsumerState<HutangScreen> createState() => _HutangScreenState();
}

class _HutangScreenState extends ConsumerState<HutangScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

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

  @override
  Widget build(BuildContext context) {
    final summary = ref.watch(hutangSummaryProvider);
    final selected = ref.watch(_selectedDebtProvider);
    final isTabletLandscape = Responsive.isTabletLandscape(context);

    // Widget daftar hutang (pakai di kedua layout)
    final listWidget = Column(
      children: [
        summary.when(
          data: (s) => _SummaryBar(summary: s),
          loading: () => const SizedBox(height: 72),
          error: (_, __) => const SizedBox(),
        ),
        Expanded(
          child: TabBarView(
            controller: _tab,
            children: const [
              _AllDebtsTab(),
              _UnpaidDebtsTab(),
              _DueTodayTab(),
            ],
          ),
        ),
      ],
    );

    // FITUR TABLET: master-detail 2 kolom saat tablet landscape —
    // daftar hutang (dengan tab Semua/Belum Lunas/Jatuh Tempo) di kiri,
    // detail hutang terpilih di kanan. _DebtCard meng-set
    // _selectedDebtProvider saat di-tap alih-alih buka bottom sheet.
    if (isTabletLandscape) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Hutang Piutang',
              style: TextStyle(fontWeight: FontWeight.w700)),
          bottom: TabBar(
            controller: _tab,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white60,
            indicatorColor: Colors.white,
            indicatorWeight: 3,
            tabs: const [
              Tab(text: 'Semua'),
              Tab(text: 'Belum Lunas'),
              Tab(text: 'Jatuh Tempo'),
            ],
          ),
        ),
        body: Row(
          children: [
            Expanded(flex: 2, child: listWidget),
            const VerticalDivider(width: 1),
            Expanded(
              flex: 3,
              child: selected == null
                  ? const _NoSelectionPlaceholder(
                      icon: Icons.receipt_long_outlined,
                      label: 'Pilih hutang untuk melihat detail',
                    )
                  : _DebtDetailPanel(
                      key: ValueKey(selected.debt.id),
                      debt: selected.debt,
                      customerName: selected.customerName,
                    ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Hutang Piutang',
            style: TextStyle(fontWeight: FontWeight.w700)),
        bottom: TabBar(
          controller: _tab,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          tabs: const [
            Tab(text: 'Semua'),
            Tab(text: 'Belum Lunas'),
            Tab(text: 'Jatuh Tempo'),
          ],
        ),
      ),
      body: listWidget,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SUMMARY BAR
// ─────────────────────────────────────────────────────────────────────────────

class _SummaryBar extends StatelessWidget {
  final HutangSummary summary;
  const _SummaryBar({required this.summary});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          _SummaryChip(
            label: 'Total Hutang',
            value: CurrencyFormatter.format(summary.totalDebt),
            color: AppColors.danger,
            icon: Icons.receipt_long_outlined,
          ),
          const SizedBox(width: 8),
          _SummaryChip(
            label: 'Sudah Bayar',
            value: CurrencyFormatter.format(summary.totalPaid),
            color: AppColors.success,
            icon: Icons.check_circle_outline,
          ),
          const SizedBox(width: 8),
          _SummaryChip(
            label: 'Sisa',
            value: CurrencyFormatter.format(summary.totalRemaining),
            color: AppColors.warning,
            icon: Icons.pending_outlined,
          ),
        ],
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final String label, value;
  final Color color;
  final IconData icon;
  const _SummaryChip({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(height: 4),
            Text(value,
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    color: color)),
            Text(label,
                style: const TextStyle(fontSize: 9, color: Colors.grey)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB: SEMUA HUTANG
// ─────────────────────────────────────────────────────────────────────────────

class _AllDebtsTab extends ConsumerWidget {
  const _AllDebtsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final debtsAsync = ref.watch(allDebtsWithCustomerProvider);

    return debtsAsync.when(
      data: (list) {
        if (list.isEmpty) {
          return _EmptyState(
              message: 'Belum ada data hutang',
              icon: Icons.receipt_long_outlined);
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
          itemCount: list.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) => _DebtCard(
            debt: list[i].debt,
            customerName: list[i].customerName,
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB: BELUM LUNAS
// ─────────────────────────────────────────────────────────────────────────────

class _UnpaidDebtsTab extends ConsumerWidget {
  const _UnpaidDebtsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final debtsAsync = ref.watch(unpaidDebtsWithCustomerProvider);

    return debtsAsync.when(
      data: (list) {
        if (list.isEmpty) {
          return _EmptyState(
              message: '🎉 Semua hutang sudah lunas!',
              icon: Icons.check_circle_outline,
              color: AppColors.success);
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
          itemCount: list.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) => _DebtCard(
            debt: list[i].debt,
            customerName: list[i].customerName,
            showPayButton: true,
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TAB: JATUH TEMPO
// ─────────────────────────────────────────────────────────────────────────────

class _DueTodayTab extends ConsumerWidget {
  const _DueTodayTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final debtsAsync = ref.watch(overdueDebtsWithCustomerProvider);

    return debtsAsync.when(
      data: (list) {
        if (list.isEmpty) {
          return _EmptyState(
              message: 'Tidak ada tagihan yang jatuh tempo',
              icon: Icons.event_available_outlined,
              color: AppColors.success);
        }
        return Column(
          children: [
            // Warning banner
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.danger.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.danger.withOpacity(0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: AppColors.danger, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${list.length} tagihan jatuh tempo atau terlambat. Segera hubungi pelanggan!',
                      style: const TextStyle(
                          color: AppColors.danger,
                          fontSize: 12,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) => _DebtCard(
                  debt: list[i].debt,
                  customerName: list[i].customerName,
                  showPayButton: true,
                  highlightDue: true,
                ),
              ),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DEBT CARD
// ─────────────────────────────────────────────────────────────────────────────

class _DebtCard extends ConsumerWidget {
  final Debt debt;
  final String customerName;
  final bool showPayButton;
  final bool highlightDue;

  const _DebtCard({
    required this.debt,
    required this.customerName,
    this.showPayButton = false,
    this.highlightDue = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sisa = debt.amount - debt.paidAmount;
    final isLunas = debt.status == 'paid';
    final isOverdue = debt.dueDate != null &&
        debt.dueDate!.isBefore(DateTime.now()) &&
        !isLunas;

    Color cardBorderColor = Colors.grey.shade200;
    if (highlightDue && isOverdue) cardBorderColor = AppColors.danger;
    if (isLunas) cardBorderColor = AppColors.success.withOpacity(0.3);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cardBorderColor),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _showDetail(context, ref),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Header ────────────────────────────────────────────────
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _statusColor(debt.status).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        isLunas
                            ? Icons.check_circle_outline
                            : Icons.receipt_long_outlined,
                        size: 18,
                        color: _statusColor(debt.status),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(customerName,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w700, fontSize: 14)),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              _StatusBadge(debt.status),
                              if (isOverdue) ...[
                                const SizedBox(width: 4),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color:
                                        AppColors.danger.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text('TERLAMBAT',
                                      style: TextStyle(
                                          fontSize: 9,
                                          color: AppColors.danger,
                                          fontWeight: FontWeight.w800)),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(CurrencyFormatter.format(debt.amount),
                            style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 14)),
                        if (!isLunas)
                          Text('Sisa: ${CurrencyFormatter.format(sisa)}',
                              style: const TextStyle(
                                  fontSize: 11, color: AppColors.danger)),
                      ],
                    ),
                  ],
                ),

                // ── Due date & notes ───────────────────────────────────────
                if (debt.dueDate != null || debt.notes != null) ...[
                  const Divider(height: 16, thickness: 0.5),
                  Row(
                    children: [
                      if (debt.dueDate != null) ...[
                        Icon(
                          Icons.event_outlined,
                          size: 12,
                          color: isOverdue
                              ? AppColors.danger
                              : Colors.grey.shade500,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Jatuh: ${DateFormat('dd MMM yyyy', 'id').format(debt.dueDate!)}',
                          style: TextStyle(
                              fontSize: 11,
                              color: isOverdue
                                  ? AppColors.danger
                                  : Colors.grey.shade500,
                              fontWeight: isOverdue
                                  ? FontWeight.w700
                                  : FontWeight.normal),
                        ),
                      ],
                      const Spacer(),
                      if (debt.notes != null && debt.notes!.isNotEmpty)
                        Flexible(
                          child: Text(
                            debt.notes!,
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey.shade500),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),
                ],

                // ── Bayar button ───────────────────────────────────────────
                if (showPayButton && !isLunas) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.success,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.payments_outlined, size: 16),
                      label: const Text('Bayar Hutang',
                          style: TextStyle(fontSize: 13)),
                      onPressed: () => _showBayarSheet(context, ref),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'paid':
        return AppColors.success;
      case 'partial':
        return AppColors.warning;
      default:
        return AppColors.danger;
    }
  }

  void _showDetail(BuildContext context, WidgetRef ref) {
    // FITUR TABLET: set provider lokal agar screen utama menampilkan panel
    // detail di kanan. Di mobile, tetap buka bottom sheet seperti semula.
    if (Responsive.isTabletLandscape(context)) {
      ref.read(_selectedDebtProvider.notifier).state =
          (debt: debt, customerName: customerName);
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => ProviderScope(
        parent: ProviderScope.containerOf(context),
        child: _DebtDetailSheet(
            debt: debt,
            customerName: customerName),
      ),
    );
  }

  void _showBayarSheet(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => ProviderScope(
        parent: ProviderScope.containerOf(context),
        child: _BayarHutangSheet(
            debt: debt,
            customerName: customerName),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BAYAR HUTANG SHEET
// ─────────────────────────────────────────────────────────────────────────────

class _BayarHutangSheet extends ConsumerStatefulWidget {
  final Debt debt;
  final String customerName;
  const _BayarHutangSheet(
      {required this.debt, required this.customerName});

  @override
  ConsumerState<_BayarHutangSheet> createState() => _BayarHutangSheetState();
}

class _BayarHutangSheetState extends ConsumerState<_BayarHutangSheet> {
  final _amountCtrl = TextEditingController();
  bool _loading = false;
  bool _lunasSemua = false;

  double get _sisa => widget.debt.amount - widget.debt.paidAmount;

  @override
  void initState() {
    super.initState();
    _amountCtrl.text = _sisa.toStringAsFixed(0);
  }

  @override
  void dispose() {
    _amountCtrl.dispose();
    super.dispose();
  }

  Future<void> _bayar() async {
    final raw = _amountCtrl.text.replaceAll(RegExp(r'[^\d]'), '');
    final amount = double.tryParse(raw) ?? 0;

    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Masukkan jumlah pembayaran')));
      return;
    }
    if (amount > _sisa) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pembayaran melebihi sisa hutang')));
      return;
    }

    setState(() => _loading = true);
    try {
      await ref.read(databaseProvider).debtsDao.payDebt(widget.debt.id, amount);

      // Catat juga ke cash_flows sebagai kas masuk
      await ref.read(databaseProvider).reportsDao.addCashFlow(
            type: 'income',
            category: 'pelunasan_hutang',
            amount: amount,
            // BUG #3 FIX: Tambahkan marker unik [debt_id:X] agar filter riwayat
            // pembayaran di debtPaymentHistoryProvider bisa eksak per hutang.
            // Format lama 'Invoice #X' menyebabkan filter selalu true untuk semua
            // cash_flow pelunasan_hutang → riwayat campur semua pelanggan.
            description:
                'Bayar hutang ${widget.customerName} [debt_id:${widget.debt.id}]',
          );

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
                'Pembayaran ${CurrencyFormatter.format(amount)} berhasil dicatat'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal: $e')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Bayar Hutang',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w800)),
                      Text(widget.customerName,
                          style: TextStyle(
                              color: Colors.grey.shade600, fontSize: 13)),
                    ],
                  ),
                ),
                IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close)),
              ],
            ),
            const SizedBox(height: 16),

            // Info hutang
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.bg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  _InfoRow(
                      label: 'Total Hutang',
                      value: CurrencyFormatter.format(widget.debt.amount)),
                  const SizedBox(width: 16),
                  _InfoRow(
                      label: 'Sudah Bayar',
                      value: CurrencyFormatter.format(widget.debt.paidAmount),
                      color: AppColors.success),
                  const SizedBox(width: 16),
                  _InfoRow(
                      label: 'Sisa',
                      value: CurrencyFormatter.format(_sisa),
                      color: AppColors.danger),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Lunas semua toggle
            GestureDetector(
              onTap: () {
                setState(() {
                  _lunasSemua = !_lunasSemua;
                  if (_lunasSemua) {
                    _amountCtrl.text = _sisa.toStringAsFixed(0);
                  }
                });
              },
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: _lunasSemua
                          ? AppColors.success
                          : Colors.transparent,
                      border: Border.all(
                          color: _lunasSemua
                              ? AppColors.success
                              : Colors.grey.shade400),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: _lunasSemua
                        ? const Icon(Icons.check,
                            size: 14, color: Colors.white)
                        : null,
                  ),
                  const SizedBox(width: 8),
                  const Text('Lunasi semua sekaligus',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Input jumlah
            TextField(
              controller: _amountCtrl,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              enabled: !_lunasSemua,
              decoration: InputDecoration(
                labelText: 'Jumlah Pembayaran',
                prefixText: 'Rp ',
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
                suffixIcon: _lunasSemua
                    ? const Icon(Icons.lock_outline, size: 16)
                    : null,
              ),
            ),
            const SizedBox(height: 20),

            // Tombol bayar
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.success,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _loading ? null : _bayar,
                child: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Text('Konfirmasi Pembayaran',
                        style: TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DEBT DETAIL SHEET — Riwayat Pelunasan
// ─────────────────────────────────────────────────────────────────────────────

class _DebtDetailSheet extends ConsumerWidget {
  final Debt debt;
  final String customerName;
  const _DebtDetailSheet(
      {required this.debt, required this.customerName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync =
        ref.watch(debtPaymentHistoryProvider(debt.id));

    final sisa = debt.amount - debt.paidAmount;
    final isLunas = debt.status == 'paid';

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, sc) => Container(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
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
            const SizedBox(height: 16),

            // Title
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(customerName,
                          style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800)),
                      Text(
                        isLunas
                            ? 'Lunas'
                            : 'Sisa: ${CurrencyFormatter.format(sisa)}',
                        style: TextStyle(
                            color:
                                isLunas ? AppColors.success : AppColors.danger,
                            fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                _StatusBadge(debt.status, large: true),
              ],
            ),
            const Divider(height: 24),

            // Info
            Row(
              children: [
                _InfoRow(
                    label: 'Total',
                    value: CurrencyFormatter.format(debt.amount)),
                const SizedBox(width: 16),
                _InfoRow(
                    label: 'Bayar',
                    value:
                        CurrencyFormatter.format(debt.paidAmount),
                    color: AppColors.success),
                const SizedBox(width: 16),
                _InfoRow(
                    label: 'Sisa',
                    value: CurrencyFormatter.format(sisa),
                    color: isLunas ? Colors.grey : AppColors.danger),
              ],
            ),

            if (debt.dueDate != null) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.event_outlined,
                      size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(
                    'Jatuh tempo: ${DateFormat('dd MMMM yyyy', 'id').format(debt.dueDate!)}',
                    style: TextStyle(
                        fontSize: 12,
                        color:
                            debt.dueDate!.isBefore(DateTime.now()) &&
                                    !isLunas
                                ? AppColors.danger
                                : Colors.grey.shade600),
                  ),
                ],
              ),
            ],

            if (debt.notes != null && debt.notes!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Catatan: ${debt.notes}',
                style: TextStyle(
                    fontSize: 12, color: Colors.grey.shade500),
              ),
            ],

            const SizedBox(height: 16),
            const Text('Riwayat Pembayaran',
                style:
                    TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 8),

            // History list
            Expanded(
              child: historyAsync.when(
                data: (payments) {
                  if (payments.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.history_outlined,
                              size: 40, color: Colors.grey.shade300),
                          const SizedBox(height: 8),
                          Text('Belum ada pembayaran',
                              style: TextStyle(
                                  color: Colors.grey.shade400)),
                        ],
                      ),
                    );
                  }
                  return ListView.separated(
                    controller: sc,
                    itemCount: payments.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (_, i) => _PaymentHistoryRow(
                        payment: payments[i]),
                  );
                },
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('$e')),
              ),
            ),

            // Bayar button if not lunas
            if (!isLunas) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.success,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  icon:
                      const Icon(Icons.payments_outlined, size: 18),
                  label: const Text('Bayar Sekarang',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15)),
                  onPressed: () {
                    Navigator.pop(context);
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.vertical(
                              top: Radius.circular(24))),
                      builder: (_) => ProviderScope(
                        parent: ProviderScope.containerOf(context),
                        child: _BayarHutangSheet(
                            debt: debt,
                            customerName: customerName),
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PaymentHistoryRow extends StatelessWidget {
  final DebtPayment payment;
  const _PaymentHistoryRow({required this.payment});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: AppColors.success.withOpacity(0.1),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.arrow_downward_rounded,
            size: 16, color: AppColors.success),
      ),
      title: Text(CurrencyFormatter.format(payment.amount),
          style:
              const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
      subtitle: Text(payment.description ?? 'Pembayaran hutang',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
      trailing: Text(
        DateFormat('dd MMM\nHH:mm', 'id').format(payment.date),
        style: TextStyle(fontSize: 10, color: Colors.grey.shade400),
        textAlign: TextAlign.right,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// HELPERS
// ─────────────────────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  final String status;
  final bool large;
  const _StatusBadge(this.status, {this.large = false});

  @override
  Widget build(BuildContext context) {
    Color c;
    String label;
    switch (status) {
      case 'paid':
        c = AppColors.success;
        label = 'Lunas';
        break;
      case 'partial':
        c = AppColors.warning;
        label = 'Sebagian';
        break;
      default:
        c = AppColors.danger;
        label = 'Belum Bayar';
    }
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: large ? 10 : 6, vertical: large ? 4 : 2),
      decoration: BoxDecoration(
        color: c.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.withOpacity(0.3)),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: large ? 12 : 10,
              fontWeight: FontWeight.w700,
              color: c)),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label, value;
  final Color? color;
  const _InfoRow(
      {required this.label, required this.value, this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style:
                  TextStyle(fontSize: 10, color: Colors.grey.shade500)),
          Text(value,
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: color)),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String message;
  final IconData icon;
  final Color? color;
  const _EmptyState(
      {required this.message, required this.icon, this.color});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon,
              size: 56,
              color: (color ?? Colors.grey).withOpacity(0.4)),
          const SizedBox(height: 12),
          Text(message,
              style: TextStyle(
                  color: Colors.grey.shade500,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

// ─── FITUR TABLET: Placeholder saat belum ada hutang terpilih ───────────────

class _NoSelectionPlaceholder extends StatelessWidget {
  final IconData icon;
  final String label;
  const _NoSelectionPlaceholder({
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      color: isDark ? AppColors.darkBg : Colors.grey.shade50,
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: Colors.grey.shade300),
            const SizedBox(height: 16),
            Text(label,
                style: TextStyle(
                    color: Colors.grey.shade400, fontSize: 15)),
          ],
        ),
      ),
    );
  }
}

// ─── FITUR TABLET: Panel detail hutang untuk layout master-detail ────────────
// Konten identik dengan _DebtDetailSheet, namun dibungkus sebagai panel biasa
// tanpa DraggableScrollableSheet. Tombol "Bayar Sekarang" tetap membuka
// _BayarHutangSheet sebagai modal, karena pembayaran adalah aksi yang
// memang layak tampil sebagai modal di semua device.

class _DebtDetailPanel extends ConsumerWidget {
  final Debt debt;
  final String customerName;

  const _DebtDetailPanel({
    super.key,
    required this.debt,
    required this.customerName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(debtPaymentHistoryProvider(debt.id));
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sisa = debt.amount - debt.paidAmount;
    final isLunas = debt.status == 'paid';

    return Container(
      color: isDark ? AppColors.darkBg : Colors.grey.shade50,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ────────────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            decoration: BoxDecoration(
              color: isDark ? AppColors.darkCard : Colors.white,
              border: Border(
                bottom: BorderSide(
                  color: isDark
                      ? AppColors.darkBorder
                      : Colors.grey.shade200,
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(customerName,
                          style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800)),
                      Text(
                        isLunas
                            ? 'Lunas'
                            : 'Sisa: ${CurrencyFormatter.format(sisa)}',
                        style: TextStyle(
                            color: isLunas
                                ? AppColors.success
                                : AppColors.danger,
                            fontWeight: FontWeight.w600,
                            fontSize: 13),
                      ),
                    ],
                  ),
                ),
                _StatusBadge(debt.status, large: true),
              ],
            ),
          ),

          // ── Info ringkasan ────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Row(
              children: [
                _InfoRow(
                    label: 'Total',
                    value: CurrencyFormatter.format(debt.amount)),
                const SizedBox(width: 16),
                _InfoRow(
                    label: 'Bayar',
                    value: CurrencyFormatter.format(debt.paidAmount),
                    color: AppColors.success),
                const SizedBox(width: 16),
                _InfoRow(
                    label: 'Sisa',
                    value: CurrencyFormatter.format(sisa),
                    color: isLunas ? Colors.grey : AppColors.danger),
              ],
            ),
          ),

          if (debt.dueDate != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Row(
                children: [
                  const Icon(Icons.event_outlined,
                      size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(
                    'Jatuh tempo: ${DateFormat('dd MMMM yyyy', 'id').format(debt.dueDate!)}',
                    style: TextStyle(
                        fontSize: 12,
                        color: debt.dueDate!.isBefore(DateTime.now()) &&
                                !isLunas
                            ? AppColors.danger
                            : Colors.grey.shade600),
                  ),
                ],
              ),
            ),

          if (debt.notes != null && debt.notes!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
              child: Text('Catatan: ${debt.notes}',
                  style: TextStyle(
                      fontSize: 12, color: Colors.grey.shade500)),
            ),

          const Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Text('Riwayat Pembayaran',
                style:
                    TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          ),
          const SizedBox(height: 8),

          // ── Riwayat pembayaran ────────────────────────────────────────────
          Expanded(
            child: historyAsync.when(
              data: (payments) {
                if (payments.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.history_outlined,
                            size: 40, color: Colors.grey.shade300),
                        const SizedBox(height: 8),
                        Text('Belum ada pembayaran',
                            style: TextStyle(
                                color: Colors.grey.shade400)),
                      ],
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: payments.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) =>
                      _PaymentHistoryRow(payment: payments[i]),
                );
              },
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('$e')),
            ),
          ),

          // ── Tombol bayar ──────────────────────────────────────────────────
          if (!isLunas)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.success,
                    padding:
                        const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.payments_outlined, size: 18),
                  label: const Text('Bayar Sekarang',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15)),
                  onPressed: () => showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(
                            top: Radius.circular(24))),
                    builder: (_) => ProviderScope(
                      parent: ProviderScope.containerOf(context),
                      child: _BayarHutangSheet(
                          debt: debt,
                          customerName: customerName),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
