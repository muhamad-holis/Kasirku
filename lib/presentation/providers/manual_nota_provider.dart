import 'dart:convert';
import 'dart:math';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/database/app_database.dart';
import 'database_provider.dart';

/// Satu baris item nota manual — bebas ketik nama & harga, TIDAK terhubung
/// ke Products (beda dengan CartItem di kasir_provider.dart yang mengacu
/// ke Product asli + stok).
class ManualNotaItem {
  final String id;
  final String name;
  final double price;
  final int qty;
  final double? totalOverride;

  const ManualNotaItem({
    required this.id,
    this.name = '',
    this.price = 0,
    this.qty = 1,
    this.totalOverride,
  });

  double get total => totalOverride ?? (price * qty);

  ManualNotaItem copyWith({
    String? name,
    double? price,
    int? qty,
    double? totalOverride,
    bool clearOverride = false,
  }) =>
      ManualNotaItem(
        id: id,
        name: name ?? this.name,
        price: price ?? this.price,
        qty: qty ?? this.qty,
        totalOverride: clearOverride ? null : (totalOverride ?? this.totalOverride),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'price': price,
        'qty': qty,
        if (totalOverride != null) 'totalOverride': totalOverride,
      };

  factory ManualNotaItem.fromJson(Map<String, dynamic> j) => ManualNotaItem(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        price: (j['price'] as num?)?.toDouble() ?? 0,
        qty: (j['qty'] as num?)?.toInt() ?? 1,
        totalOverride: (j['totalOverride'] as num?)?.toDouble(),
      );
}

String _newItemId() =>
    '${DateTime.now().microsecondsSinceEpoch}_${Random().nextInt(99999)}';

ManualNotaItem _emptyRow() => ManualNotaItem(id: _newItemId());

class ManualNotaState {
  final List<ManualNotaItem> items;
  final String customerName;

  const ManualNotaState({
    this.items = const [],
    this.customerName = '',
  });

  double get total => items.fold(0.0, (s, i) => s + i.total);

  List<ManualNotaItem> get validItems => items
      .where((i) => i.name.trim().isNotEmpty && (i.price > 0 || i.qty > 0))
      .toList();

  ManualNotaState copyWith({
    List<ManualNotaItem>? items,
    String? customerName,
  }) =>
      ManualNotaState(
        items: items ?? this.items,
        customerName: customerName ?? this.customerName,
      );
}

class ManualNotaNotifier extends StateNotifier<ManualNotaState> {
  final AppDatabase db;

  /// Non-null kalau notifier ini sedang dipakai untuk MENGEDIT nota yang
  /// sudah tersimpan (dibuka dari Riwayat) — bukan membuat nota baru.
  /// invoiceNumber & createdAt asli tetap dipertahankan saat update.
  final int? editingId;
  final String? editingInvoiceNumber;

  ManualNotaNotifier(this.db, {ManualNota? editingNota})
      : editingId = editingNota?.id,
        editingInvoiceNumber = editingNota?.invoiceNumber,
        super(editingNota == null
            ? ManualNotaState(items: [_emptyRow()])
            : ManualNotaState(
                items: decodeManualNotaItems(editingNota.itemsJson),
                customerName: editingNota.customerName ?? '',
              ));

  void setCustomerName(String name) {
    state = state.copyWith(customerName: name);
  }

  void updateItem(String id, {String? name, double? price, int? qty}) {
    final items = state.items
        .map((i) => i.id == id
            ? i.copyWith(name: name, price: price, qty: qty, clearOverride: false)
            : i)
        .toList();
    state = state.copyWith(items: items);
  }

  void removeItem(String id) {
    final filtered = state.items.where((i) => i.id != id).toList();
    state = state.copyWith(items: filtered.isEmpty ? [_emptyRow()] : filtered);
  }

  void addRow() {
    state = state.copyWith(items: [...state.items, _emptyRow()]);
  }

  /// Tambah baris baru otomatis kalau baris terakhir sudah terisi —
  /// dipanggil saat user selesai mengisi baris (mis. onSubmitted harga).
  void ensureTrailingRow() {
    final last = state.items.isNotEmpty ? state.items.last : null;
    if (last != null && last.name.trim().isEmpty) return;
    addRow();
  }

  void reset() {
    state = ManualNotaState(items: [_emptyRow()]);
  }

  /// Simpan nota ke database. Melempar [Exception] kalau nota masih kosong.
  /// Kalau [editingId] terisi (mode edit dari Riwayat), nota yang sudah ada
  /// di-UPDATE (invoiceNumber & createdAt asli dipertahankan); kalau tidak,
  /// nota baru dibuat seperti biasa.
  Future<ManualNota> saveNota({double? amountPaid}) async {
    final validItems = state.validItems;
    if (validItems.isEmpty) {
      throw Exception('Nota masih kosong.');
    }
    final total = validItems.fold(0.0, (s, i) => s + i.total);
    final customerName =
        Value(state.customerName.trim().isEmpty ? null : state.customerName.trim());
    final itemsJson = jsonEncode(validItems.map((i) => i.toJson()).toList());

    if (editingId != null) {
      final companion = ManualNotasCompanion(
        customerName: customerName,
        itemsJson: Value(itemsJson),
        total: Value(total),
        amountPaid: Value(amountPaid),
        updatedAt: Value(DateTime.now()),
      );
      await db.manualNotasDao.updateNota(editingId!, companion);
      final saved = await db.manualNotasDao.getById(editingId!);
      return saved!;
    }

    final invoiceNumber = await db.manualNotasDao.nextInvoiceNumber();
    final companion = ManualNotasCompanion.insert(
      invoiceNumber: invoiceNumber,
      customerName: customerName,
      itemsJson: itemsJson,
      total: Value(total),
      amountPaid: Value(amountPaid),
    );
    final id = await db.manualNotasDao.insertNota(companion);
    final saved = await db.manualNotasDao.getById(id);
    return saved!;
  }
}

/// Family di-key oleh nota yang sedang diedit: null = mode buat nota baru,
/// non-null = mode edit (dibuka dari tombol Edit di Riwayat Transaksi).
final manualNotaProvider = StateNotifierProvider.autoDispose
    .family<ManualNotaNotifier, ManualNotaState, ManualNota?>((ref, editingNota) {
  final db = ref.watch(databaseProvider);
  return ManualNotaNotifier(db, editingNota: editingNota);
});

/// Helper untuk decode itemsJson dari ManualNota tersimpan (dipakai di
/// riwayat/laporan/cetak-ulang).
List<ManualNotaItem> decodeManualNotaItems(String itemsJson) {
  final list = jsonDecode(itemsJson) as List<dynamic>;
  return list
      .map((e) => ManualNotaItem.fromJson(e as Map<String, dynamic>))
      .toList();
}
