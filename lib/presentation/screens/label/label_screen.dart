import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency.dart';
import '../../../core/utils/bluetooth_permission.dart';
import '../../../core/utils/label_printer.dart';
import '../../../data/database/app_database.dart';
import '../../providers/products_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/database_provider.dart';

/// Menu "Cetak Label Harga" — ambil data nama+harga langsung dari Stok
/// Kasirku (satu sumber data yang sama dengan Kasir & Nota Manual), pilih
/// berapa lembar per produk, lalu cetak via printer Bluetooth thermal.
/// Menggantikan aplikasi Label Harga terpisah yang sebelumnya punya
/// database produk sendiri.
class LabelScreen extends ConsumerStatefulWidget {
  const LabelScreen({super.key});

  @override
  ConsumerState<LabelScreen> createState() => _LabelScreenState();
}

class _LabelScreenState extends ConsumerState<LabelScreen> {
  String _query = '';
  final Map<int, int> _qtyByProductId = {};
  bool _printing = false;

  int get _totalLabels => _qtyByProductId.values.fold(0, (s, q) => s + q);

  void _setQty(int productId, int qty) {
    setState(() {
      if (qty <= 0) {
        _qtyByProductId.remove(productId);
      } else {
        _qtyByProductId[productId] = qty;
      }
    });
  }

  Future<void> _onCetak(List<Product> allProducts) async {
    if (_qtyByProductId.isEmpty) return;

    final granted = await ensureBluetoothPermission();
    if (!mounted) return;
    if (!granted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Izin Bluetooth ditolak. Aktifkan lewat Pengaturan '
              'HP > Aplikasi > KasirKu Pro > Izin.'),
          backgroundColor: AppColors.danger));
      return;
    }

    final selected = allProducts.where((p) => _qtyByProductId.containsKey(p.id)).toList();
    final items = selected
        .map((p) => LabelItem(
              productName: p.name,
              unit: p.unit,
              price: p.sellPrice,
              quantity: _qtyByProductId[p.id]!,
            ))
        .toList();

    final settings = ref.read(storeSettingsProvider);
    final paperSize = settings.receiptSize == '80mm' ? PaperSize.mm80 : PaperSize.mm58;

    setState(() => _printing = true);
    try {
      final connected = await PrintBluetoothThermal.connectionStatus;
      if (!connected) {
        if (mounted) await _showPrinterDialog(items, paperSize);
      } else {
        await LabelPrinter.print(items: items, paperSize: paperSize);
        await _saveHistory(items);
        if (mounted) _afterPrintSuccess();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text('Gagal cetak: $e'), backgroundColor: AppColors.danger));
      }
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  Future<void> _showPrinterDialog(List<LabelItem> items, PaperSize paperSize) async {
    final devices = await PrintBluetoothThermal.pairedBluetooths;
    if (!mounted) return;
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
                    try {
                      await LabelPrinter.print(items: items, paperSize: paperSize);
                      await _saveHistory(items);
                      if (mounted) _afterPrintSuccess();
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text('Gagal cetak: $e'), backgroundColor: AppColors.danger));
                      }
                    }
                  } else if (mounted) {
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

  Future<void> _saveHistory(List<LabelItem> items) async {
    final db = ref.read(databaseProvider);
    for (final item in items) {
      await db.printLabelHistoriesDao.addEntry(
        productName: item.productName,
        unit: item.unit,
        price: item.price,
        quantity: item.quantity,
      );
    }
  }

  void _afterPrintSuccess() {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('$_totalLabels label berhasil dicetak!'),
        backgroundColor: AppColors.success));
    setState(() => _qtyByProductId.clear());
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final productsAsync = ref.watch(productsStreamProvider);

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.bg,
      appBar: AppBar(
        title: const Text('Cetak Label Harga',
            style: TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: const Icon(Icons.history_rounded),
            tooltip: 'Riwayat Cetak',
            onPressed: () => showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
              builder: (_) => ProviderScope(
                parent: ProviderScope.containerOf(context),
                child: const _LabelHistorySheet(),
              ),
            ),
          ),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Cari produk...',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              fillColor: isDark ? AppColors.darkCard : Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _query = v.toLowerCase()),
          ),
        ),
        Expanded(
          child: productsAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (products) {
              final filtered = _query.isEmpty
                  ? products
                  : products.where((p) => p.name.toLowerCase().contains(_query)).toList();
              if (filtered.isEmpty) {
                return const Center(
                  child: Text('Belum ada produk di Stok',
                      style: TextStyle(color: AppColors.textSecondary)),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 100),
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (_, i) {
                  final p = filtered[i];
                  final qty = _qtyByProductId[p.id] ?? 0;
                  return Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isDark ? AppColors.darkCard : Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                          color: qty > 0
                              ? AppColors.primary
                              : (isDark ? AppColors.darkBorder : AppColors.border),
                          width: qty > 0 ? 1.2 : 0.5),
                    ),
                    child: Row(children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p.name,
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 2),
                            Text('${CurrencyFormatter.format(p.sellPrice)} / ${p.unit}',
                                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                          ],
                        ),
                      ),
                      _QtyStepper(
                        qty: qty,
                        onChanged: (v) => _setQty(p.id, v),
                      ),
                    ]),
                  );
                },
              );
            },
          ),
        ),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: _printing
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.print_outlined),
              label: Text(_printing
                  ? 'Mencetak...'
                  : _totalLabels > 0
                      ? 'Cetak $_totalLabels Label'
                      : 'Pilih produk untuk dicetak'),
              onPressed: (_totalLabels > 0 && !_printing)
                  ? () => _onCetak(ref.read(productsStreamProvider).value ?? [])
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _QtyStepper extends StatelessWidget {
  final int qty;
  final ValueChanged<int> onChanged;
  const _QtyStepper({required this.qty, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      _StepBtn(icon: Icons.remove, onTap: qty > 0 ? () => onChanged(qty - 1) : null),
      SizedBox(
        width: 28,
        child: Text('$qty',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontWeight: FontWeight.w700,
                color: qty > 0 ? AppColors.primary : AppColors.textHint)),
      ),
      _StepBtn(icon: Icons.add, onTap: () => onChanged(qty + 1)),
    ]);
  }
}

class _StepBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _StepBtn({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: onTap != null ? AppColors.primary.withOpacity(0.1) : Colors.grey.withOpacity(0.08),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 16,
              color: onTap != null ? AppColors.primary : AppColors.textHint),
        ),
      ),
    );
  }
}

class _LabelHistorySheet extends ConsumerWidget {
  const _LabelHistorySheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final historyAsync = ref.watch(_labelHistoryProvider);

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (_, controller) => Column(children: [
        Container(
          margin: const EdgeInsets.symmetric(vertical: 12),
          width: 40, height: 4,
          decoration: BoxDecoration(
              color: isDark ? AppColors.darkBorder : Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2)),
        ),
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text('Riwayat Cetak Label',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
        ),
        const Divider(height: 1),
        Expanded(
          child: historyAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Error: $e')),
            data: (list) {
              if (list.isEmpty) {
                return const Center(
                    child: Text('Belum ada riwayat cetak',
                        style: TextStyle(color: AppColors.textSecondary)));
              }
              return ListView.builder(
                controller: controller,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: list.length,
                itemBuilder: (_, i) {
                  final h = list[i];
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.sell_outlined, color: AppColors.primary),
                    title: Text(h.productName,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    subtitle: Text(
                        '${CurrencyFormatter.format(h.price)} / ${h.unit} • ${_fmtDate(h.printedAt)}',
                        style: const TextStyle(fontSize: 11)),
                    trailing: Text('${h.quantity}x',
                        style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary)),
                  );
                },
              );
            },
          ),
        ),
      ]),
    );
  }

  String _fmtDate(DateTime dt) {
    const months = ['Jan','Feb','Mar','Apr','Mei','Jun','Jul','Ags','Sep','Okt','Nov','Des'];
    return '${dt.day} ${months[dt.month - 1]} ${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}';
  }
}

final _labelHistoryProvider = StreamProvider<List<PrintLabelHistory>>((ref) {
  return ref.watch(databaseProvider).printLabelHistoriesDao.watchHistory();
});
