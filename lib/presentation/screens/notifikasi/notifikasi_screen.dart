// lib/presentation/screens/notifikasi/notifikasi_screen.dart
// ─────────────────────────────────────────────────────────────────────────────
// Sistem Notifikasi (P4) — Stok Menipis + Hutang Jatuh Tempo
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../../providers/notification_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SCREEN NOTIFIKASI
// ─────────────────────────────────────────────────────────────────────────────

class NotifikasiScreen extends ConsumerWidget {
  const NotifikasiScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifs = ref.watch(notificationProvider);
    final unread = notifs.where((n) => !n.isRead).length;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Notifikasi',
                style: TextStyle(fontWeight: FontWeight.w700)),
            if (unread > 0)
              Text('$unread belum dibaca',
                  style: const TextStyle(
                      fontSize: 11, color: Colors.white70)),
          ],
        ),
        actions: [
          if (notifs.isNotEmpty)
            TextButton(
              onPressed: () =>
                  ref.read(notificationProvider.notifier).markAllRead(),
              child: const Text('Tandai Semua Dibaca',
                  style:
                      TextStyle(color: Colors.white, fontSize: 12)),
            ),
          if (notifs.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined),
              tooltip: 'Hapus semua',
              onPressed: () => _confirmClearAll(context, ref),
            ),
        ],
      ),
      body: notifs.isEmpty
          ? _EmptyNotif()
          : ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: notifs.length,
              separatorBuilder: (_, __) => const Divider(
                  height: 1, indent: 72),
              itemBuilder: (_, i) => _NotifTile(notif: notifs[i]),
            ),
    );
  }

  void _confirmClearAll(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hapus Semua Notifikasi?'),
        content: const Text(
            'Semua notifikasi akan dihapus. Tindakan ini tidak bisa dibatalkan.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal')),
          FilledButton(
            style:
                FilledButton.styleFrom(backgroundColor: AppColors.danger),
            onPressed: () {
              ref.read(notificationProvider.notifier).clearAll();
              Navigator.pop(context);
            },
            child: const Text('Hapus Semua'),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// NOTIFIKASI TILE
// ─────────────────────────────────────────────────────────────────────────────

class _NotifTile extends ConsumerWidget {
  final AppNotification notif;
  const _NotifTile({required this.notif});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = _getConfig(notif.type);

    return Dismissible(
      key: Key(notif.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: AppColors.danger,
        child: const Icon(Icons.delete_outline, color: Colors.white),
      ),
      onDismissed: (_) =>
          ref.read(notificationProvider.notifier).remove(notif.id),
      child: InkWell(
        onTap: () =>
            ref.read(notificationProvider.notifier).markRead(notif.id),
        child: Container(
          color: notif.isRead ? Colors.transparent : config.bg,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: config.color.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(config.icon,
                    size: 20, color: config.color),
              ),
              const SizedBox(width: 12),

              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(notif.title,
                              style: TextStyle(
                                  fontWeight: notif.isRead
                                      ? FontWeight.w600
                                      : FontWeight.w800,
                                  fontSize: 13)),
                        ),
                        if (!notif.isRead)
                          Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: config.color,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(notif.message,
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600)),
                    const SizedBox(height: 4),
                    Text(
                      _timeAgo(notif.time),
                      style: TextStyle(
                          fontSize: 10, color: Colors.grey.shade400),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  _NotifConfig _getConfig(NotifType type) {
    switch (type) {
      case NotifType.stokHabis:
        return _NotifConfig(
          icon: Icons.inventory_2_outlined,
          color: AppColors.danger,
          bg: AppColors.danger.withOpacity(0.04),
        );
      case NotifType.stokHampirHabis:
        return _NotifConfig(
          icon: Icons.warning_amber_rounded,
          color: AppColors.warning,
          bg: AppColors.warning.withOpacity(0.04),
        );
      case NotifType.hutangJatuhTempo:
        return _NotifConfig(
          icon: Icons.receipt_long_outlined,
          color: AppColors.danger,
          bg: AppColors.danger.withOpacity(0.04),
        );
      case NotifType.scanBarcode:
        return _NotifConfig(
          icon: Icons.qr_code_scanner_outlined,
          color: AppColors.info,
          bg: AppColors.info.withOpacity(0.04),
        );
      default:
        return _NotifConfig(
          icon: Icons.info_outline,
          color: AppColors.info,
          bg: AppColors.info.withOpacity(0.04),
        );
    }
  }

  String _timeAgo(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'Baru saja';
    if (diff.inHours < 1) return '${diff.inMinutes} menit lalu';
    if (diff.inDays < 1) return '${diff.inHours} jam lalu';
    if (diff.inDays == 1) return 'Kemarin';
    if (diff.inDays < 7) return '${diff.inDays} hari lalu';
    return DateFormat('dd MMM yyyy', 'id').format(time);
  }
}

class _NotifConfig {
  final IconData icon;
  final Color color, bg;
  const _NotifConfig(
      {required this.icon, required this.color, required this.bg});
}

// ─────────────────────────────────────────────────────────────────────────────
// EMPTY STATE
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyNotif extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.notifications_none_outlined,
                size: 40, color: Colors.grey.shade400),
          ),
          const SizedBox(height: 16),
          const Text('Tidak ada notifikasi',
              style:
                  TextStyle(fontWeight: FontWeight.w600, fontSize: 16)),
          const SizedBox(height: 8),
          Text('Notifikasi stok dan hutang akan muncul di sini',
              style: TextStyle(
                  color: Colors.grey.shade500, fontSize: 13)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BELL ICON WIDGET — Pasang di AppBar (gunakan di DashboardScreen)
// ─────────────────────────────────────────────────────────────────────────────

class NotifBellIcon extends ConsumerWidget {
  const NotifBellIcon({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(unreadCountProvider);

    return Stack(
      alignment: Alignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.notifications_outlined),
          tooltip: 'Notifikasi',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => const NotifikasiScreen()),
          ),
        ),
        if (count > 0)
          Positioned(
            right: 8,
            top: 8,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(
                color: AppColors.danger,
                shape: BoxShape.circle,
              ),
              constraints:
                  const BoxConstraints(minWidth: 16, minHeight: 16),
              child: Text(
                count > 99 ? '99+' : '$count',
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w800),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }
}
