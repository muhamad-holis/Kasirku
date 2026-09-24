import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency.dart';
import '../../../core/utils/responsive.dart';
import '../../providers/dashboard_provider.dart';
import '../../providers/products_provider.dart';
import '../../providers/database_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/notification_provider.dart';
import '../../providers/auth_provider.dart';
import '../../navigation/app_router.dart';
import '../../../data/database/app_database.dart';
import '../notifikasi/notifikasi_screen.dart';
import '../settings/settings_screen.dart';
import '../riwayat/riwayat_screen.dart';
import '../kasir_management/kasir_management_screen.dart';
import '../login/login_screen.dart';

// ─── Helpers warna tema ───────────────────────────────────────────────────────

Color _bg(bool isDark)          => isDark ? AppColors.darkBg        : AppColors.bg;
Color _card(bool isDark)        => isDark ? AppColors.darkCard       : Colors.white;
Color _border(bool isDark)      => isDark ? AppColors.darkBorder     : AppColors.border;
Color _textPrimary(bool isDark) => isDark ? Colors.white             : AppColors.textPrimary;
Color _textSub(bool isDark)     => isDark ? const Color(0xFF94A3B8)  : AppColors.textSecondary;
Color _shimmer(bool isDark)     => isDark ? AppColors.darkSurface    : Colors.grey.shade100;
Color _priLight(bool isDark)    => isDark ? AppColors.darkPrimaryLight: AppColors.primaryLight;

// ─── DashboardStats Model ─────────────────────────────────────────────────────

class DashboardStats {
  final double omzetToday;
  final double omzetChange;
  final int txToday;
  final double txChange;
  final double avgToday;
  final double avgChange;
  final int productsSold;

  const DashboardStats({
    this.omzetToday = 0,
    this.omzetChange = 0,
    this.txToday = 0,
    this.txChange = 0,
    this.avgToday = 0,
    this.avgChange = 0,
    this.productsSold = 0,
  });
}

// ─── DashboardStats Provider ──────────────────────────────────────────────────
final dashboardStatsProvider = StreamProvider<DashboardStats>((ref) async* {
  final db  = ref.watch(databaseProvider);
  final now = DateTime.now();
  final startOfToday     = DateTime(now.year, now.month, now.day);
  final endOfToday       = startOfToday.add(const Duration(days: 1));
  final startOfYesterday = startOfToday.subtract(const Duration(days: 1));

  final todayStream = db.transactionsDao.watchTodayTransactions();

  await for (final todayTx in todayStream) {
    final yesterdayTx = await db.transactionsDao
        .getTransactionsByDate(startOfYesterday, startOfToday);

    final omzetToday     = todayTx.fold<double>(0, (sum, t) => sum + t.total);
    final omzetYesterday = yesterdayTx.fold<double>(0, (sum, t) => sum + t.total);

    double pctChange(double today, double yesterday) {
      if (yesterday == 0) return today > 0 ? 100.0 : 0.0;
      return ((today - yesterday) / yesterday) * 100;
    }

    final txToday      = todayTx.length;
    final txYesterday  = yesterdayTx.length;
    final avgToday     = txToday > 0 ? omzetToday / txToday : 0.0;
    final avgYesterday = txYesterday > 0 ? omzetYesterday / txYesterday : 0.0;

    final productsSold = await db.transactionsDao
        .getTotalProductsSold(todayTx.map((t) => t.id).toList());

    yield DashboardStats(
      omzetToday:   omzetToday,
      omzetChange:  pctChange(omzetToday, omzetYesterday),
      txToday:      txToday,
      txChange:     pctChange(txToday.toDouble(), txYesterday.toDouble()),
      avgToday:     avgToday,
      avgChange:    pctChange(avgToday, avgYesterday),
      productsSold: productsSold,
    );
  }
});

// ─── Provider items per transaction ──────────────────────────────────────────

final _txItemsProvider =
    FutureProvider.family<List<TransactionItem>, int>((ref, txId) =>
        ref.watch(databaseProvider).transactionsDao.getTransactionItems(txId));

// ─── DashboardScreen ──────────────────────────────────────────────────────────

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark   = Theme.of(context).brightness == Brightness.dark;
    final stats    = ref.watch(dashboardStatsProvider);
    final lowStock = ref.watch(lowStockProvider);
    final todayTx  = ref.watch(todayTransactionsProvider);
    final isTabletLandscape = Responsive.isTabletLandscape(context);

    if (isTabletLandscape) {
      return Scaffold(
        backgroundColor: _bg(isDark),
        body: Column(
          children: [
            _Header(),
            Expanded(
              child: CustomScrollView(
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
                    sliver: SliverToBoxAdapter(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 3,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _SectionTitle(
                                  'Ringkasan Hari Ini',
                                  action: 'Lihat semua',
                                  onAction: () => ref
                                      .read(currentNavIndexProvider.notifier)
                                      .state = 1,
                                ),
                                const SizedBox(height: 12),
                                stats.when(
                                  data:    (s)    => _SummaryGrid(stats: s),
                                  loading: ()     => _Shimmer(isDark: isDark, height: 180),
                                  error:   (e, _) => _ErrorWidget(msg: '$e'),
                                ),
                                const SizedBox(height: 24),
                                _SectionTitle(
                                  'Transaksi Terakhir',
                                  action: 'Lihat semua',
                                  onAction: () => ref
                                      .read(currentNavIndexProvider.notifier)
                                      .state = 1,
                                ),
                                const SizedBox(height: 12),
                                todayTx.when(
                                  data: (list) => list.isEmpty
                                      ? _EmptyTx(isDark: isDark)
                                      : _TxList(transactions: list.take(5).toList()),
                                  loading: () => _Shimmer(isDark: isDark, height: 80),
                                  error:   (e, _) => _ErrorWidget(msg: '$e'),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 20),
                          Expanded(
                            flex: 2,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _SectionTitle('Aksi Cepat'),
                                const SizedBox(height: 12),
                                _QuickActions(),
                                const SizedBox(height: 24),
                                lowStock.when(
                                  data: (list) => list.isEmpty
                                      ? const SizedBox()
                                      : _LowStockBanner(
                                          products: list,
                                          onLihatStok: () => ref
                                              .read(currentNavIndexProvider.notifier)
                                              .state = 3,
                                        ),
                                  loading: () => const SizedBox(),
                                  error:   (_, __) => const SizedBox(),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: _bg(isDark),
      body: Column(
        children: [
          _Header(), // Header kini bersifat sticky dan compact
          Expanded(
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      _SectionTitle(
                        'Ringkasan Hari Ini',
                        action: 'Lihat semua',
                        onAction: () =>
                            ref.read(currentNavIndexProvider.notifier).state = 1,
                      ),
                      const SizedBox(height: 12),
                      stats.when(
                        data:    (s)    => _SummaryGrid(stats: s),
                        loading: ()     => _Shimmer(isDark: isDark, height: 180),
                        error:   (e, _) => _ErrorWidget(msg: '$e'),
                      ),
                      const SizedBox(height: 24),

                      _SectionTitle('Aksi Cepat'),
                      const SizedBox(height: 12),
                      _QuickActions(),
                      const SizedBox(height: 24),

                      lowStock.when(
                        data: (list) => list.isEmpty
                            ? const SizedBox()
                            : _LowStockBanner(
                                products: list,
                                onLihatStok: () => ref
                                    .read(currentNavIndexProvider.notifier)
                                    .state = 3,
                              ),
                        loading: () => const SizedBox(),
                        error:   (_, __) => const SizedBox(),
                      ),

                      _SectionTitle(
                        'Transaksi Terakhir',
                        action: 'Lihat semua',
                        onAction: () =>
                            ref.read(currentNavIndexProvider.notifier).state = 1,
                      ),
                      const SizedBox(height: 12),
                      todayTx.when(
                        data: (list) => list.isEmpty
                            ? _EmptyTx(isDark: isDark)
                            : _TxList(transactions: list.take(5).toList()),
                        loading: () => _Shimmer(isDark: isDark, height: 80),
                        error:   (e, _) => _ErrorWidget(msg: '$e'),
                      ),
                      const SizedBox(height: 100),
                    ]),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Reusable shimmer & error ─────────────────────────────────────────────────

class _Shimmer extends StatelessWidget {
  final bool isDark;
  final double height;
  const _Shimmer({required this.isDark, required this.height});

  @override
  Widget build(BuildContext context) => Container(
        height: height,
        decoration: BoxDecoration(
          color: _shimmer(isDark),
          borderRadius: BorderRadius.circular(16),
        ),
      );
}

class _ErrorWidget extends StatelessWidget {
  final String msg;
  const _ErrorWidget({required this.msg});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(8),
        child: Text(msg,
            style: const TextStyle(color: AppColors.danger, fontSize: 12)),
      );
}

class _EmptyTx extends StatelessWidget {
  final bool isDark;
  const _EmptyTx({required this.isDark});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 32),
        alignment: Alignment.center,
        child: Column(children: [
          Icon(Icons.receipt_long_outlined,
              size: 48, color: _textSub(isDark).withOpacity(0.4)),
          const SizedBox(height: 8),
          Text('Belum ada transaksi hari ini',
              style: TextStyle(color: _textSub(isDark), fontSize: 13)),
        ]),
      );
}

// ─── Header (Compact & Sticky) ────────────────────────────────────────────────

class _Header extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark   = Theme.of(context).brightness == Brightness.dark;
    final settings = ref.watch(storeSettingsProvider);
    final headerBg = isDark ? const Color(0xFF134E4A) : AppColors.primary;

    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 20,
        left: 16,
        right: 16,
        bottom: 24,
      ),
      decoration: BoxDecoration(
        color: headerBg,
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(24),
        ),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 4))
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => _showSwitchRoleSheet(context, ref),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.storefront_outlined,
                        color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Consumer(
                      builder: (ctx, r, _) {
                        final user = r.watch(authProvider);
                        final isAdmin = user?.role == 'admin';
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              settings.storeName.isNotEmpty
                                  ? settings.storeName
                                  : 'KasirKu',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 18,
                                  color: Colors.white),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Row(
                              children: [
                                Text(
                                  isAdmin ? 'Admin' : 'Kasir',
                                  style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.white70,
                                      fontWeight: FontWeight.w600),
                                ),
                                const SizedBox(width: 4),
                                const Icon(Icons.keyboard_arrow_down_rounded,
                                    color: Colors.white70, size: 14),
                              ],
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          Consumer(
            builder: (context, ref, _) {
              final unreadCount = ref.watch(unreadCountProvider);
              return GestureDetector(
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ProviderScope(
                      parent: ProviderScope.containerOf(context),
                      child: const NotifikasiScreen(),
                    ),
                  ),
                ),
                child: Stack(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.notifications_outlined,
                          color: Colors.white, size: 22),
                    ),
                    if (unreadCount > 0)
                      Positioned(
                        top: 0,
                        right: 0,
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444),
                            shape: BoxShape.circle,
                            border: Border.all(color: headerBg, width: 2),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  void _showSwitchRoleSheet(BuildContext context, WidgetRef ref) {
    final isDark    = Theme.of(context).brightness == Brightness.dark;
    final sheetBg   = isDark ? AppColors.darkSurface : Colors.white;
    final textColor = isDark ? Colors.white : AppColors.textPrimary;
    final user      = ref.read(authProvider);
    final isAdmin   = user?.role == 'admin';

    showModalBottomSheet(
      context: context,
      backgroundColor: sheetBg,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => ProviderScope(
        parent: ProviderScope.containerOf(context),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkBorder : Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Text(
                'Akun & Role',
                style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w800, color: textColor),
              ),
              const SizedBox(height: 6),
              Text(
                'Login ulang diperlukan untuk berpindah role',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark
                      ? const Color(0xFF94A3B8) : AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 20),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: isAdmin
                      ? AppColors.primary.withOpacity(0.08)
                      : AppColors.success.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isAdmin
                        ? AppColors.primary.withOpacity(0.25)
                        : AppColors.success.withOpacity(0.25),
                  ),
                ),
                child: Row(children: [
                  Icon(
                    isAdmin
                        ? Icons.admin_panel_settings_rounded
                        : Icons.badge_rounded,
                    color: isAdmin ? AppColors.primary : AppColors.success,
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      user?.displayName ?? '-',
                      style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w800,
                        color: textColor,
                      ),
                    ),
                    Text(
                      isAdmin ? 'Admin' : 'Kasir',
                      style: TextStyle(
                        fontSize: 11,
                        color: isAdmin ? AppColors.primary : AppColors.success,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ]),
                ]),
              ),
              const SizedBox(height: 16),

              if (isAdmin) ...[
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.people_outline_rounded, size: 18),
                    label: const Text('Kelola Admin & Kasir',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ProviderScope(
                            parent: ProviderScope.containerOf(context),
                            child: const KasirManagementScreen(),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 10),
              ],

              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                  label: Text(
                    isAdmin
                        ? 'Ganti ke Role Kasir'
                        : 'Ganti ke Role Admin',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => _confirmLogout(context, ref, isAdmin),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmLogout(BuildContext context, WidgetRef ref, bool isAdmin) {
    final targetRole = isAdmin ? 'Kasir' : 'Admin';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Ganti Role',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
        content: Text(
          'Kamu akan logout dan login ulang sebagai $targetRole.\nLanjutkan?',
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              Navigator.pop(context);
              await ref.read(authProvider.notifier).logout();
              if (context.mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (route) => false,
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Ya, Logout',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onAction;
  const _SectionTitle(this.title, {this.action, this.onAction});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: _textPrimary(isDark),
            )),
        if (action != null)
          GestureDetector(
            onTap: onAction,
            child: Row(children: [
              Text(action!,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  )),
              const Icon(Icons.chevron_right, size: 16, color: AppColors.primary),
            ]),
          ),
      ],
    );
  }
}

// ─── Summary Grid ─────────────────────────────────────────────────────────────

class _SummaryGrid extends StatelessWidget {
  final DashboardStats stats;
  const _SummaryGrid({required this.stats});

  String _badge(double pct, {bool isProductSold = false}) {
    if (isProductSold) return 'hari ini';
    if (pct == 0) return '= sama seperti kemarin';
    final sign = pct > 0 ? '+' : '';
    return '$sign${pct.toStringAsFixed(1)}% dari kemarin';
  }

  bool _isUp(double pct) => pct >= 0;

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Row(children: [
        Expanded(child: _StatCard(
          title: 'Total Penjualan',
          value: CurrencyFormatter.format(stats.omzetToday),
          badge: _badge(stats.omzetChange),
          isUp: _isUp(stats.omzetChange),
          icon: Icons.shopping_bag_outlined,
          color: AppColors.primary,
        )),
        const SizedBox(width: 10),
        Expanded(child: _StatCard(
          title: 'Transaksi',
          value: '${stats.txToday}',
          badge: _badge(stats.txChange),
          isUp: _isUp(stats.txChange),
          icon: Icons.receipt_long_outlined,
          color: AppColors.info,
        )),
      ]),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(child: _StatCard(
          title: 'Rata-rata Transaksi',
          value: CurrencyFormatter.format(stats.avgToday),
          badge: _badge(stats.avgChange),
          isUp: _isUp(stats.avgChange),
          icon: Icons.bar_chart_rounded,
          color: AppColors.success,
        )),
        const SizedBox(width: 10),
        Expanded(child: _StatCard(
          title: 'Produk Terjual',
          value: '${stats.productsSold}',
          badge: _badge(0, isProductSold: true),
          isUp: true,
          icon: Icons.inventory_2_outlined,
          color: AppColors.warning,
        )),
      ]),
    ]);
  }
}

class _StatCard extends StatelessWidget {
  final String title, value, badge;
  final bool isUp;
  final IconData icon;
  final Color color;
  const _StatCard({
    required this.title, required this.value, required this.badge,
    required this.isUp,  required this.icon,  required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isDark     = Theme.of(context).brightness == Brightness.dark;
    final badgeColor = isUp ? AppColors.success : AppColors.danger;
    final badgeIcon  = isUp ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card(isDark),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border(isDark), width: 0.5),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(height: 10),
        Text(value,
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: color)),
        const SizedBox(height: 2),
        Text(title,
            style: TextStyle(
              fontSize: 11, fontWeight: FontWeight.w500, color: _textSub(isDark))),
        const SizedBox(height: 4),
        Row(children: [
          Icon(badgeIcon, size: 10, color: badgeColor),
          const SizedBox(width: 2),
          Flexible(
            child: Text(badge,
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10, color: badgeColor, fontWeight: FontWeight.w600)),
          ),
        ]),
      ]),
    );
  }
}

// ─── Quick Actions ────────────────────────────────────────────────────────────

class _QuickActions extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = [
      _QA(icon: Icons.shopping_cart_outlined, label: 'Mulai Kasir',
          color: AppColors.primary,
          onTap: () => ref.read(currentNavIndexProvider.notifier).state = 2),
      _QA(icon: Icons.add_box_outlined, label: 'Tambah Produk',
          color: AppColors.success,
          onTap: () {
            ref.read(currentNavIndexProvider.notifier).state = 3;
            Future.delayed(const Duration(milliseconds: 300), () {
              if (context.mounted) {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
                  builder: (_) => ProviderScope(
                    parent: ProviderScope.containerOf(context),
                    child: const _AddProductSheet(),
                  ),
                );
              }
            });
          }),
      _QA(icon: Icons.history_rounded, label: 'Riwayat Transaksi',
          color: AppColors.info,
          onTap: () => Navigator.push(context,
              MaterialPageRoute(builder: (_) => ProviderScope(
                parent: ProviderScope.containerOf(context),
                child: const RiwayatScreen())))),
      _QA(icon: Icons.insert_chart_outlined_rounded, label: 'Laporan Hari Ini',
          color: AppColors.warning,
          onTap: () => ref.read(currentNavIndexProvider.notifier).state = 1),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 360;
        if (isNarrow) {
          return GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
            childAspectRatio: 1.3,
            children: actions.map((a) => _QACard(qa: a)).toList(),
          );
        }
        return Row(
          children: actions.map((a) => Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: _QACard(qa: a),
            ),
          )).toList(),
        );
      },
    );
  }
}

class _QA {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _QA({required this.icon, required this.label,
              required this.color, required this.onTap});
}

class _QACard extends StatelessWidget {
  final _QA qa;
  const _QACard({required this.qa});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: qa.onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
        decoration: BoxDecoration(
          color: _card(isDark),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _border(isDark), width: 0.5),
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: qa.color.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(qa.icon, color: qa.color, size: 22),
          ),
          const SizedBox(height: 8),
          Text(qa.label,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.w600,
                color: _textPrimary(isDark), height: 1.3,
              )),
        ]),
      ),
    );
  }
}

// ─── Low Stock Banner ─────────────────────────────────────────────────────────

class _LowStockBanner extends StatelessWidget {
  final List products;
  final VoidCallback onLihatStok;
  const _LowStockBanner({required this.products, required this.onLihatStok});

  @override
  Widget build(BuildContext context) {
    final isDark  = Theme.of(context).brightness == Brightness.dark;
    final bannerBg = isDark
        ? AppColors.warning.withOpacity(0.12)
        : const Color(0xFFFFF7ED);

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bannerBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.warning.withOpacity(0.3)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.warning_amber_rounded,
                  size: 16, color: AppColors.warning),
              const SizedBox(width: 6),
              const Text('Stok Hampir Habis',
                  style: TextStyle(
                    color: AppColors.warning,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  )),
            ]),
            const SizedBox(height: 4),
            Text(
              '${products.length} produk stoknya hampir habis. '
              'Segera lakukan restok agar penjualan tetap lancar.',
              style: TextStyle(
                  fontSize: 12, color: _textSub(isDark), height: 1.4),
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: onLihatStok,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.warning,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text('Lihat Stok',
                    style: TextStyle(
                        color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ),
          ]),
        ),
        const SizedBox(width: 12),
        Icon(Icons.inventory_2_outlined,
            size: 52, color: AppColors.warning.withOpacity(0.3)),
      ]),
    );
  }
}

// ─── Transaction List ─────────────────────────────────────────────────────────

class _TxList extends ConsumerWidget {
  final List<Transaction> transactions;
  const _TxList({required this.transactions});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      children: transactions.map((tx) => GestureDetector(
        onTap: () => _showDetail(context, ref, tx),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _card(isDark),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _border(isDark), width: 0.5),
          ),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _priLight(isDark),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.shopping_bag_outlined,
                  color: AppColors.primary, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(tx.invoiceNumber,
                    style: TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 13,
                      color: _textPrimary(isDark),
                    )),
                const SizedBox(height: 2),
                Text(_formatDate(tx.createdAt),
                    style: TextStyle(fontSize: 11, color: _textSub(isDark))),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(CurrencyFormatter.format(tx.total),
                  style: TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 14,
                    color: _textPrimary(isDark),
                  )),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(_methodLabel(tx.paymentMethod),
                    style: const TextStyle(
                      fontSize: 10, color: AppColors.success,
                      fontWeight: FontWeight.w600,
                    )),
              ),
            ]),
          ]),
        ),
      )).toList(),
    );
  }

  void _showDetail(BuildContext context, WidgetRef ref, Transaction tx) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => ProviderScope(
        parent: ProviderScope.containerOf(context),
        child: _TxDetailSheet(transaction: tx),
      ),
    );
  }

  String _methodLabel(String? m) {
    switch (m) {
      case 'tunai':    return 'Tunai';
      case 'transfer': return 'Transfer';
      case 'qris':     return 'QRIS';
      case 'hutang':   return 'Hutang';
      default:         return 'Selesai';
    }
  }

  String _formatDate(DateTime dt) {
    const months = ['Jan','Feb','Mar','Apr','Mei','Jun',
                    'Jul','Ags','Sep','Okt','Nov','Des'];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year} • '
        '${dt.hour.toString().padLeft(2,'0')}:'
        '${dt.minute.toString().padLeft(2,'0')}';
  }
}

// ─── Transaction Detail Sheet ─────────────────────────────────────────────────

class _TxDetailSheet extends ConsumerWidget {
  final Transaction transaction;
  const _TxDetailSheet({required this.transaction});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark      = Theme.of(context).brightness == Brightness.dark;
    final itemsFuture = ref.watch(_txItemsProvider(transaction.id));
    final handleColor = isDark ? AppColors.darkBorder : Colors.grey.shade300;
    final notesBg     = isDark ? AppColors.darkSurface : Colors.grey.shade50;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.92,
      builder: (_, controller) => Column(children: [
        Container(
          margin: const EdgeInsets.only(top: 12, bottom: 8),
          width: 40, height: 4,
          decoration: BoxDecoration(
            color: handleColor, borderRadius: BorderRadius.circular(2)),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(transaction.invoiceNumber,
                    style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800,
                      color: _textPrimary(isDark),
                    )),
                Text(_formatDate(transaction.createdAt),
                    style: TextStyle(fontSize: 12, color: _textSub(isDark))),
              ]),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(_methodLabel(transaction.paymentMethod),
                    style: const TextStyle(
                      fontSize: 12, color: AppColors.success,
                      fontWeight: FontWeight.w700,
                    )),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView(
            controller: controller,
            padding: const EdgeInsets.all(20),
            children: [
              Text('Item Produk',
                  style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700,
                    color: _textSub(isDark),
                  )),
              const SizedBox(height: 8),
              itemsFuture.when(
                data: (items) => items.isEmpty
                    ? Text('Tidak ada item',
                        style: TextStyle(color: _textSub(isDark)))
                    : Column(
                        children: items.map((item) => _ItemRow(item: item)).toList()),
                loading: () => const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(),
                    )),
                error: (e, _) => Text('Error: $e',
                    style: const TextStyle(color: AppColors.danger)),
              ),
              const Divider(height: 24),
              _SummaryRow('Subtotal',
                  CurrencyFormatter.format(transaction.subtotal)),
              if (transaction.discountAmount > 0)
                _SummaryRow('Diskon',
                    '- ${CurrencyFormatter.format(transaction.discountAmount)}',
                    color: AppColors.danger),
              if (transaction.taxAmount > 0)
                _SummaryRow('Pajak',
                    CurrencyFormatter.format(transaction.taxAmount)),
              const Divider(height: 16),
              _SummaryRow('Total',
                  CurrencyFormatter.format(transaction.total),
                  bold: true, color: AppColors.primary),
              _SummaryRow('Dibayar',
                  CurrencyFormatter.format(transaction.amountPaid)),
              if (transaction.change > 0)
                _SummaryRow('Kembalian',
                    CurrencyFormatter.format(transaction.change),
                    color: AppColors.success),
              if (transaction.notes != null && transaction.notes!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: notesBg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: _border(isDark)),
                  ),
                  child: Row(children: [
                    Icon(Icons.notes_rounded,
                        size: 16, color: _textSub(isDark)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(transaction.notes!,
                          style: TextStyle(
                              fontSize: 12, color: _textSub(isDark))),
                    ),
                  ]),
                ),
              ],
              const SizedBox(height: 20),
            ],
          ),
        ),
      ]),
    );
  }

  String _methodLabel(String? m) {
    switch (m) {
      case 'tunai':    return 'Tunai';
      case 'transfer': return 'Transfer';
      case 'qris':     return 'QRIS';
      case 'hutang':   return 'Hutang';
      default:         return 'Selesai';
    }
  }

  String _formatDate(DateTime dt) {
    const months = ['Jan','Feb','Mar','Apr','Mei','Jun',
                    'Jul','Ags','Sep','Okt','Nov','Des'];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year} • '
        '${dt.hour.toString().padLeft(2,'0')}:'
        '${dt.minute.toString().padLeft(2,'0')}';
  }
}

class _ItemRow extends StatelessWidget {
  final TransactionItem item;
  const _ItemRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(item.productName,
                style: TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600,
                  color: _textPrimary(isDark),
                )),
            Text('${item.quantity}x ${CurrencyFormatter.format(item.price)}',
                style: TextStyle(fontSize: 11, color: _textSub(isDark))),
          ]),
        ),
        Text(CurrencyFormatter.format(item.subtotal),
            style: TextStyle(
              fontSize: 13, fontWeight: FontWeight.w700,
              color: _textPrimary(isDark),
            )),
      ]),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String label, value;
  final bool bold;
  final Color? color;
  const _SummaryRow(this.label, this.value, {this.bold = false, this.color});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                fontSize: bold ? 14 : 13,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
                color: bold ? _textPrimary(isDark) : _textSub(isDark),
              )),
          Text(value,
              style: TextStyle(
                fontSize: bold ? 14 : 13,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
                color: color ?? _textPrimary(isDark),
              )),
        ],
      ),
    );
  }
}

// ─── Add Product Quick Sheet ──────────────────────────────────────────────────

class _AddProductSheet extends ConsumerWidget {
  const _AddProductSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: EdgeInsets.only(
        top: 20, left: 20, right: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 40, height: 4,
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkBorder : Colors.grey.shade300,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 20),
        const Icon(Icons.inventory_2_outlined, size: 48, color: AppColors.primary),
        const SizedBox(height: 12),
        Text('Tambah Produk',
            style: TextStyle(
              fontSize: 18, fontWeight: FontWeight.w800,
              color: _textPrimary(isDark),
            )),
        const SizedBox(height: 8),
        Text(
          'Kamu sudah ada di tab Stock. '
          'Tap tombol + di bawah layar untuk menambah produk baru.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: _textSub(isDark), fontSize: 13, height: 1.5),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Oke, Mengerti',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
      ]),
    );
  }
}
