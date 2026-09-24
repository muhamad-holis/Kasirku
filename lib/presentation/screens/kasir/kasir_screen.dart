import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' show Value;
import 'package:pdf/widgets.dart' as pw;
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../../core/utils/sound_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency.dart';
import '../../../core/utils/responsive.dart';
import '../../../core/utils/receipt_pdf_builder.dart';
import '../../providers/kasir_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/products_provider.dart';
import '../../providers/database_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/auth_provider.dart';
import '../../../data/database/app_database.dart';
import '../dashboard/dashboard_screen.dart' show dashboardStatsProvider;
import '../../navigation/app_router.dart' show currentNavIndexProvider;
import 'manual_nota_screen.dart';

// Index tab "Kasir" pada bottom navigation (lihat _screens di app_router.dart)
const int _kKasirTabIndex = 2;

class KasirScreen extends ConsumerStatefulWidget {
  const KasirScreen({super.key});

  @override
  ConsumerState<KasirScreen> createState() => _KasirScreenState();
}

class _KasirScreenState extends ConsumerState<KasirScreen> {
  /// Popup dipanggil setiap kali tab Kasir ditekan. "Otomatis" melanjutkan
  /// alur kasir yang sudah ada (scan barcode → keranjang → bayar, TIDAK
  /// diubah). "Manual" membuka ManualNotaScreen (ketik bebas nama & harga,
  /// tidak menyentuh stok/Products sama sekali).
  Future<void> _showKasirModeDialog() async {
    final mode = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.point_of_sale_outlined, color: AppColors.primary, size: 22),
            SizedBox(width: 8),
            Text('Mode Kasir', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ],
        ),
        content: const Text('Pilih cara mencatat transaksi kali ini.'),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          OutlinedButton.icon(
            onPressed: () => Navigator.pop(context, 'manual'),
            icon: const Icon(Icons.edit_note_outlined),
            label: const Text('Manual'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
            onPressed: () => Navigator.pop(context, 'otomatis'),
            icon: const Icon(Icons.qr_code_scanner_outlined),
            label: const Text('Otomatis'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (mode == 'manual') {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ProviderScope(
            parent: ProviderScope.containerOf(context),
            child: const ManualNotaScreen(),
          ),
        ),
      );
    } else if (mode == 'otomatis') {
      _openScanner();
    }
    // Kalau dialog ditutup tanpa pilihan (mis. back button Android), tidak
    // ada aksi lanjutan — user tetap di tab Kasir seperti biasa.
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      // Cek draft tersimpan
      final notifier = ref.read(kasirProvider.notifier);
      final has = await notifier.hasDraft();
      if (has && mounted) {
        final draftTime = await notifier.getDraftTime();
        final timeStr = draftTime != null
            ? DateFormat('HH:mm, dd MMM').format(draftTime)
            : '';
        if (!mounted) return;
        final load = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Ada Draft Tersimpan'),
            content: Text('Draft transaksi dari $timeStr ditemukan. Lanjutkan?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Mulai Baru')),
              ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Lanjutkan')),
            ],
          ),
        );
        if (load == true) {
          // BUG #8 FIX: Pass db agar loadDraft bisa refresh stok dari DB
          final db = ref.read(databaseProvider);
          await notifier.loadDraft(db);
        } else {
          await notifier.clearDraft();
        }
      }
      // Catatan: scanner TIDAK lagi auto-dibuka saat cold start.
      // Scanner hanya dibuka saat user aktif menekan tab "Kasir"
      // di bottom navigation — lihat ref.listen di method build().
    });
  }

  void _openScanner() {
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black87,
      transitionDuration: const Duration(milliseconds: 250),
      transitionBuilder: (ctx, anim, _, child) => FadeTransition(
        opacity: anim,
        child: child,
      ),
      pageBuilder: (ctx, _, __) => ProviderScope(
        parent: ProviderScope.containerOf(context),
        child: _BarcodeScannerSheet(
          onDetected: (code) async {
            final db = ref.read(databaseProvider);
            final product = await db.productsDao.getByBarcode(code);
            if (!mounted) return;
            if (product != null) {
              ref.read(kasirProvider.notifier).addProduct(product);
              HapticFeedback.mediumImpact();
              await SoundService.instance.beepScan();
            } else {
              await SoundService.instance.beepError();
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Row(children: [
                    const Icon(Icons.warning_amber_rounded,
                        color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    Text('Barcode "\$code" tidak ditemukan di produk'),
                  ]),
                  backgroundColor: AppColors.warning,
                  duration: const Duration(seconds: 2),
                ),
              );
            }
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(kasirProvider);

    // Setiap kali user aktif berpindah ke tab "Kasir" (bukan saat cold start,
    // karena IndexedStack membangun semua screen sekaligus), tanya dulu mode
    // yang mau dipakai: Manual (Nota Manual, ketik bebas) atau Otomatis
    // (alur kasir/scan barcode yang sudah ada, tidak diubah sama sekali).
    ref.listen<int>(currentNavIndexProvider, (previous, next) {
      if (next == _kKasirTabIndex && previous != _kKasirTabIndex) {
        _showKasirModeDialog();
      }
    });

    final isTabletLandscape = Responsive.isTabletLandscape(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kasir',
          style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          if (!cart.isEmpty)
            TextButton.icon(
              icon: const Icon(Icons.delete_sweep_outlined,
                color: Colors.white70, size: 18),
              label: const Text('Hapus',
                style: TextStyle(color: Colors.white70, fontSize: 13)),
              onPressed: () => _confirmClear(context),
            ),
        ],
      ),
      // FITUR TABLET: di tablet landscape, tampilkan layout POS profesional
      // 2 kolom — grid produk browsable di kiri (selalu terlihat) dan
      // keranjang + ringkasan + tombol bayar di kanan (selalu terlihat).
      // Tidak perlu pindah tab atau buka halaman baru untuk melihat produk
      // sambil tetap melihat keranjang. Logic kasirProvider/addProduct/dll
      // TIDAK diubah sama sekali — hanya disusun ulang secara visual.
      body: isTabletLandscape
          ? Row(
              children: [
                // ── Kolom kiri: cari + grid produk ─────────────────────────
                Expanded(
                  flex: 3,
                  child: Column(
                    children: [
                      _SearchBar(onFocused: _onSearchFocused),
                      _ProductResults(),
                      const Expanded(child: _ProductGridTablet()),
                    ],
                  ),
                ),
                const VerticalDivider(width: 1),
                // ── Kolom kanan: keranjang (sama seperti layout mobile) ────
                Expanded(
                  flex: 2,
                  child: !cart.isEmpty
                      ? _KasirBody(cart: cart)
                      : const _EmptyCart(),
                ),
              ],
            )
          : Column(
              children: [
                _SearchBar(onFocused: _onSearchFocused),
                _ProductResults(),
                if (!cart.isEmpty)
                  Expanded(
                    child: _KasirBody(cart: cart),
                  )
                else
                  const Expanded(child: _EmptyCart()),
              ],
            ),
    );
  }

  // Dipanggil saat search bar difokus → tutup scanner bottom sheet jika terbuka.
  // CATATAN-03 FIX: popUntil dengan pengecekan named route tidak efektif untuk
  // bottom sheet (tidak punya route name), diganti dengan canPop() + pop() saja.
  void _onSearchFocused() {
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  void _confirmClear(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hapus Keranjang?'),
        content: const Text('Semua item akan dihapus dari keranjang.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal')),
          ElevatedButton(
            onPressed: () {
              ref.read(kasirProvider.notifier).clear();
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger),
            child: const Text('Hapus')),
        ],
      ),
    );
  }
}

// ─── Kasir Body (scroll: keranjang + ringkasan + bayar) ───────────────────────

class _KasirBody extends ConsumerWidget {
  final KasirState cart;
  const _KasirBody({required this.cart});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = isDark ? AppColors.darkBg : const Color(0xFFF5F7FA);

    return Container(
      color: bgColor,
      child: CustomScrollView(
        slivers: [
          // ── Header keranjang ──────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              color: Theme.of(context).cardColor,
              child: Row(
                children: [
                  Icon(Icons.shopping_cart_outlined,
                    size: 16, color: AppColors.primary),
                  const SizedBox(width: 6),
                  Text('Keranjang (${cart.totalItems})',
                    style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  TextButton.icon(
                    icon: const Icon(Icons.delete_outline,
                      size: 14, color: AppColors.danger),
                    label: const Text('Bersihkan',
                      style: TextStyle(
                        fontSize: 12, color: AppColors.danger)),
                    onPressed: () => _confirmClear(context, ref),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── Daftar item keranjang ─────────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) {
                  final item = cart.items[i];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Dismissible(
                      key: ValueKey(item.product.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 16),
                        decoration: BoxDecoration(
                          color: AppColors.danger.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(Icons.delete_outline,
                          color: AppColors.danger),
                      ),
                      onDismissed: (_) {
                        ref.read(kasirProvider.notifier)
                            .removeProduct(item.product.id);
                        HapticFeedback.mediumImpact();
                      },
                      child: Card(
                        margin: EdgeInsets.zero,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                          child: Row(children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: AppColors.primaryLight,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Icon(Icons.inventory_2_outlined,
                                size: 22, color: AppColors.primary),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(item.product.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis),
                                  const SizedBox(height: 2),
                                  Text(
                                    CurrencyFormatter.format(item.product.sellPrice),
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade500),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Qty + harga kanan
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Row(children: [
                                  _QtyBtn(
                                    icon: Icons.remove,
                                    onTap: () {
                                      ref.read(kasirProvider.notifier)
                                          .updateQuantity(item.product.id,
                                              item.quantity - 1);
                                      HapticFeedback.lightImpact();
                                    },
                                  ),
                                  GestureDetector(
                                    onTap: () => _editQty(context, ref, item),
                                    child: SizedBox(
                                      width: 32,
                                      child: Text('${item.quantity}',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          fontSize: 15)),
                                    ),
                                  ),
                                  _QtyBtn(
                                    icon: Icons.add,
                                    onTap: () {
                                      ref.read(kasirProvider.notifier)
                                          .updateQuantity(item.product.id,
                                              item.quantity + 1);
                                      HapticFeedback.lightImpact();
                                    },
                                  ),
                                ]),
                                const SizedBox(height: 2),
                                Text(
                                  CurrencyFormatter.format(item.subtotal),
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.primary),
                                ),
                              ],
                            ),
                          ]),
                        ),
                      ),
                    ),
                  );
                },
                childCount: cart.items.length,
              ),
            ),
          ),

          // ── Ringkasan Pembayaran ──────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Ringkasan Pembayaran',
                        style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 12),
                      _SummaryRow(
                        label: 'Subtotal',
                        value: CurrencyFormatter.format(cart.subtotal)),
                      if (cart.discountTotal > 0) ...[
                        const SizedBox(height: 6),
                        _SummaryRow(
                          label: 'Diskon',
                          value: '- ${CurrencyFormatter.format(cart.discountTotal)}',
                          valueColor: AppColors.danger),
                      ],
                      if (cart.taxAmount > 0) ...[
                        const SizedBox(height: 6),
                        _SummaryRow(
                          label: 'Pajak (${cart.taxPercent.toStringAsFixed(0)}%)',
                          value: '+ ${CurrencyFormatter.format(cart.taxAmount)}',
                          valueColor: AppColors.warning),
                      ],
                      if (cart.redeemPoints > 0) ...[
                        const SizedBox(height: 6),
                        _SummaryRow(
                          label: 'Diskon Poin',
                          value: '- ${CurrencyFormatter.format(cart.pointDiscount)}',
                          valueColor: AppColors.primary),
                      ],
                      const Divider(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Total',
                            style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w700)),
                          Text(CurrencyFormatter.format(cart.total),
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: AppColors.primary)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // ── Tombol Diskon, Pajak ──────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.local_offer_outlined, size: 16),
                    label: Text(
                      cart.discountTotal > 0 && cart.subtotal > 0
                          ? 'Diskon ${(cart.discountTotal / cart.subtotal * 100).toStringAsFixed(0)}%'
                          : 'Tambah Diskon',
                      style: const TextStyle(fontSize: 12)),
                    onPressed: () => _showDiscount(context, ref),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: cart.discountTotal > 0
                          ? AppColors.danger : null,
                      side: cart.discountTotal > 0
                          ? const BorderSide(color: AppColors.danger) : null,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.percent_outlined, size: 16),
                    label: Text(
                      cart.taxPercent > 0
                          ? 'Pajak ${cart.taxPercent.toStringAsFixed(0)}%'
                          : 'Tambah Pajak',
                      style: const TextStyle(fontSize: 12)),
                    onPressed: () => _showTax(context, ref),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: cart.taxPercent > 0
                          ? AppColors.warning : null,
                      side: cart.taxPercent > 0
                          ? const BorderSide(color: AppColors.warning) : null,
                    ),
                  ),
                ),
              ]),
            ),
          ),

          // ── Tombol Simpan Draft + Bayar ───────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
              child: Row(children: [
                // Simpan Draft
                OutlinedButton.icon(
                  icon: const Icon(Icons.save_outlined, size: 18),
                  label: const Text('Simpan Draft'),
                  onPressed: () => _saveDraft(context, ref),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  ),
                ),
                const SizedBox(width: 8),
                // Bayar
                Expanded(
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.payment, size: 18),
                    label: Text(
                      'Bayar  ${CurrencyFormatter.format(cart.total)}  →',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14)),
                    onPressed: () => _showPayment(context, ref),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ]),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 8)),
        ],
      ),
    );
  }

  void _confirmClear(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hapus Keranjang?'),
        content: const Text('Semua item akan dihapus dari keranjang.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal')),
          ElevatedButton(
            onPressed: () {
              ref.read(kasirProvider.notifier).clear();
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger),
            child: const Text('Hapus')),
        ],
      ),
    );
  }

  void _editQty(BuildContext context, WidgetRef ref, CartItem item) {
    final ctrl = TextEditingController(text: '${item.quantity}');
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(item.product.name,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Jumlah',
            suffixText: item.product.unit,
            helperText: 'Stok tersedia: ${item.product.stock}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal')),
          ElevatedButton(
            onPressed: () {
              final qty = int.tryParse(ctrl.text) ?? 1;
              ref.read(kasirProvider.notifier)
                  .updateQuantity(item.product.id, qty);
              Navigator.pop(context);
            },
            child: const Text('OK')),
        ],
      ),
    );
  }

  void _showDiscount(BuildContext context, WidgetRef ref) {
    final cart = ref.read(kasirProvider);
    final initialPercent = (cart.subtotal > 0 && cart.discountTotal > 0)
        ? (cart.discountTotal / cart.subtotal * 100)
        : 0.0;
    final ctrl = TextEditingController(
      text: initialPercent > 0
          ? (initialPercent % 1 == 0
              ? initialPercent.toStringAsFixed(0)
              : initialPercent.toStringAsFixed(2))
          : '');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetCtx) => AnimatedPadding(
        duration: const Duration(milliseconds: 100),
        curve: Curves.decelerate,
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 16,
          left: 20, right: 20, top: 20),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2)))),
              const SizedBox(height: 16),
              const Text('Tambah Diskon',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              Text(
                'Diskon dihitung dari subtotal ${CurrencyFormatter.format(cart.subtotal)}',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
              const SizedBox(height: 16),
              TextField(
                controller: ctrl,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Persentase Diskon',
                  suffixText: '%',
                  prefixIcon: Icon(Icons.percent_outlined))),
              const SizedBox(height: 16),
              Row(children: [
                Expanded(child: OutlinedButton(
                  onPressed: () {
                    ref.read(kasirProvider.notifier).setDiscount(0);
                    Navigator.pop(context);
                  },
                  child: const Text('Hapus Diskon'))),
                const SizedBox(width: 10),
                Expanded(child: ElevatedButton(
                  onPressed: () {
                    double percent = double.tryParse(ctrl.text) ?? 0;
                    if (percent < 0) percent = 0;
                    if (percent > 100) percent = 100;
                    final discAmount = cart.subtotal * (percent / 100);
                    ref.read(kasirProvider.notifier).setDiscount(discAmount);
                    Navigator.pop(context);
                  },
                  child: const Text('Terapkan'))),
              ]),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  void _showTax(BuildContext context, WidgetRef ref) {
    final cart = ref.read(kasirProvider);
    final ctrl = TextEditingController(
      text: cart.taxPercent > 0 ? cart.taxPercent.toStringAsFixed(0) : '');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetCtx) => AnimatedPadding(
        duration: const Duration(milliseconds: 100),
        curve: Curves.decelerate,
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 16,
          left: 20, right: 20, top: 20),
        child: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2)))),
            const SizedBox(height: 16),
            const Text('Atur Pajak',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Persentase Pajak', suffixText: '%')),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: OutlinedButton(
                onPressed: () {
                  ref.read(kasirProvider.notifier).setTax(0);
                  Navigator.pop(context);
                },
                child: const Text('Hapus Pajak'))),
              const SizedBox(width: 10),
              Expanded(child: ElevatedButton(
                onPressed: () {
                  final tax = double.tryParse(ctrl.text) ?? 0;
                  ref.read(kasirProvider.notifier).setTax(tax.clamp(0, 100));
                  Navigator.pop(context);
                },
                child: const Text('Terapkan'))),
            ]),
            const SizedBox(height: 8),
          ],
          ),
        ),
      ),
    );
  }

  void _showPayment(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => ProviderScope(
        parent: ProviderScope.containerOf(context),
        child: const _PaymentSheet(),
      ),
    );
  }

  Future<void> _saveDraft(BuildContext context, WidgetRef ref) async {
    await ref.read(kasirProvider.notifier).saveDraft();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(children: [
            Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Text('Draft berhasil disimpan'),
          ]),
          backgroundColor: AppColors.success,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }
}

// ─── Summary Row Helper ───────────────────────────────────────────────────────

class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  const _SummaryRow({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 13, color: Colors.grey.shade600)),
        Text(value, style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: valueColor ?? Theme.of(context).textTheme.bodyMedium?.color)),
      ],
    );
  }
}

// ─── Search Bar ──────────────────────────────────────────────────────────────

class _SearchBar extends ConsumerStatefulWidget {
  final VoidCallback? onFocused;
  const _SearchBar({this.onFocused});

  @override
  ConsumerState<_SearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends ConsumerState<_SearchBar> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (_focus.hasFocus) {
        // Tutup scanner saat user tap search bar
        widget.onFocused?.call();
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _openScanner() {
    showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black87,
      transitionDuration: const Duration(milliseconds: 250),
      transitionBuilder: (ctx, anim, _, child) => FadeTransition(
        opacity: anim,
        child: child,
      ),
      pageBuilder: (ctx, _, __) => ProviderScope(
        parent: ProviderScope.containerOf(context),
        child: _BarcodeScannerSheet(
          onDetected: (code) async {
            // Lookup produk by barcode → langsung masuk keranjang
            final db = ref.read(databaseProvider);
            final product = await db.productsDao.getByBarcode(code);
            if (!mounted) return;
            if (product != null) {
              ref.read(kasirProvider.notifier).addProduct(product);
              HapticFeedback.mediumImpact();
              await SoundService.instance.beepScan(); // ✅ beep sukses
            } else {
              // Barcode tidak ditemukan → fallback ke search
              _ctrl.text = code;
              ref.read(_kasirSearchProvider.notifier).state = code;
              await SoundService.instance.beepError(); // ❌ beep error
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Row(children: [
                    const Icon(Icons.warning_amber_rounded,
                        color: Colors.white, size: 18),
                    const SizedBox(width: 8),
                    Text('Barcode "$code" tidak ditemukan di produk'),
                  ]),
                  backgroundColor: AppColors.warning,
                  duration: const Duration(seconds: 2),
                ),
              );
            }
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Row(children: [
        Expanded(
          child: TextField(
            controller: _ctrl,
            focusNode: _focus,
            onChanged: (v) =>
                ref.read(_kasirSearchProvider.notifier).state = v,
            decoration: const InputDecoration(
              hintText: 'Cari nama / barcode produk...',
              prefixIcon: Icon(Icons.search, size: 20),
              isDense: true,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(12),
          ),
          child: IconButton(
            icon: const Icon(Icons.qr_code_scanner,
              color: Colors.white, size: 22),
            onPressed: _openScanner,
            tooltip: 'Scan Barcode',
          ),
        ),
      ]),
    );
  }
}

// ─── Barcode Scanner Sheet ────────────────────────────────────────────────────

class _BarcodeScannerSheet extends ConsumerStatefulWidget {
  final Future<void> Function(String code) onDetected;
  const _BarcodeScannerSheet({required this.onDetected});

  @override
  ConsumerState<_BarcodeScannerSheet> createState() =>
      _BarcodeScannerSheetState();
}

class _BarcodeScannerSheetState
    extends ConsumerState<_BarcodeScannerSheet> {
  final MobileScannerController _scannerCtrl = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
    torchEnabled: false,
  );

  bool _processing = false;
  bool _torchOn = false;

  // Riwayat scan dalam sesi ini: barcode -> jumlah scan
  final Map<String, int> _scanLog = {};
  // Nama produk terakhir yang berhasil discan
  String? _lastProductName;
  // Kode terakhir (untuk debounce)
  String? _lastCode;
  DateTime? _lastScanTime;

  @override
  void dispose() {
    _scannerCtrl.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) async {
    if (_processing) return;
    final barcode = capture.barcodes.firstOrNull;
    final code = barcode?.rawValue;
    if (code == null || code.isEmpty) return;

    // Debounce: abaikan scan yang sama dalam 1.5 detik
    final now = DateTime.now();
    if (_lastCode == code &&
        _lastScanTime != null &&
        now.difference(_lastScanTime!).inMilliseconds < 1500) return;

    _lastCode = code;
    _lastScanTime = now;
    _processing = true;

    HapticFeedback.mediumImpact();

    // Panggil callback (lookup + addProduct di parent)
    await widget.onDetected(code);

    if (mounted) {
      setState(() {
        _scanLog[code] = (_scanLog[code] ?? 0) + 1;
        _processing = false;
      });
    } else {
      _processing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    // ── LAYOUT FULLSCREEN: kamera di atas (30% layar), panel item scan di bawah.
    // Mirip gaya POS scanner modern — kamera selalu terlihat di atas,
    // daftar item yang sudah scan tampil di bawah secara real-time.
    final screenHeight = MediaQuery.of(context).size.height;
    final cameraHeight = screenHeight * 0.30;
    final totalScanned = _scanLog.values.fold(0, (a, b) => a + b);

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            // ── Bagian ATAS: Kamera (50% layar) ─────────────────────────────
            SizedBox(
              height: cameraHeight,
              child: Stack(
                children: [
                  // Kamera penuh memenuhi area atas
                  MobileScanner(
                    controller: _scannerCtrl,
                    onDetect: _onDetect,
                  ),

                  // AppBar overlay di atas kamera
                  Positioned(
                    top: 0, left: 0, right: 0,
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.black87, Colors.transparent],
                        ),
                      ),
                      padding: const EdgeInsets.fromLTRB(4, 8, 4, 20),
                      child: Row(children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back_ios_new,
                              color: Colors.white, size: 20),
                          onPressed: () => Navigator.pop(context),
                        ),
                        const Expanded(
                          child: Text('Scan Barcode',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            )),
                        ),
                        // Total item badge
                        if (totalScanned > 0)
                          Container(
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              '$totalScanned item',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        // Torch toggle
                        IconButton(
                          icon: Icon(
                            _torchOn
                                ? Icons.flashlight_on
                                : Icons.flashlight_off_outlined,
                            color: _torchOn ? Colors.yellow : Colors.white70,
                          ),
                          onPressed: () {
                            _scannerCtrl.toggleTorch();
                            setState(() => _torchOn = !_torchOn);
                          },
                        ),
                      ]),
                    ),
                  ),

                  // Viewfinder di tengah kamera
                  Center(
                    child: Container(
                      width: 240,
                      height: 120,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: AppColors.primary,
                          width: 3,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Stack(children: [
                        _Corner(Alignment.topLeft),
                        _Corner(Alignment.topRight),
                        _Corner(Alignment.bottomLeft),
                        _Corner(Alignment.bottomRight),
                      ]),
                    ),
                  ),

                  // Hint text di bawah kamera (gradient overlay bawah)
                  Positioned(
                    bottom: 0, left: 0, right: 0,
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [Colors.black87, Colors.transparent],
                        ),
                      ),
                      padding: const EdgeInsets.fromLTRB(0, 20, 0, 12),
                      child: const Center(
                        child: Text(
                          'Arahkan kamera ke barcode produk',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ── Bagian BAWAH: Panel item scan (50% sisa layar) ──────────────
            Expanded(
              child: Container(
                decoration: const BoxDecoration(
                  color: Color(0xFF1A1A2E),
                  borderRadius: BorderRadius.vertical(top: Radius.circular(0)),
                ),
                child: Column(
                  children: [
                    // Header panel
                    Container(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                      decoration: const BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: Colors.white12),
                        ),
                      ),
                      child: Row(children: [
                        const Icon(Icons.shopping_cart_outlined,
                            color: Colors.white70, size: 16),
                        const SizedBox(width: 8),
                        Text(
                          totalScanned > 0
                              ? 'Item Terpindai ($totalScanned)'
                              : 'Belum ada item',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ]),
                    ),

                    // Daftar item scan
                    Expanded(
                      child: _scanLog.isEmpty
                          ? const Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.qr_code_scanner,
                                      color: Colors.white24, size: 48),
                                  SizedBox(height: 12),
                                  Text('Scan barcode untuk\nmenambahkan produk',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.white38,
                                      fontSize: 13,
                                    )),
                                ],
                              ),
                            )
                          : ListView(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 8, horizontal: 12),
                              children: _scanLog.entries.map((e) => Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: Colors.white10,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: Colors.white12),
                                ),
                                child: Row(children: [
                                  Container(
                                    width: 32, height: 32,
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: const Icon(Icons.inventory_2_outlined,
                                        color: AppColors.primary, size: 16),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      e.key.length > 28
                                          ? '${e.key.substring(0, 28)}…'
                                          : e.key,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: AppColors.primary,
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                    child: Text(
                                      'x${e.value}',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ]),
                              )).toList(),
                            ),
                    ),

                    // Tombol selesai
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.check_circle_outline,
                              size: 18),
                          label: Text(totalScanned == 0
                              ? 'Scan Barcode untuk mulai'
                              : 'Selesai – $totalScanned item ditambahkan'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: totalScanned == 0
                                ? Colors.white24
                                : AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          onPressed: totalScanned == 0
                              ? null
                              : () => Navigator.pop(context),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Corner decorator untuk viewfinder
class _Corner extends StatelessWidget {
  final Alignment alignment;
  const _Corner(this.alignment);

  @override
  Widget build(BuildContext context) {
    final isTop    = alignment == Alignment.topLeft || alignment == Alignment.topRight;
    final isLeft   = alignment == Alignment.topLeft || alignment == Alignment.bottomLeft;
    return Positioned(
      top:    isTop    ? -1 : null,
      bottom: !isTop   ? -1 : null,
      left:   isLeft   ? -1 : null,
      right:  !isLeft  ? -1 : null,
      child: Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          border: Border(
            top:    isTop    ? const BorderSide(color: Colors.white, width: 3) : BorderSide.none,
            bottom: !isTop   ? const BorderSide(color: Colors.white, width: 3) : BorderSide.none,
            left:   isLeft   ? const BorderSide(color: Colors.white, width: 3) : BorderSide.none,
            right:  !isLeft  ? const BorderSide(color: Colors.white, width: 3) : BorderSide.none,
          ),
        ),
      ),
    );
  }
}

// ─── Product Search Results ───────────────────────────────────────────────────

class _ProductResults extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final query = ref.watch(_kasirSearchProvider);
    if (query.isEmpty) return const SizedBox();

    final results = ref.watch(_kasirFilteredProductsProvider);
    return results.when(
      data: (list) {
        if (list.isEmpty) {
          return Container(
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.search_off, color: Colors.grey.shade400, size: 18),
                const SizedBox(width: 8),
                Text('Produk tidak ditemukan',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 13)),
              ],
            ),
          );
        }
        return Container(
          constraints: const BoxConstraints(maxHeight: 220),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: list.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final p = list[i];
              final outOfStock = p.stock <= 0;
              return ListTile(
                dense: true,
                leading: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: outOfStock
                        ? Colors.grey.shade100
                        : AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.inventory_2_outlined,
                    size: 18,
                    color: outOfStock
                        ? Colors.grey.shade400
                        : AppColors.primary,
                  ),
                ),
                title: Text(p.name,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color: outOfStock ? Colors.grey : null,
                  )),
                subtitle: Text(CurrencyFormatter.format(p.sellPrice),
                  style: const TextStyle(
                    color: AppColors.primary, fontSize: 12)),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: outOfStock
                        ? AppColors.danger.withOpacity(0.1)
                        : p.stock <= p.minStock
                            ? AppColors.warning.withOpacity(0.1)
                            : AppColors.success.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    outOfStock ? 'Habis' : 'Stok: ${p.stock}',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: outOfStock
                          ? AppColors.danger
                          : p.stock <= p.minStock
                              ? AppColors.warning
                              : AppColors.success,
                    ),
                  ),
                ),
                onTap: () {
                  if (!outOfStock) {
                    ref.read(kasirProvider.notifier).addProduct(p);
                    ref.read(_kasirSearchProvider.notifier).state = '';
                    HapticFeedback.lightImpact();
                  }
                },
              );
            },
          ),
        );
      },
      loading: () => const LinearProgressIndicator(),
      error: (_, __) => const SizedBox(),
    );
  }
}

// FITUR TABLET: provider kategori terpisah khusus untuk grid produk di Kasir,
// supaya tidak berbagi state dengan selectedCategoryProvider yang sudah
// dipakai oleh Stok Screen (filteredStokProvider). Tanpa ini, memilih
// kategori di Kasir akan ikut mengubah filter di Stok Screen, dan sebaliknya.
final _kasirGridCategoryProvider = StateProvider<int?>((ref) => null);

// BUG-06 FIX: provider search terpisah khusus Kasir agar tidak mengotori
// productSearchProvider yang dipakai bersama oleh StokScreen.
final _kasirSearchProvider = StateProvider<String>((ref) => '');

// Provider filtered produk khusus kasir — membaca _kasirSearchProvider,
// bukan productSearchProvider, sehingga search di Kasir tidak bocor ke Stok.
final _kasirFilteredProductsProvider = FutureProvider<List<Product>>((ref) async {
  final query = ref.watch(_kasirSearchProvider);
  final db = ref.watch(databaseProvider);
  if (query.isEmpty) return db.productsDao.getAllProducts();
  return db.productsDao.searchProducts(query);
});

// _CartHeader sudah digantikan _KasirBody

// ─── FITUR TABLET: Grid Produk Browsable (kolom kiri saat landscape) ──────────
// Menampilkan semua produk dalam grid kartu yang bisa di-tap untuk langsung
// ditambah ke keranjang. Memakai provider yang sudah ada (productsStreamProvider,
// categoriesProvider, selectedCategoryProvider) dan addProduct() dari
// kasirProvider — tidak ada provider atau logic bisnis baru yang ditambahkan.
// Tujuannya supaya di tablet landscape, kasir bisa "browse & tap" produk
// tanpa harus selalu mengetik di search bar, sambil keranjang tetap terlihat
// di kolom kanan.

class _ProductGridTablet extends ConsumerWidget {
  const _ProductGridTablet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final productsAsync = ref.watch(productsStreamProvider);
    final categoriesAsync = ref.watch(categoriesProvider);
    final selectedCategory = ref.watch(_kasirGridCategoryProvider);

    return Column(
      children: [
        // ── Filter kategori (chip horizontal) ──────────────────────────────
        categoriesAsync.when(
          data: (categories) {
            if (categories.isEmpty) return const SizedBox();
            return SizedBox(
              height: 44,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                children: [
                  _CategoryChip(
                    label: 'Semua',
                    selected: selectedCategory == null,
                    onTap: () =>
                        ref.read(_kasirGridCategoryProvider.notifier).state = null,
                  ),
                  ...categories.map((c) => _CategoryChip(
                        label: c.name,
                        selected: selectedCategory == c.id,
                        onTap: () => ref
                            .read(_kasirGridCategoryProvider.notifier)
                            .state = c.id,
                      )),
                ],
              ),
            );
          },
          loading: () => const SizedBox(height: 44),
          error: (_, __) => const SizedBox(height: 44),
        ),
        // ── Grid produk ─────────────────────────────────────────────────────
        Expanded(
          child: productsAsync.when(
            data: (allProducts) {
              final list = selectedCategory == null
                  ? allProducts
                  : allProducts
                      .where((p) => p.categoryId == selectedCategory)
                      .toList();

              if (list.isEmpty) {
                return Center(
                  child: Text('Tidak ada produk',
                      style: TextStyle(color: Colors.grey.shade500)),
                );
              }

              return GridView.builder(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 100),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: Responsive.gridColumns(context),
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 0.78,
                ),
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final p = list[i];
                  return _ProductGridCardKasir(product: p);
                },
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
          ),
        ),
      ],
    );
  }
}

class _CategoryChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onTap(),
        selectedColor: AppColors.primary,
        labelStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: selected ? Colors.white : null,
        ),
      ),
    );
  }
}

class _ProductGridCardKasir extends ConsumerWidget {
  final Product product;
  const _ProductGridCardKasir({required this.product});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final outOfStock = product.stock <= 0;
    final cardBg = isDark ? AppColors.darkCard : Colors.white;
    final borderColor = isDark ? AppColors.darkBorder : Colors.grey.shade200;

    return Material(
      color: cardBg,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: outOfStock
            ? null
            : () {
                ref.read(kasirProvider.notifier).addProduct(product);
                HapticFeedback.lightImpact();
              },
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor),
          ),
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: outOfStock
                        ? Colors.grey.shade200
                        : AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.inventory_2_outlined,
                    size: 28,
                    color: outOfStock ? Colors.grey.shade400 : AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                product.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: outOfStock
                      ? Colors.grey
                      : (isDark ? Colors.white : AppColors.textPrimary),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                CurrencyFormatter.format(product.sellPrice),
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
              Text(
                outOfStock ? 'Stok habis' : 'Stok: ${product.stock}',
                style: TextStyle(
                  fontSize: 10.5,
                  color: outOfStock ? AppColors.danger : Colors.grey.shade500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}



class _QtyBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _QtyBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: AppColors.primary.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 16, color: AppColors.primary),
      ),
    );
  }
}

// ─── Payment Sheet ────────────────────────────────────────────────────────────

class _PaymentSheet extends ConsumerStatefulWidget {
  const _PaymentSheet();

  @override
  ConsumerState<_PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends ConsumerState<_PaymentSheet> {
  final _amountCtrl = TextEditingController();
  final _notesCtrl  = TextEditingController();
  String _method = 'tunai';
  bool _loading = false;

  // Untuk metode hutang
  Customer? _selectedCustomer;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cart = ref.watch(kasirProvider);
    final paid = double.tryParse(_amountCtrl.text) ?? 0;
    final change = paid - cart.total;
    final canPay = _method != 'tunai' || paid >= cart.total;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 20, right: 20, top: 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Pembayaran',
              style: TextStyle(
                fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  const Text('Total Pembayaran',
                    style: TextStyle(
                      color: Colors.white70, fontSize: 12)),
                  const SizedBox(height: 4),
                  Text(CurrencyFormatter.format(cart.total),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                    )),
                  Text('${cart.totalItems} item',
                    style: const TextStyle(
                      color: Colors.white70, fontSize: 12)),
                ],
              ),
            ),
            const SizedBox(height: 16),

            const Text('Metode Pembayaran',
              style: TextStyle(
                fontWeight: FontWeight.w600, fontSize: 13)),
            const SizedBox(height: 8),
            Row(
              children: [
                _buildMethodChip('tunai', Icons.payments_outlined, 'Tunai'),
                const SizedBox(width: 8),
                _buildMethodChip('qris', Icons.qr_code, 'QRIS'),
                const SizedBox(width: 8),
                _buildMethodChip('transfer', Icons.account_balance_outlined, 'Transfer'),
                const SizedBox(width: 8),
                _buildMethodChip('hutang', Icons.receipt_long_outlined, 'Hutang'),
              ],
            ),
            const SizedBox(height: 16),

            // ── Tampilan QRIS ──────────────────────────────────────────────
            if (_method == 'qris') ...[
              _QrisDisplay(onTap: () {}),
              const SizedBox(height: 16),
            ],

            // ── Tampilan info rekening Transfer ────────────────────────────
            if (_method == 'transfer') ...[
              _TransferAccountsDisplay(),
              const SizedBox(height: 16),
            ],

            if (_method == 'tunai') ...[
              TextField(
                controller: _amountCtrl,
                keyboardType: TextInputType.number,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Jumlah Uang Diterima',
                  prefixText: 'Rp ',
                  prefixIcon: Icon(Icons.payments_outlined),
                ),
              ),
              const SizedBox(height: 10),

              Wrap(
                spacing: 8, runSpacing: 8,
                children: _quickAmounts(cart.total)
                    .map((v) => ActionChip(
                      avatar: Icon(Icons.add, size: 14,
                        color: AppColors.primary),
                      label: Text(CurrencyFormatter.formatCompact(v),
                        style: const TextStyle(fontSize: 12)),
                      onPressed: () {
                        _amountCtrl.text = v.toStringAsFixed(0);
                        setState(() {});
                      },
                    ))
                    .toList(),
              ),

              if (change > 0) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.success.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.success.withOpacity(0.3)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(children: [
                        const Icon(Icons.change_circle_outlined,
                          color: AppColors.success, size: 18),
                        const SizedBox(width: 8),
                        const Text('Kembalian',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      ]),
                      Text(CurrencyFormatter.format(change),
                        style: const TextStyle(
                          color: AppColors.success,
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                        )),
                    ],
                  ),
                ),
              ] else if (_amountCtrl.text.isNotEmpty && change < 0) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(children: [
                    const Icon(Icons.warning_amber_outlined,
                      color: AppColors.danger, size: 16),
                    const SizedBox(width: 8),
                    Text('Kurang ${CurrencyFormatter.format(-change)}',
                      style: const TextStyle(
                        color: AppColors.danger,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      )),
                  ]),
                ),
              ],
              // ── Customer picker untuk metode Tunai ───────────────────────
              const SizedBox(height: 12),
              GestureDetector(
                onTap: _pickCustomer,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: _selectedCustomer != null
                          ? AppColors.primary.withOpacity(0.6)
                          : Colors.grey.shade300,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    color: _selectedCustomer != null
                        ? AppColors.primary.withOpacity(0.05)
                        : Colors.transparent,
                  ),
                  child: Row(children: [
                    Icon(
                      Icons.person_outline,
                      size: 20,
                      color: _selectedCustomer != null
                          ? AppColors.primary
                          : Colors.grey.shade500,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _selectedCustomer != null
                                ? _selectedCustomer!.name
                                : 'Pilih pelanggan (opsional)',
                            style: TextStyle(
                              fontWeight: _selectedCustomer != null
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                              color: _selectedCustomer != null
                                  ? AppColors.primary
                                  : Colors.grey.shade500,
                              fontSize: 14,
                            ),
                          ),
                          if (_selectedCustomer != null) ...[
                            const SizedBox(height: 2),
                            Builder(builder: (ctx) {
                              final pts = (cart.total / 10000).floor();
                              return Text(
                                '+$pts poin • Total poin: ${_selectedCustomer!.points + pts}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.warning,
                                ),
                              );
                            }),
                          ],
                        ],
                      ),
                    ),
                    if (_selectedCustomer != null)
                      GestureDetector(
                        onTap: () {
                          // BUG-04 FIX: reset poin saat pelanggan dihapus
                          ref.read(kasirProvider.notifier).setRedeemPoints(0);
                          setState(() => _selectedCustomer = null);
                        },
                        child: const Icon(Icons.close,
                          color: AppColors.danger, size: 18),
                      )
                    else
                      Icon(Icons.chevron_right,
                        color: Colors.grey.shade400, size: 18),
                  ]),
                ),
              ),
              // FITUR POIN: UI tukar poin pelanggan (tunai)
              if (_selectedCustomer != null && _selectedCustomer!.points > 0) ...[
                Consumer(
                  builder: (_, ref, __) {
                    final cart = ref.watch(kasirProvider);
                    final maxRedeem = _selectedCustomer!.points;
                    final currentRedeem = cart.redeemPoints;
                    return Container(
                      margin: const EdgeInsets.only(top: 8, bottom: 4),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: AppColors.warning.withOpacity(0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            const Icon(Icons.stars_rounded,
                                color: AppColors.warning, size: 18),
                            const SizedBox(width: 6),
                            Text(
                              'Tukar Poin ($maxRedeem tersedia)',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: AppColors.warning,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '1 poin = Rp 100',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade500),
                            ),
                          ]),
                          const SizedBox(height: 10),
                          Row(children: [
                            GestureDetector(
                              onTap: currentRedeem > 0
                                  ? () => ref
                                      .read(kasirProvider.notifier)
                                      .setRedeemPoints(currentRedeem - 1)
                                  : null,
                              child: Container(
                                width: 32, height: 32,
                                decoration: BoxDecoration(
                                  color: currentRedeem > 0
                                      ? AppColors.warning.withOpacity(0.15)
                                      : Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(Icons.remove,
                                    size: 16,
                                    color: currentRedeem > 0
                                        ? AppColors.warning
                                        : Colors.grey.shade400),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                children: [
                                  Text(
                                    '$currentRedeem poin',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16,
                                      color: AppColors.warning,
                                    ),
                                  ),
                                  Text(
                                    '= Rp ${(currentRedeem * 100).toString().replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (m) => "\${m[1]}.")}',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade500),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: currentRedeem < maxRedeem
                                  ? () => ref
                                      .read(kasirProvider.notifier)
                                      .setRedeemPoints(currentRedeem + 1)
                                  : null,
                              child: Container(
                                width: 32, height: 32,
                                decoration: BoxDecoration(
                                  color: currentRedeem < maxRedeem
                                      ? AppColors.warning.withOpacity(0.15)
                                      : Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(Icons.add,
                                    size: 16,
                                    color: currentRedeem < maxRedeem
                                        ? AppColors.warning
                                        : Colors.grey.shade400),
                              ),
                            ),
                          ]),
                          Slider(
                            value: currentRedeem.toDouble(),
                            min: 0,
                            max: maxRedeem.toDouble(),
                            divisions: maxRedeem > 0 ? maxRedeem : 1,
                            activeColor: AppColors.warning,
                            onChanged: (v) => ref
                                .read(kasirProvider.notifier)
                                .setRedeemPoints(v.round()),
                          ),
                          if (currentRedeem > 0)
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: () => ref
                                    .read(kasirProvider.notifier)
                                    .setRedeemPoints(0),
                                child: const Text('Reset Poin',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: AppColors.danger)),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ],
              const SizedBox(height: 16),
            ] else ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.info.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(children: [
                  Icon(Icons.info_outline,
                    color: AppColors.info, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _method == 'hutang'
                          ? 'Transaksi akan dicatat sebagai hutang'
                          : 'Pastikan pembayaran sudah diterima sebelum konfirmasi',
                      style: TextStyle(
                        color: AppColors.info,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ]),
              ),
              // ── Customer picker — tersedia untuk semua metode ─────────────
              const SizedBox(height: 12),
              GestureDetector(
                onTap: _pickCustomer,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: _selectedCustomer != null
                          ? AppColors.primary
                          : (_method == 'hutang'
                              ? AppColors.warning
                              : Colors.grey.shade300)),
                    borderRadius: BorderRadius.circular(12),
                    color: _selectedCustomer != null
                        ? AppColors.primaryLight
                        : null,
                  ),
                  child: Row(children: [
                    Icon(
                      _selectedCustomer != null
                          ? Icons.person
                          : Icons.person_add_alt_outlined,
                      color: _selectedCustomer != null
                          ? AppColors.primary
                          : (_method == 'hutang'
                              ? AppColors.warning
                              : Colors.grey.shade500),
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _selectedCustomer != null
                                ? _selectedCustomer!.name
                                : _method == 'hutang'
                                    ? 'Pilih Pelanggan (wajib)'
                                    : 'Pilih Pelanggan (opsional)',
                            style: TextStyle(
                              fontWeight: _selectedCustomer != null
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                              color: _selectedCustomer != null
                                  ? AppColors.primary
                                  : (_method == 'hutang'
                                      ? AppColors.warning
                                      : Colors.grey.shade500),
                              fontSize: 13,
                            ),
                          ),
                          if (_selectedCustomer != null) ...[
                            const SizedBox(height: 2),
                            Builder(builder: (ctx) {
                              final cart = ref.read(kasirProvider);
                              final pts = (cart.total / 10000).floor();
                              return Text(
                                '+$pts poin • Total poin: ${_selectedCustomer!.points + pts}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.warning,
                                ),
                              );
                            }),
                          ],
                        ],
                      ),
                    ),
                    if (_selectedCustomer != null)
                      GestureDetector(
                        onTap: () {
                          // BUG-04 FIX: reset poin saat pelanggan dihapus
                          ref.read(kasirProvider.notifier).setRedeemPoints(0);
                          setState(() => _selectedCustomer = null);
                        },
                        child: const Icon(Icons.close,
                          color: AppColors.danger, size: 18),
                      )
                    else
                      Icon(Icons.chevron_right,
                        color: Colors.grey.shade400, size: 18),
                  ]),
                ),
              ),
              if (_method == 'hutang') ...[
              ],
              // FITUR POIN: UI tukar poin pelanggan
              if (_selectedCustomer != null && _selectedCustomer!.points > 0) ...[
                Consumer(
                  builder: (_, ref, __) {
                    final cart = ref.watch(kasirProvider);
                    final maxRedeem = _selectedCustomer!.points;
                    final currentRedeem = cart.redeemPoints;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.warning.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: AppColors.warning.withOpacity(0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            const Icon(Icons.stars_rounded,
                                color: AppColors.warning, size: 18),
                            const SizedBox(width: 6),
                            Text(
                              'Tukar Poin ($maxRedeem tersedia)',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: AppColors.warning,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '1 poin = Rp 100',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade500),
                            ),
                          ]),
                          const SizedBox(height: 10),
                          Row(children: [
                            GestureDetector(
                              onTap: currentRedeem > 0
                                  ? () => ref
                                      .read(kasirProvider.notifier)
                                      .setRedeemPoints(currentRedeem - 1)
                                  : null,
                              child: Container(
                                width: 32, height: 32,
                                decoration: BoxDecoration(
                                  color: currentRedeem > 0
                                      ? AppColors.warning.withOpacity(0.15)
                                      : Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(Icons.remove,
                                    size: 16,
                                    color: currentRedeem > 0
                                        ? AppColors.warning
                                        : Colors.grey.shade400),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                children: [
                                  Text(
                                    '$currentRedeem poin',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16,
                                      color: AppColors.warning,
                                    ),
                                  ),
                                  Text(
                                    '= Rp ${(currentRedeem * 100).toString().replaceAllMapped(RegExp(r"(\d{1,3})(?=(\d{3})+(?!\d))"), (m) => "\${m[1]}.")}',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: Colors.grey.shade500),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: currentRedeem < maxRedeem
                                  ? () => ref
                                      .read(kasirProvider.notifier)
                                      .setRedeemPoints(currentRedeem + 1)
                                  : null,
                              child: Container(
                                width: 32, height: 32,
                                decoration: BoxDecoration(
                                  color: currentRedeem < maxRedeem
                                      ? AppColors.warning.withOpacity(0.15)
                                      : Colors.grey.shade100,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(Icons.add,
                                    size: 16,
                                    color: currentRedeem < maxRedeem
                                        ? AppColors.warning
                                        : Colors.grey.shade400),
                              ),
                            ),
                          ]),
                          Slider(
                            value: currentRedeem.toDouble(),
                            min: 0,
                            max: maxRedeem.toDouble(),
                            divisions: maxRedeem > 0 ? maxRedeem : 1,
                            activeColor: AppColors.warning,
                            onChanged: (v) => ref
                                .read(kasirProvider.notifier)
                                .setRedeemPoints(v.round()),
                          ),
                          if (currentRedeem > 0)
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: () => ref
                                    .read(kasirProvider.notifier)
                                    .setRedeemPoints(0),
                                child: const Text('Reset Poin',
                                    style: TextStyle(
                                        fontSize: 11,
                                        color: AppColors.danger)),
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ],
              const SizedBox(height: 16),
            ],


            TextField(
              controller: _notesCtrl,
              decoration: const InputDecoration(
                labelText: 'Catatan (opsional)',
                prefixIcon: Icon(Icons.note_alt_outlined),
                isDense: true,
              ),
              maxLines: 2,
            ),
            const SizedBox(height: 16),

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: _loading
                    ? const SizedBox(
                        width: 16, height: 16,
                        child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.check_circle_outline, size: 20),
                label: Text(_loading
                    ? 'Memproses...'
                    : 'Konfirmasi Pembayaran'),
                onPressed: (_loading || !canPay) ? null : _process,
                style: ElevatedButton.styleFrom(
                  backgroundColor: canPay
                      ? AppColors.success
                      : Colors.grey.shade300,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildMethodChip(String value, IconData icon, String label) {
    final isSelected = _method == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _method = value),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primary : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected
                  ? AppColors.primary
                  : Colors.grey.shade300,
            ),
          ),
          child: Column(
            children: [
              Icon(icon,
                size: 18,
                color: isSelected ? Colors.white : Colors.grey.shade600),
              const SizedBox(height: 3),
              Text(label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white : Colors.grey.shade600,
                )),
            ],
          ),
        ),
      ),
    );
  }

  List<double> _quickAmounts(double total) {
    final base = [10000.0, 20000.0, 50000.0, 100000.0, 200000.0, 500000.0];
    final result = <double>[total];
    for (final v in base) {
      if (v >= total) result.add(v);
      if (result.length >= 4) break;
    }
    return result.toSet().take(4).toList()..sort();
  }

  Future<void> _pickCustomer() async {
    final db = ref.read(databaseProvider);
    List<Customer> allCustomers = await db.customersDao.getAllCustomers();

    if (!context.mounted) return;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        String query = '';
        return StatefulBuilder(
          builder: (ctx, setLocalState) {
            final filtered = query.isEmpty
                ? allCustomers
                : allCustomers
                    .where((c) =>
                        c.name.toLowerCase().contains(query.toLowerCase()))
                    .toList();
            return SizedBox(
              height: MediaQuery.of(ctx).size.height * 0.75,
              child: Column(children: [
                const SizedBox(height: 12),
                Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2)),
                ),
                const SizedBox(height: 12),
                const Text('Pilih Pelanggan',
                  style: TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: TextField(
                    autofocus: true,
                    onChanged: (v) => setLocalState(() => query = v),
                    decoration: InputDecoration(
                      hintText: 'Cari nama pelanggan...',
                      prefixIcon: const Icon(Icons.search, size: 18),
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: AppColors.primary),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: AppColors.primary),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: AppColors.primary, width: 2),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.person_add_outlined, size: 18),
                      label: const Text(
                        'Tambah pelanggan',
                        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      onPressed: () async {
                        // Tutup sheet pilih pelanggan dulu
                        Navigator.pop(ctx);
                        // Buka form tambah pelanggan
                        await _showAddCustomerForm(db);
                      },
                    ),
                  ),
                ),
                Expanded(
                  child: filtered.isEmpty
                      ? Center(
                          child: Text('Pelanggan tidak ditemukan',
                            style: TextStyle(color: Colors.grey.shade500)))
                      : ListView.builder(
                          itemCount: filtered.length,
                          itemBuilder: (_, i) {
                            final c = filtered[i];
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: AppColors.primaryLight,
                                child: Text(
                                  c.name[0].toUpperCase(),
                                  style: const TextStyle(
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.w700),
                                ),
                              ),
                              title: Text(c.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600)),
                              subtitle: c.phone != null
                                  ? Text(c.phone!,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade500))
                                  : null,
                              onTap: () {
                                setState(() => _selectedCustomer = c);
                                Navigator.pop(ctx);
                              },
                            );
                          },
                        ),
                ),
              ]),
            );
          },
        );
      },
    );
  }

  Future<void> _showAddCustomerForm(AppDatabase db) async {
    if (!context.mounted) return;

    final nameCtrl    = TextEditingController();
    final phoneCtrl   = TextEditingController();
    final addressCtrl = TextEditingController();
    bool loading = false;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setLocalState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
                top: 20, left: 20, right: 20,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Handle
                    Center(
                      child: Container(
                        width: 40, height: 4,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2)),
                      ),
                    ),
                    const Text(
                      'Tambah Pelanggan',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Isi data pelanggan baru',
                      style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                    const SizedBox(height: 20),

                    // Nama
                    TextField(
                      controller: nameCtrl,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(
                        labelText: 'Nama Pelanggan *',
                        prefixIcon: Icon(Icons.person_outline),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // No HP
                    TextField(
                      controller: phoneCtrl,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'Nomor HP',
                        prefixIcon: Icon(Icons.phone_outlined),
                        prefixText: '+62 ',
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Alamat
                    TextField(
                      controller: addressCtrl,
                      textCapitalization: TextCapitalization.sentences,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Alamat',
                        prefixIcon: Icon(Icons.location_on_outlined),
                        alignLabelWithHint: true,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Tombol simpan
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: loading
                            ? const SizedBox(
                                width: 16, height: 16,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2))
                            : const Icon(Icons.save_outlined, size: 18),
                        label: Text(loading ? 'Menyimpan...' : 'Tambah Pelanggan'),
                        onPressed: loading
                            ? null
                            : () async {
                                if (nameCtrl.text.trim().isEmpty) {
                                  ScaffoldMessenger.of(ctx).showSnackBar(
                                    const SnackBar(
                                      content: Text('Nama pelanggan wajib diisi'),
                                      backgroundColor: AppColors.danger,
                                    ),
                                  );
                                  return;
                                }
                                setLocalState(() => loading = true);
                                try {
                                  final newId = await db.customersDao.insertCustomer(
                                    CustomersCompanion.insert(
                                      name: nameCtrl.text.trim(),
                                      phone: Value(phoneCtrl.text.isEmpty
                                          ? null
                                          : phoneCtrl.text.trim()),
                                      address: Value(addressCtrl.text.isEmpty
                                          ? null
                                          : addressCtrl.text.trim()),
                                    ),
                                  );
                                  // Ambil customer yang baru saja ditambahkan
                                  final allCustomers =
                                      await db.customersDao.getAllCustomers();
                                  final newCustomer = allCustomers
                                      .where((c) => c.id == newId)
                                      .firstOrNull;
                                  if (ctx.mounted) {
                                    Navigator.pop(ctx);
                                  }
                                  if (newCustomer != null) {
                                    WidgetsBinding.instance.addPostFrameCallback((_) {
                                      if (mounted) {
                                        setState(() => _selectedCustomer = newCustomer);
                                      }
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              'Pelanggan "${newCustomer.name}" berhasil ditambahkan dan dipilih'),
                                            backgroundColor: AppColors.success,
                                          ),
                                        );
                                      }
                                    });
                                  }
                                } catch (e) {
                                  setLocalState(() => loading = false);
                                  if (ctx.mounted) {
                                    ScaffoldMessenger.of(ctx).showSnackBar(
                                      SnackBar(
                                        content: Text('Gagal menyimpan: $e'),
                                        backgroundColor: AppColors.danger,
                                      ),
                                    );
                                  }
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    // Tunggu animasi penutupan bottom sheet selesai sebelum dispose controller,
    // agar TextField yang masih dalam proses unmount tidak kehilangan listener
    // controller secara tiba-tiba (penyebab error '_dependents.isEmpty').
    await Future.delayed(const Duration(milliseconds: 300));
    nameCtrl.dispose();
    phoneCtrl.dispose();
    addressCtrl.dispose();
  }

  Future<void> _process() async {
    final cart = ref.read(kasirProvider);

    // BUG-03 FIX: guard total <= 0 (bisa terjadi jika diskon+poin melebihi subtotal)
    if (cart.total <= 0 && cart.items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Keranjang kosong, tidak bisa memproses transaksi.'),
          backgroundColor: AppColors.danger));
      return;
    }

    if (_method == 'tunai') {
      final paid = double.tryParse(_amountCtrl.text) ?? 0;
      if (paid < cart.total) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Uang tidak cukup!'),
            backgroundColor: AppColors.danger));
        return;
      }
    }

    // Validasi pelanggan wajib untuk hutang
    if (_method == 'hutang' && _selectedCustomer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pilih pelanggan terlebih dahulu untuk hutang!'),
          backgroundColor: AppColors.warning));
      return;
    }

    setState(() => _loading = true);
    try {
      final db = ref.read(databaseProvider);
      final invoiceNumber =
          await db.transactionsDao.generateInvoiceNumber();
      final amountPaid = _method == 'tunai'
          ? (double.tryParse(_amountCtrl.text) ?? cart.total)
          : _method == 'hutang'
              ? 0.0
              : cart.total;

      final tx = TransactionsCompanion.insert(
        invoiceNumber: invoiceNumber,
        subtotal: Value(cart.subtotal),
        discountAmount: Value(cart.discountTotal),
        taxAmount: Value(cart.taxAmount),
        total: Value(cart.total),
        amountPaid: Value(amountPaid),
        change: Value(amountPaid - cart.total),
        paymentMethod: Value(_method),
        notes: Value(_notesCtrl.text.isEmpty ? null : _notesCtrl.text),
      );

      final items = cart.items.map((i) =>
        TransactionItemsCompanion.insert(
          transactionId: 0,
          productId: i.product.id,
          productName: i.product.name,
          price: i.product.sellPrice,
          quantity: i.quantity,
          discount: Value(i.discount),
          subtotal: i.subtotal,
        )).toList();

      final txId = await db.transactionsDao.insertTransaction(
        tx, items,
        customerId: _selectedCustomer?.id,
        kasirId:   ref.read(authProvider)?.id,
        kasirName: ref.read(authProvider)?.name,
      );

      // ── Kurangi poin yang diredeem ─────────────────────────────────────────
      if (cart.redeemPoints > 0 && _selectedCustomer != null) {
        final customer = _selectedCustomer!;
        final newPoints = (customer.points - cart.redeemPoints).clamp(0, customer.points);
        await db.customersDao.updateCustomer(
          CustomersCompanion(
            id: Value(customer.id),
            points: Value(newPoints),
          ),
        );
      }

      // ── Insert ke tabel Debts jika metode hutang ──────────────────────────
      if (_method == 'hutang' && _selectedCustomer != null) {
        await db.debtsDao.insertDebt(
          DebtsCompanion.insert(
            customerId: _selectedCustomer!.id,
            transactionId: Value(txId),
            amount: cart.total,
            paidAmount: const Value(0),
            status: const Value('unpaid'),
            notes: Value(_notesCtrl.text.isEmpty ? null : _notesCtrl.text),
          ),
        );
      }

      ref.read(kasirProvider.notifier).clear();

      // FIX: Invalidate dashboardStatsProvider agar kartu ringkasan di
      // Dashboard langsung refresh setelah transaksi selesai.
      // StreamProvider sudah reaktif via watchTodayTransactions, tapi
      // invalidate ini memastikan data kemarin juga ikut diperbarui.
      ref.invalidate(dashboardStatsProvider);

      if (context.mounted) {
        // ── BUGFIX: Simpan context dan data SEBELUM Navigator.pop ─────────
        // Context dari _PaymentSheet akan detached setelah pop, sehingga
        // showDialog yang dipanggil sesudah pop tidak akan muncul.
        // Solusi: ambil navigator dari root context terlebih dahulu,
        // lalu pop sheet, lalu tampilkan dialog menggunakan navigator tersebut.
        final kasirName = ref.read(authProvider)?.name;
        final customerName = _selectedCustomer?.name;
        final nav = Navigator.of(context);
        nav.pop(); // Tutup PaymentSheet

        // Tunggu frame berikutnya agar animasi pop selesai,
        // baru tampilkan dialog sukses di atas halaman Kasir.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (nav.context.mounted) {
            _showSuccessDialog(nav.context, invoiceNumber, cart, amountPaid,
                kasirName, customerName);
          }
        });
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppColors.danger));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showSuccessDialog(
    BuildContext context,
    String invoiceNumber,
    KasirState cart,
    double amountPaid,
    String? kasirName,
    String? customerName,
  ) {
    final change = amountPaid - cart.total;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => ProviderScope(
        parent: ProviderScope.containerOf(context),
        child: _SuccessDialog(
          invoiceNumber: invoiceNumber,
          cart: cart,
          amountPaid: amountPaid,
          change: change,
          paymentMethod: _method,
          kasirName: kasirName,
          customerName: customerName,
        ),
      ),
    );
  }
}

// ─── Success Dialog dengan opsi cetak ────────────────────────────────────────

class _SuccessDialog extends ConsumerStatefulWidget {
  final String invoiceNumber;
  final KasirState cart;
  final double amountPaid;
  final double change;
  final String paymentMethod;
  final String? kasirName;
  final String? customerName;

  const _SuccessDialog({
    required this.invoiceNumber,
    required this.cart,
    required this.amountPaid,
    required this.change,
    required this.paymentMethod,
    this.kasirName,
    this.customerName,
  });

  @override
  ConsumerState<_SuccessDialog> createState() => _SuccessDialogState();
}

class _SuccessDialogState extends ConsumerState<_SuccessDialog> {
  bool _printing = false;
  bool _savingPdf = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              color: AppColors.success,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_rounded,
              color: Colors.white, size: 36),
          ),
          const SizedBox(height: 16),
          const Text('Transaksi Berhasil!',
            style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Text(widget.invoiceNumber,
            style: TextStyle(
              color: Colors.grey.shade500, fontSize: 13)),
          const SizedBox(height: 16),
          _ReceiptRow('Total', CurrencyFormatter.format(widget.cart.total)),
          _ReceiptRow('Bayar', CurrencyFormatter.format(widget.amountPaid)),
          if (widget.change > 0)
            _ReceiptRow('Kembalian', CurrencyFormatter.format(widget.change),
              highlight: true),
          const SizedBox(height: 20),

          // Tombol cetak Bluetooth
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: _printing
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.print_outlined, size: 18),
              label: Text(_printing ? 'Mencetak...' : 'Cetak Struk (Bluetooth)'),
              onPressed: _printing ? null : _cetakBluetooth,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12)),
            ),
          ),
          const SizedBox(height: 8),

          // Tombol simpan / share PDF
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: _savingPdf
                  ? const SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.picture_as_pdf_outlined, size: 18),
              label: Text(_savingPdf ? 'Membuat PDF...' : 'Simpan / Share PDF'),
              onPressed: _savingPdf ? null : _sharePdf,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12)),
            ),
          ),
          const SizedBox(height: 8),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.check, size: 18),
              label: const Text('Selesai'),
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(vertical: 12)),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Cetak Bluetooth Thermal ──────────────────────────────────────────────

  Future<void> _cetakBluetooth() async {
    setState(() => _printing = true);
    try {
      // Cek apakah Bluetooth tersedia
      final bool connected = await PrintBluetoothThermal.connectionStatus;
      if (!connected) {
        // Tampilkan dialog pilih printer
        if (context.mounted) {
          await _showBluetoothPrinterDialog();
        }
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

  Future<void> _showBluetoothPrinterDialog() async {
    final List<dynamic> devices =
        await PrintBluetoothThermal.pairedBluetooths;

    if (!context.mounted) return;

    if (devices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
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
                  style: TextStyle(
                    fontSize: 12, color: Colors.grey.shade500)),
                onTap: () async {
                  Navigator.pop(context);
                  final bool result = await PrintBluetoothThermal.connect(
                    macPrinterAddress: d.macAdress ?? '');
                  if (result) {
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

  // ── Helper load logo (sama dengan settings_screen) ─────────────────────────
  // BUG-13 FIX: _loadLogoImage sekarang mengembalikan gambar WARNA PENUH.
  // Dipakai untuk PDF yang mendukung warna — grayscale tidak diperlukan di sini.
  Future<img.Image?> _loadLogoImage(int maxWidth) async {
    try {
      final store = ref.read(storeSettingsProvider);
      img.Image? original;

      // Pakai logo custom jika ada
      if (store.logoPath.isNotEmpty && File(store.logoPath).existsSync()) {
        final bytes = await File(store.logoPath).readAsBytes();
        original = img.decodeImage(bytes);
      } else {
        // Fallback ke logo header dari assets/logo/header.png
        final ByteData data =
            await rootBundle.load('assets/logo/header.png');
        final Uint8List bytes = data.buffer.asUint8List();
        original = img.decodeImage(bytes);
      }

      if (original == null) return null;
      original = img.trim(original, mode: img.TrimMode.transparent);
      if (original.width > maxWidth) {
        original = img.copyResize(original, width: maxWidth);
      }
      return original; // warna penuh untuk PDF
    } catch (_) {
      return null;
    }
  }

  // BUG-13 FIX: Versi grayscale khusus untuk printer thermal Bluetooth.
  // Printer ESC/POS hanya mendukung bitmap monokrom — gambar berwarna harus
  // dikonversi ke grayscale terlebih dahulu.
  Future<img.Image?> _loadLogoForBluetooth(int maxWidth) async {
    final logo = await _loadLogoImage(maxWidth);
    if (logo == null) return null;
    return img.grayscale(logo);
  }

  // Footer logo PERMANEN KasirKu Pro — selalu dari assets/logo/footer.png,
  // tidak mengikuti logo custom toko, tidak memakai app_icon.png.
  Future<img.Image?> _loadFooterAppIcon({int maxWidth = 400}) async {
    try {
      final ByteData data =
          await rootBundle.load('assets/logo/footer.png');
      final Uint8List bytes = data.buffer.asUint8List();
      var original = img.decodeImage(bytes);
      if (original == null) return null;
      original = img.trim(original, mode: img.TrimMode.transparent);
      if (original.width > maxWidth) {
        original = img.copyResize(original, width: maxWidth);
      }
      // Warna penuh untuk PDF — grayscale TIDAK dipakai di sini
      return original;
    } catch (_) {
      return null;
    }
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

    final profile = await CapabilityProfile.load();
    final generator = Generator(paperSize, profile);
    var bytes = <int>[];

    final now = DateTime.now();
    final dateStr = DateFormat('dd/MM/yyyy HH:mm').format(now);

    // ── Logo ────────────────────────────────────────────────────────────────
    if (settings.showLogo) {
      // BUG-13 FIX: pakai versi grayscale khusus Bluetooth (ESC/POS hanya bitmap monokrom)
      final logoImg = await _loadLogoForBluetooth(logoMaxWidth);
      if (logoImg != null) {
        bytes += generator.image(logoImg);
        bytes += generator.feed(1);
      }
    }

    // ── Header toko ─────────────────────────────────────────────────────────
    bytes += generator.text(storeName,
      styles: const PosStyles(
        align: PosAlign.center,
        bold: true,
        height: PosTextSize.size2,
        width: PosTextSize.size2,
      ));
    if (storeAddress.isNotEmpty) {
      bytes += generator.text(storeAddress,
        styles: const PosStyles(align: PosAlign.center));
    }
    if (storePhone.isNotEmpty) {
      bytes += generator.text('Telp: $storePhone',
        styles: const PosStyles(align: PosAlign.center));
    }
    bytes += generator.hr();
    bytes += generator.text('No: ${widget.invoiceNumber}',
      styles: const PosStyles(align: PosAlign.center));
    bytes += generator.text(dateStr,
      styles: const PosStyles(align: PosAlign.center));
    if (widget.kasirName != null && widget.kasirName!.isNotEmpty) {
      bytes += generator.text('Kasir: ${widget.kasirName}',
        styles: const PosStyles(align: PosAlign.center));
    }
    bytes += generator.hr();

    // ── Items ────────────────────────────────────────────────────────────────
    for (final item in widget.cart.items) {
      bytes += generator.text(item.product.name,
        styles: const PosStyles(bold: true));
      bytes += generator.row([
        PosColumn(
          text: '  ${item.quantity} x ${CurrencyFormatter.format(item.product.sellPrice)}',
          width: 8,
          styles: const PosStyles(align: PosAlign.left)),
        PosColumn(
          text: CurrencyFormatter.format(item.subtotal),
          width: 4,
          styles: const PosStyles(align: PosAlign.right)),
      ]);
    }
    bytes += generator.hr();

    // ── Summary ──────────────────────────────────────────────────────────────
    if (widget.cart.discountTotal > 0) {
      bytes += generator.row([
        PosColumn(text: 'Diskon', width: 6,
          styles: const PosStyles(align: PosAlign.left)),
        PosColumn(
          text: '- ${CurrencyFormatter.format(widget.cart.discountTotal)}',
          width: 6,
          styles: const PosStyles(align: PosAlign.right)),
      ]);
    }
    if (widget.cart.taxAmount > 0) {
      bytes += generator.row([
        PosColumn(
          text: 'Pajak (${widget.cart.taxPercent.toStringAsFixed(0)}%)',
          width: 6,
          styles: const PosStyles(align: PosAlign.left)),
        PosColumn(
          text: '+ ${CurrencyFormatter.format(widget.cart.taxAmount)}',
          width: 6,
          styles: const PosStyles(align: PosAlign.right)),
      ]);
    }
    bytes += generator.row([
      PosColumn(text: 'TOTAL', width: 6,
        styles: const PosStyles(bold: true, align: PosAlign.left)),
      PosColumn(
        text: CurrencyFormatter.format(widget.cart.total),
        width: 6,
        styles: const PosStyles(bold: true, align: PosAlign.right)),
    ]);
    bytes += generator.row([
      PosColumn(text: 'Bayar', width: 6,
        styles: const PosStyles(align: PosAlign.left)),
      PosColumn(
        text: CurrencyFormatter.format(widget.amountPaid),
        width: 6,
        styles: const PosStyles(align: PosAlign.right)),
    ]);
    if (widget.change > 0) {
      bytes += generator.row([
        PosColumn(text: 'Kembali', width: 6,
          styles: const PosStyles(align: PosAlign.left)),
        PosColumn(
          text: CurrencyFormatter.format(widget.change),
          width: 6,
          styles: const PosStyles(align: PosAlign.right)),
      ]);
    }
    bytes += generator.hr();

    // ── Footer dari pengaturan ───────────────────────────────────────────────
    if (storeNote.isNotEmpty) {
      bytes += generator.text(storeNote,
        styles: const PosStyles(align: PosAlign.center, bold: true));
    }
    bytes += generator.feed(3);
    bytes += generator.cut();

    await PrintBluetoothThermal.writeBytes(bytes);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Struk berhasil dicetak!'),
          backgroundColor: AppColors.success));
    }
  }

  // ─── Share PDF ─────────────────────────────────────────────────────────────

  Future<void> _sharePdf() async {
    setState(() => _savingPdf = true);
    try {
      final settings    = ref.read(storeSettingsProvider);
      final storeName   = settings.storeName;
      final storeAddress = settings.storeAddress ?? '';

      final pdfBytes = await _buildPdf(storeName, storeAddress);
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/${widget.invoiceNumber}.pdf');
      await file.writeAsBytes(pdfBytes);
      await Share.shareXFiles([XFile(file.path)], text: 'Struk ${widget.invoiceNumber}');
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal buat PDF: $e'),
            backgroundColor: AppColors.danger));
      }
    } finally {
      if (mounted) setState(() => _savingPdf = false);
    }
  }

  // ── PERUBAHAN: _buildPdf sekarang hanya menyiapkan data & memanggil
  // ReceiptPdfBuilder (lib/core/utils/receipt_pdf_builder.dart) untuk urusan
  // layout/tampilan. Semua angka (subtotal/diskon/pajak/total/kembali) tetap
  // berasal dari widget.cart / widget.amountPaid / widget.change apa adanya
  // — TIDAK ada perhitungan ulang di sini maupun di builder.
  Future<Uint8List> _buildPdf(String storeName, String storeAddress) async {
    await initializeDateFormatting('id', null);
    final settings   = ref.read(storeSettingsProvider);
    final storePhone = settings.storePhone ?? '';
    final storeNote  = settings.storeNote ?? '';
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

    final items = widget.cart.items
        .map((item) => ReceiptPdfItem(
              name: item.product.name,
              quantity: item.quantity,
              price: item.product.sellPrice,
              subtotal: item.subtotal,
            ))
        .toList();

    return ReceiptPdfBuilder.build(
      storeName: storeName,
      storeAddress: storeAddress,
      storePhone: storePhone,
      storeNote: storeNote,
      invoiceNumber: widget.invoiceNumber,
      date: DateTime.now(),
      paymentMethodLabel: _methodLabel(widget.paymentMethod),
      kasirName: widget.kasirName,
      customerName: widget.customerName,
      items: items,
      discount: widget.cart.discountTotal,
      discountPercent: (widget.cart.subtotal > 0 && widget.cart.discountTotal > 0)
          ? (widget.cart.discountTotal / widget.cart.subtotal * 100)
          : 0.0,
      tax: widget.cart.taxAmount,
      taxPercent: widget.cart.taxPercent,
      total: widget.cart.total,
      amountPaid: widget.amountPaid,
      change: widget.change,
      receiptSize: settings.receiptSize,
      logoImage: logoImage,
      footerLogoImage: footerLogoImage,
    );
  }

  String _methodLabel(String method) {
    switch (method) {
      case 'tunai':    return 'Tunai';
      case 'qris':     return 'QRIS';
      case 'transfer': return 'Transfer Bank';
      case 'hutang':   return 'Hutang';
      default:         return method;
    }
  }
}

// ─── Receipt Row ──────────────────────────────────────────────────────────────

class _ReceiptRow extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;
  const _ReceiptRow(this.label, this.value, {this.highlight = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade600)),
          Text(value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: highlight ? FontWeight.w800 : FontWeight.w600,
              color: highlight ? AppColors.success : null,
            )),
        ],
      ),
    );
  }
}

// ─── Empty Cart ───────────────────────────────────────────────────────────────

class _EmptyCart extends StatelessWidget {
  const _EmptyCart();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.shopping_cart_outlined,
              size: 48, color: AppColors.primary),
          ),
          const SizedBox(height: 20),
          const Text('Keranjang Kosong',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            )),
          const SizedBox(height: 8),
          Text('Cari produk di kotak pencarian di atas',
            style: TextStyle(
              color: Colors.grey.shade400, fontSize: 13)),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            icon: const Icon(Icons.search, size: 16),
            label: const Text('Cari Produk'),
            onPressed: () {},
          ),
        ],
      ),
    );
  }
}

// ─── Widget QRIS Display di Payment Sheet ────────────────────────────────────

class _QrisDisplay extends ConsumerWidget {
  final VoidCallback? onTap;
  const _QrisDisplay({this.onTap});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store   = ref.watch(storeSettingsProvider);
    final isDark  = Theme.of(context).brightness == Brightness.dark;
    final cardBg  = isDark ? AppColors.darkSurface : Colors.grey.shade50;
    final subColor= isDark ? const Color(0xFF94A3B8) : AppColors.textSecondary;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : Colors.grey.shade200),
      ),
      child: store.qrisImagePath.isNotEmpty &&
              File(store.qrisImagePath).existsSync()
          ? Column(children: [
              ClipRRect(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(13)),
                child: Image.file(
                  File(store.qrisImagePath),
                  width: double.infinity,
                  height: 220,
                  fit: BoxFit.contain,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.qr_code_scanner_rounded,
                        size: 16, color: subColor),
                    const SizedBox(width: 6),
                    Text('Minta customer scan QR di atas',
                        style: TextStyle(
                            fontSize: 12, color: subColor)),
                  ],
                ),
              ),
            ])
          : Padding(
              padding: const EdgeInsets.all(20),
              child: Column(children: [
                Icon(Icons.qr_code_2_rounded,
                    size: 48, color: Colors.grey.shade400),
                const SizedBox(height: 8),
                Text('Belum ada gambar QRIS',
                    style: TextStyle(
                        fontWeight: FontWeight.w600, color: subColor)),
                const SizedBox(height: 4),
                Text('Upload gambar QRIS di Menu → Metode Pembayaran',
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(fontSize: 12, color: subColor)),
              ]),
            ),
    );
  }
}

// ─── Widget Transfer Accounts Display di Payment Sheet ───────────────────────

class _TransferAccountsDisplay extends ConsumerWidget {
  const _TransferAccountsDisplay();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store    = ref.watch(storeSettingsProvider);
    final accounts = store.bankAccounts;
    final isDark   = Theme.of(context).brightness == Brightness.dark;
    final subColor = isDark ? const Color(0xFF94A3B8) : AppColors.textSecondary;

    if (accounts.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: isDark ? AppColors.darkBorder : Colors.grey.shade200),
        ),
        child: Column(children: [
          Icon(Icons.account_balance_outlined,
              size: 40, color: Colors.grey.shade400),
          const SizedBox(height: 8),
          Text('Belum ada rekening tersimpan',
              style: TextStyle(
                  fontWeight: FontWeight.w600, color: subColor)),
          const SizedBox(height: 4),
          Text('Tambah rekening di Menu → Metode Pembayaran',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: subColor)),
        ]),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Transfer ke rekening:',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: subColor)),
        const SizedBox(height: 8),
        ...accounts.map((acc) => Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurface : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: isDark
                        ? AppColors.darkBorder
                        : Colors.grey.shade200),
              ),
              child: Row(children: [
                Container(
                  width: 38, height: 38,
                  decoration: BoxDecoration(
                    color: AppColors.primaryLight,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.account_balance_rounded,
                      color: AppColors.primary, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(acc.bankName,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13)),
                      const SizedBox(height: 2),
                      Text(acc.accountNumber,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                              letterSpacing: 0.5)),
                      Text('a/n ${acc.accountHolder}',
                          style: TextStyle(
                              fontSize: 11, color: subColor)),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(
                        ClipboardData(text: acc.accountNumber));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                            'No. rekening ${acc.bankName} disalin'),
                        duration: const Duration(seconds: 2),
                        backgroundColor: AppColors.success,
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.copy_rounded,
                        size: 16, color: AppColors.primary),
                  ),
                ),
              ]),
            )),
      ],
    );
  }
}
