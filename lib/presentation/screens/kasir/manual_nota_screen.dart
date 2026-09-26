import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency.dart';
import '../../../core/utils/manual_nota_printer.dart';
import '../../providers/manual_nota_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/database_provider.dart';
import '../../../data/database/app_database.dart';

/// Layar "Nota Manual" — nota tulis-tangan cepat, alternatif dari Kasir
/// Otomatis. Dibuka dari popup pilihan saat tab Kasir ditekan (lihat
/// kasir_screen.dart / _showKasirModeDialog).
class ManualNotaScreen extends ConsumerStatefulWidget {
  /// Kalau diisi, layar dibuka dalam mode EDIT nota yang sudah tersimpan
  /// (dari tombol Edit di Riwayat Transaksi) — kalau null, mode buat baru
  /// seperti biasa (dibuka dari popup mode Kasir).
  final ManualNota? editingNota;

  const ManualNotaScreen({super.key, this.editingNota});

  @override
  ConsumerState<ManualNotaScreen> createState() => _ManualNotaScreenState();
}

class _ManualNotaScreenState extends ConsumerState<ManualNotaScreen> {
  bool _saving = false;
  final _bayarController = TextEditingController();
  final Map<String, FocusNode> _nameFocusNodes = {};

  bool get _isEditing => widget.editingNota != null;

  @override
  void initState() {
    super.initState();
    final paid = widget.editingNota?.amountPaid;
    if (paid != null && paid > 0) {
      _bayarController.text = paid.toStringAsFixed(0);
    }
  }

  FocusNode _nameFocusFor(String id) =>
      _nameFocusNodes.putIfAbsent(id, () => FocusNode());

  @override
  void dispose() {
    _bayarController.dispose();
    for (final node in _nameFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  /// Dipanggil saat Enter ditekan di kolom Qty baris ke-[index]. Kalau ini
  /// baris terakhir, tambah baris baru lalu pindah fokus ke nama baris baru
  /// itu; kalau bukan, pindah fokus ke nama baris berikutnya. Sama seperti
  /// handleEnterQty di page.tsx Nota Tulis.
  void _handleRowSubmitted(int index) {
    final items = ref.read(manualNotaProvider(widget.editingNota)).items;
    if (index >= items.length - 1) {
      ref.read(manualNotaProvider(widget.editingNota).notifier).addRow();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final newItems = ref.read(manualNotaProvider(widget.editingNota)).items;
        if (newItems.isNotEmpty) {
          _nameFocusFor(newItems.last.id).requestFocus();
        }
      });
    } else {
      _nameFocusFor(items[index + 1].id).requestFocus();
    }
  }

  Future<void> _confirmClear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Hapus Nota?'),
        content: const Text('Semua item yang sudah diketik akan dihapus.'),
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
    if (ok == true) ref.read(manualNotaProvider(widget.editingNota).notifier).reset();
  }

  /// Simpan nota, lalu COBA cetak (bukan dicek dulu status koneksinya —
  /// mengikuti pola handlePrint() di page.tsx Nota Tulis: langsung coba,
  /// kalau gagal cukup tampilkan pesan, nota tetap tersimpan). Dibungkus
  /// timeout supaya kalau plugin printer macet, tidak nge-hang selamanya.
  Future<void> _saveAndPrint() async {
    final notifier = ref.read(manualNotaProvider(widget.editingNota).notifier);
    final bayar = double.tryParse(_bayarController.text.replaceAll(RegExp(r'[^0-9]'), ''));

    setState(() => _saving = true);
    try {
      final nota = await notifier.saveNota(amountPaid: bayar);
      if (!mounted) return;

      final items = decodeManualNotaItems(nota.itemsJson);
      final settings = ref.read(storeSettingsProvider);

      try {
        await ManualNotaPrinter.print(nota: nota, items: items, settings: settings)
            .timeout(const Duration(seconds: 6));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Nota tersimpan & dicetak'), backgroundColor: AppColors.success),
          );
        }
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Nota tersimpan. Gagal mencetak — cek koneksi printer.'),
              backgroundColor: AppColors.warning,
            ),
          );
        }
      }

      if (_isEditing) {
        if (mounted) Navigator.pop(context, true);
        return;
      }
      notifier.reset();
      _bayarController.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menyimpan: $e'), backgroundColor: AppColors.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(manualNotaProvider(widget.editingNota));
    final notifier = ref.read(manualNotaProvider(widget.editingNota).notifier);
    final bayar = double.tryParse(_bayarController.text.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    final kembalian = bayar - state.total;

    return Scaffold(
      appBar: AppBar(
        title: Text(
            _isEditing
                ? 'Edit Nota · ${widget.editingNota!.invoiceNumber}'
                : 'Nota Manual',
            style: const TextStyle(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: _confirmClear,
            tooltip: 'Hapus semua',
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextFormField(
              initialValue: state.customerName,
              decoration: InputDecoration(
                labelText: 'Nama Pelanggan (opsional)',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onChanged: notifier.setCustomerName,
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: state.items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final item = state.items[i];
                return _ManualNotaRow(
                  key: ValueKey(item.id),
                  item: item,
                  nameFocusNode: _nameFocusFor(item.id),
                  onChanged: (name, price, qty) =>
                      notifier.updateItem(item.id, name: name, price: price, qty: qty),
                  onRemove: () => notifier.removeItem(item.id),
                  onRowSubmitted: () => _handleRowSubmitted(i),
                );
              },
            ),
          ),
          TextButton.icon(
            onPressed: notifier.addRow,
            icon: const Icon(Icons.add, color: AppColors.primary),
            label: const Text('Tambah Baris', style: TextStyle(color: AppColors.primary)),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, -2))],
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('TOTAL', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                      Text(CurrencyFormatter.format(state.total),
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18, color: AppColors.primary)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _bayarController,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: 'Bayar Tunai (opsional)',
                      filled: true,
                      fillColor: AppColors.bg,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  if (bayar > 0) ...[
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Kembalian', style: TextStyle(color: AppColors.textSecondary)),
                        Text(
                          CurrencyFormatter.format(kembalian.clamp(0, double.infinity)),
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: kembalian < 0 ? AppColors.danger : AppColors.success,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: (_saving || state.validItems.isEmpty) ? null : _saveAndPrint,
                      icon: _saving
                          ? const SizedBox(
                              width: 18, height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.receipt_long_outlined),
                      label: Text(_saving
                          ? 'Menyimpan...'
                          : (_isEditing ? 'Simpan Perubahan' : 'Simpan & Cetak')),
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ManualNotaRow extends ConsumerStatefulWidget {
  final ManualNotaItem item;
  final FocusNode nameFocusNode;
  final void Function(String? name, double? price, int? qty) onChanged;
  final VoidCallback onRemove;
  final VoidCallback onRowSubmitted;

  const _ManualNotaRow({
    super.key,
    required this.item,
    required this.nameFocusNode,
    required this.onChanged,
    required this.onRemove,
    required this.onRowSubmitted,
  });

  @override
  ConsumerState<_ManualNotaRow> createState() => _ManualNotaRowState();
}

class _ManualNotaRowState extends ConsumerState<_ManualNotaRow> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _qtyCtrl;
  final FocusNode _priceFocus = FocusNode();
  final FocusNode _qtyFocus = FocusNode();

  Timer? _debounce;
  List<Product> _suggestions = [];
  bool _showSuggestions = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.item.name);
    _priceCtrl = TextEditingController(text: widget.item.price == 0 ? '' : widget.item.price.toStringAsFixed(0));
    _qtyCtrl = TextEditingController(text: widget.item.qty.toString());
    widget.nameFocusNode.addListener(_onNameFocusChange);
  }

  void _onNameFocusChange() {
    if (!widget.nameFocusNode.hasFocus && mounted) {
      // Kasih jeda dikit supaya tap di item saran sempat kena duluan
      // sebelum listnya ditutup oleh event kehilangan fokus ini.
      Future.delayed(const Duration(milliseconds: 150), () {
        if (mounted) setState(() => _showSuggestions = false);
      });
    }
  }

  /// Autocomplete nama+harga barang — cari dari produk yang sudah pernah
  /// tercatat (baik dari Kasir Otomatis maupun Nota Manual sebelumnya),
  /// sama seperti fitur "product suggestion" di Nota Tulis, supaya tidak
  /// perlu ketik ulang nama & harga barang yang sudah pernah dicatat.
  void _onNameChanged(String v) {
    widget.onChanged(v, null, null);
    _debounce?.cancel();
    final query = v.trim();
    if (query.length < 2) {
      setState(() { _suggestions = []; _showSuggestions = false; });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final db = ref.read(databaseProvider);
      final results = await db.productsDao.findSimilarByName(query);
      if (mounted && _nameCtrl.text.trim() == query) {
        setState(() {
          _suggestions = results.take(5).toList();
          _showSuggestions = _suggestions.isNotEmpty;
        });
      }
    });
  }

  void _selectSuggestion(Product p) {
    _nameCtrl.text = p.name;
    _priceCtrl.text = p.sellPrice.toStringAsFixed(0);
    widget.onChanged(p.name, p.sellPrice, null);
    setState(() { _showSuggestions = false; _suggestions = []; });
    FocusScope.of(context).requestFocus(_priceFocus);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.nameFocusNode.removeListener(_onNameFocusChange);
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    _qtyCtrl.dispose();
    _priceFocus.dispose();
    _qtyFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _nameCtrl,
                    focusNode: widget.nameFocusNode,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      hintText: 'Nama barang',
                      border: InputBorder.none,
                      isDense: true,
                    ),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                    onChanged: _onNameChanged,
                    onSubmitted: (_) => FocusScope.of(context).requestFocus(_priceFocus),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18, color: AppColors.textHint),
                  onPressed: widget.onRemove,
                ),
              ],
            ),
            if (_showSuggestions)
              Container(
                margin: const EdgeInsets.only(bottom: 6),
                decoration: BoxDecoration(
                  color: AppColors.bg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: _suggestions.map((p) => InkWell(
                    onTap: () => _selectSuggestion(p),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      child: Row(children: [
                        const Icon(Icons.history, size: 14, color: AppColors.textHint),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(p.name,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                              overflow: TextOverflow.ellipsis),
                        ),
                        Text(CurrencyFormatter.format(p.sellPrice),
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.primary)),
                      ]),
                    ),
                  )).toList(),
                ),
              ),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _priceCtrl,
                    focusNode: _priceFocus,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(hintText: 'Harga', isDense: true),
                    onChanged: (v) => widget.onChanged(null, double.tryParse(v) ?? 0, null),
                    onSubmitted: (_) => FocusScope.of(context).requestFocus(_qtyFocus),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 1,
                  child: TextField(
                    controller: _qtyCtrl,
                    focusNode: _qtyFocus,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(hintText: 'Qty', isDense: true),
                    onChanged: (v) => widget.onChanged(null, null, int.tryParse(v) ?? 1),
                    onSubmitted: (_) => widget.onRowSubmitted(),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 90,
                  child: Text(
                    CurrencyFormatter.format(widget.item.total),
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
