import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../data/database/app_database.dart';

const _kDraftKey = 'kasir_draft';

class CartItem {
  final Product product;
  int quantity;
  double discount;

  CartItem({required this.product, this.quantity = 1, this.discount = 0});

  double get subtotal => (product.sellPrice * quantity) - discount;

  CartItem copyWith({int? quantity, double? discount}) => CartItem(
    product: product,
    quantity: quantity ?? this.quantity,
    discount: discount ?? this.discount,
  );
}

class KasirState {
  final List<CartItem> items;
  final double discountTotal;
  final double taxPercent;
  final String paymentMethod;
  final double amountPaid;
  final String notes;
  final int redeemPoints; // poin yang akan ditukar jadi diskon

  const KasirState({
    this.items = const [],
    this.discountTotal = 0,
    this.taxPercent = 0,
    this.paymentMethod = 'tunai',
    this.amountPaid = 0,
    this.notes = '',
    this.redeemPoints = 0,
  });

  double get subtotal => items.fold(0, (s, i) => s + i.subtotal);
  double get taxAmount => subtotal * (taxPercent / 100);
  // 1 poin = Rp 100 diskon
  double get pointDiscount => redeemPoints * 100;
  // BUG-03 FIX: total tidak bisa negatif meski diskon + poin melebihi subtotal
  double get total => (subtotal - discountTotal - pointDiscount + taxAmount).clamp(0.0, double.infinity);
  double get change => amountPaid - total;
  bool get isEmpty => items.isEmpty;
  int get totalItems => items.fold(0, (s, i) => s + i.quantity);

  KasirState copyWith({
    List<CartItem>? items,
    double? discountTotal,
    double? taxPercent,
    String? paymentMethod,
    double? amountPaid,
    String? notes,
    int? redeemPoints,
  }) => KasirState(
    items: items ?? this.items,
    discountTotal: discountTotal ?? this.discountTotal,
    taxPercent: taxPercent ?? this.taxPercent,
    paymentMethod: paymentMethod ?? this.paymentMethod,
    amountPaid: amountPaid ?? this.amountPaid,
    notes: notes ?? this.notes,
    redeemPoints: redeemPoints ?? this.redeemPoints,
  );
}

class KasirNotifier extends StateNotifier<KasirState> {
  KasirNotifier() : super(const KasirState());

  void addProduct(Product product) {
    final items = [...state.items];
    final idx = items.indexWhere((i) => i.product.id == product.id);
    if (idx != -1) {
      // Check stock limit
      if (items[idx].quantity >= product.stock) return;
      items[idx] = items[idx].copyWith(quantity: items[idx].quantity + 1);
    } else {
      if (product.stock <= 0) return;
      items.add(CartItem(product: product));
    }
    state = state.copyWith(items: items);
  }

  void removeProduct(int productId) {
    state = state.copyWith(
      items: state.items.where((i) => i.product.id != productId).toList());
  }

  void updateQuantity(int productId, int qty) {
    if (qty <= 0) { removeProduct(productId); return; }
    final item = state.items.firstWhere((i) => i.product.id == productId);
    if (qty > item.product.stock) return;
    state = state.copyWith(
      items: state.items.map((i) =>
        i.product.id == productId ? i.copyWith(quantity: qty) : i).toList());
  }

  void updateItemDiscount(int productId, double discount) {
    state = state.copyWith(
      items: state.items.map((i) =>
        i.product.id == productId ? i.copyWith(discount: discount) : i).toList());
  }

  void setDiscount(double v) => state = state.copyWith(discountTotal: v);
  void setTax(double v)      => state = state.copyWith(taxPercent: v);
  void setPaymentMethod(String v) => state = state.copyWith(paymentMethod: v);
  void setAmountPaid(double v)    => state = state.copyWith(amountPaid: v);
  void setNotes(String v)         => state = state.copyWith(notes: v);
  void setRedeemPoints(int v)     => state = state.copyWith(redeemPoints: v);
  void clear() => state = const KasirState();

  // ── Draft ───────────────────────────────────────────────────────────────────
  Future<void> saveDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final items = state.items.map((i) => {
        'productId': i.product.id,
        'productName': i.product.name,
        'sellPrice': i.product.sellPrice,
        'unit': i.product.unit,
        'stock': i.product.stock,
        'minStock': i.product.minStock,
        'quantity': i.quantity,
        'discount': i.discount,
      }).toList();
      final draft = {
        'items': items,
        'discountTotal': state.discountTotal,
        'taxPercent': state.taxPercent,
        'notes': state.notes,
        'savedAt': DateTime.now().millisecondsSinceEpoch,
      };
      await prefs.setString(_kDraftKey, jsonEncode(draft));
    } catch (_) {}
  }

  Future<bool> hasDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.containsKey(_kDraftKey);
    } catch (_) {
      return false;
    }
  }

  Future<DateTime?> getDraftTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kDraftKey);
      if (raw == null) return null;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final ts = data['savedAt'] as int?;
      if (ts == null) return null;
      return DateTime.fromMillisecondsSinceEpoch(ts);
    } catch (_) {
      return null;
    }
  }

  // BUG #8 FIX: loadDraft menerima AppDatabase sebagai parameter agar bisa
  // refresh stok tiap produk dari DB sebelum di-load ke state.
  // Tanpa ini, CartItem menggunakan stok snapshot lama saat draft dibuat,
  // sehingga validasi qty bisa lolos meskipun stok aktual sudah berkurang.
  Future<void> loadDraft(AppDatabase db) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kDraftKey);
      if (raw == null) return;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final itemsJson = data['items'] as List;

      final List<CartItem> items = [];
      for (final e in itemsJson) {
        final productId = e['productId'] as int;

        // Ambil stok terbaru dari DB; fallback ke nilai draft jika produk hilang
        final freshProduct = await db.productsDao.getProductById(productId);

        final p = Product(
          id: productId,
          name: e['productName'],
          sellPrice: (e['sellPrice'] as num).toDouble(),
          unit: e['unit'] ?? 'pcs',
          // Gunakan stok terbaru dari DB, bukan snapshot lama
          stock: freshProduct?.stock ?? (e['stock'] ?? 0),
          minStock: freshProduct?.minStock ?? (e['minStock'] ?? 5),
          categoryId: freshProduct?.categoryId ?? 0,
          buyPrice: freshProduct?.buyPrice ?? 0,
          isActive: freshProduct?.isActive ?? true,
          createdAt: freshProduct?.createdAt ?? DateTime.now(),
          updatedAt: freshProduct?.updatedAt ?? DateTime.now(),
        );

        final qty = e['quantity'] as int;
        // Clamp quantity agar tidak melebihi stok aktual
        final safeQty = qty.clamp(1, p.stock > 0 ? p.stock : 1);

        items.add(CartItem(
          product: p,
          quantity: safeQty,
          discount: (e['discount'] as num).toDouble(),
        ));
      }

      state = KasirState(
        items: items,
        discountTotal: (data['discountTotal'] as num).toDouble(),
        taxPercent: (data['taxPercent'] as num).toDouble(),
        notes: data['notes'] ?? '',
      );
      await clearDraft();
    } catch (_) {}
  }

  Future<void> clearDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kDraftKey);
    } catch (_) {}
  }
}

final kasirProvider =
    StateNotifierProvider<KasirNotifier, KasirState>((ref) => KasirNotifier());
