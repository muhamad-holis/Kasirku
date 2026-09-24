import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'products_provider.dart';
import 'hutang_provider.dart';

// ─── Model Notifikasi ─────────────────────────────────────────────────────────

enum NotifType { stokHampirHabis, stokHabis, hutangJatuhTempo, scanBarcode, info }

class AppNotification {
  final String id;
  final NotifType type;
  final String title;
  final String message;
  final DateTime time;
  bool isRead;

  AppNotification({
    required this.id,
    required this.type,
    required this.title,
    required this.message,
    required this.time,
    this.isRead = false,
  });

  AppNotification copyWith({bool? isRead}) => AppNotification(
        id: id,
        type: type,
        title: title,
        message: message,
        time: time,
        isRead: isRead ?? this.isRead,
      );

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.index,
    'title': title,
    'message': message,
    'time': time.millisecondsSinceEpoch,
    'isRead': isRead,
  };

  factory AppNotification.fromJson(Map<String, dynamic> json) => AppNotification(
    id: json['id'],
    type: NotifType.values[json['type']],
    title: json['title'],
    message: json['message'],
    time: DateTime.fromMillisecondsSinceEpoch(json['time']),
    isRead: json['isRead'] ?? false,
  );
}

// ─── Notification Notifier ────────────────────────────────────────────────────

const _kNotifKey = 'app_notifications';

class NotificationNotifier extends StateNotifier<List<AppNotification>> {
  NotificationNotifier() : super([]) {
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kNotifKey);
      if (raw != null) {
        final list = (jsonDecode(raw) as List)
            .map((e) => AppNotification.fromJson(e))
            .toList();
        state = list;
      }
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _kNotifKey, jsonEncode(state.map((n) => n.toJson()).toList()));
    } catch (_) {}
  }

  void add(AppNotification notif) {
    if (state.any((n) => n.id == notif.id)) return;
    state = [notif, ...state];
    _save();
  }

  void markRead(String id) {
    state = state.map((n) => n.id == id ? n.copyWith(isRead: true) : n).toList();
    _save();
  }

  void markAllRead() {
    state = state.map((n) => n.copyWith(isRead: true)).toList();
    _save();
  }

  void remove(String id) {
    state = state.where((n) => n.id != id).toList();
    _save();
  }

  void clearAll() {
    state = [];
    _save();
  }

  int get unreadCount => state.where((n) => !n.isRead).length;
}

final notificationProvider =
    StateNotifierProvider<NotificationNotifier, List<AppNotification>>(
  (ref) {
    final notifier = NotificationNotifier();

    // ── Watch lowStock → generate notif stok ──────────────────────────────────
    ref.listen(lowStockProvider, (prev, next) {
      next.whenData((products) {
        // BUG #5 FIX: Cleanup notif stok yang produknya sudah normal kembali.
        // Sebelumnya notif 'low_X' / 'out_X' tidak pernah dihapus meski stok direstok.
        // Langkah 1: Hitung set ID yang masih aktif (produk masih low/out)
        final activeIds = <String>{
          for (final p in products)
            p.stock <= 0 ? 'out_${p.id}' : 'low_${p.id}'
        };
        // Langkah 2: Hapus notif stok yang produknya sudah kembali normal
        final stale = notifier.state
            .where((n) =>
                (n.type == NotifType.stokHabis ||
                 n.type == NotifType.stokHampirHabis) &&
                !activeIds.contains(n.id))
            .map((n) => n.id)
            .toList();
        for (final id in stale) {
          notifier.remove(id);
        }
        // Langkah 3: Tambahkan notif baru untuk yang masih low/out
        for (final p in products) {
          final isOut = p.stock <= 0;
          final id = isOut ? 'out_${p.id}' : 'low_${p.id}';
          notifier.add(AppNotification(
            id: id,
            type: isOut ? NotifType.stokHabis : NotifType.stokHampirHabis,
            title: isOut ? 'Stok Habis!' : 'Stok Hampir Habis',
            message: isOut
                ? '${p.name} sudah habis. Segera restok!'
                : '${p.name} tinggal ${p.stock} ${p.unit} (min: ${p.minStock})',
            time: DateTime.now(),
          ));
        }
      });
    });

    // ── BUG #2 FIX: Watch overdueDebts → generate notif hutang jatuh tempo ──
    // Sebelumnya NotifType.hutangJatuhTempo ada di enum tapi tidak pernah di-generate.
    ref.listen(overdueDebtsWithCustomerProvider, (prev, next) {
      next.whenData((overdueList) {
        // Cleanup: hapus notif hutang yang sudah lunas / tidak lagi overdue
        final activeDebtIds = <String>{
          for (final d in overdueList) 'debt_${d.debt.id}'
        };
        final staleDebt = notifier.state
            .where((n) =>
                n.type == NotifType.hutangJatuhTempo &&
                !activeDebtIds.contains(n.id))
            .map((n) => n.id)
            .toList();
        for (final id in staleDebt) {
          notifier.remove(id);
        }

        // Tambahkan notif untuk hutang yang baru / masih overdue
        for (final d in overdueList) {
          final id = 'debt_${d.debt.id}';
          final sisa = d.debt.amount - d.debt.paidAmount;
          // Format rupiah sederhana tanpa dependency tambahan
          final sisaFormatted = 'Rp ${sisa.toStringAsFixed(0).replaceAllMapped(
            RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
            (m) => '${m[1]}.',
          )}';
          notifier.add(AppNotification(
            id: id,
            type: NotifType.hutangJatuhTempo,
            title: 'Hutang Jatuh Tempo!',
            message:
                '${d.customerName} masih punya sisa hutang $sisaFormatted yang sudah jatuh tempo.',
            time: DateTime.now(),
          ));
        }
      });
    });

    return notifier;
  },
);

// Helper: unread count
final unreadCountProvider = Provider<int>((ref) {
  final notifs = ref.watch(notificationProvider);
  return notifs.where((n) => !n.isRead).length;
});
