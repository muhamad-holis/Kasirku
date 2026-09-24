import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../screens/dashboard/dashboard_screen.dart';
import '../screens/kasir/kasir_screen.dart';
import '../screens/stok/stok_screen.dart';
import '../screens/laporan/laporan_screen.dart';
import '../screens/payment_method/payment_method_screen.dart';
import '../screens/settings/settings_screen.dart';
import '../screens/pelanggan/pelanggan_screen.dart';
import '../screens/hutang/hutang_screen.dart';
import '../screens/notifikasi/notifikasi_screen.dart';
import '../screens/kas/kas_screen.dart';
import '../screens/login/login_screen.dart'; 
import '../screens/supplier/supplier_screen.dart';
import '../screens/riwayat/riwayat_screen.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/responsive.dart';
import '../providers/auth_provider.dart';
import '../screens/kasir_management/kasir_management_screen.dart';

final currentNavIndexProvider = StateProvider<int>((ref) => 0);

// Key untuk nested Navigator di tab Lainnya — agar back button bisa dicegat
final _lainnyaNavKey = GlobalKey<NavigatorState>();

class MainNavigation extends ConsumerStatefulWidget {
  const MainNavigation({super.key});

  /// Buka layar Kas Masuk & Kas Keluar sebagai push route
  static void navigateToKas(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProviderScope(
          parent: ProviderScope.containerOf(context),
          child: const KasScreen(),
        ),
      ),
    );
  }

  @override
  ConsumerState<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends ConsumerState<MainNavigation> {
  final List<Widget> _screens = [
    const DashboardScreen(),   // 0 Dashboard
    const LaporanScreen(),     // 1 Laporan
    const KasirScreen(),       // 2 Kasir
    const _StokTabGuard(),     // 3 Stok (diblokir total untuk Kasir)
    const _LainnyaTab(),       // 4 Lainnya (nested navigator)
  ];

  Future<bool> _onWillPop() async {
    final idx = ref.read(currentNavIndexProvider);

    // Jika di tab Lainnya dan ada screen di dalam nested navigator → pop nested dulu
    if (idx == 4) {
      final canPop = _lainnyaNavKey.currentState?.canPop() ?? false;
      if (canPop) {
        _lainnyaNavKey.currentState!.pop();
        return false;
      }
    }

    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.exit_to_app_rounded, color: AppColors.primary, size: 22),
            SizedBox(width: 8),
            Text('Keluar Aplikasi',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          ],
        ),
        content: const Text(
          'Apakah kamu yakin ingin keluar dari aplikasi?',
          style: TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Tidak',
              style: TextStyle(color: AppColors.textSecondary)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Keluar'),
          ),
        ],
      ),
    );
    return shouldExit ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final idx      = ref.watch(currentNavIndexProvider);
    final aktifUser = ref.watch(authProvider);

    if (aktifUser == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const LoginScreen()),
            (_) => false,
          );
        }
      });
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final isTabletLandscape = Responsive.isTabletLandscape(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldExit = await _onWillPop();
        if (shouldExit) {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        body: isTabletLandscape
            ? Row(
                children: [
                  _SideNavRail(currentIndex: idx, ref: ref),
                  const VerticalDivider(width: 1),
                  Expanded(
                    child: IndexedStack(index: idx, children: _screens),
                  ),
                ],
              )
            : IndexedStack(index: idx, children: _screens),
        bottomNavigationBar:
            isTabletLandscape ? null : _BottomNavBar(currentIndex: idx, ref: ref),
        floatingActionButton: (isTabletLandscape && idx == 0)
            ? FloatingActionButton.extended(
                onPressed: () =>
                    ref.read(currentNavIndexProvider.notifier).state = 2,
                backgroundColor: AppColors.primary,
                icon: const Icon(Icons.point_of_sale_rounded, color: Colors.white),
                label: const Text('Buka Kasir',
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.w700)),
              )
            : null,
      ),
    );
  }

  Future<void> _doLogout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.logout_rounded, color: AppColors.danger, size: 22),
          SizedBox(width: 8),
          Text('Logout', style: TextStyle(fontWeight: FontWeight.w700)),
        ]),
        content: const Text('Yakin ingin logout dari akun ini?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
            ),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      await ref.read(authProvider.notifier).logout();
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
    }
  }
}

// ─── Tab Lainnya dengan Nested Navigator ─────────────────────────────────────

class _LainnyaTab extends StatelessWidget {
  const _LainnyaTab();

  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: _lainnyaNavKey,
      onGenerateRoute: (_) => MaterialPageRoute(
        builder: (_) => const _LainnyaHomeScreen(),
      ),
    );
  }
}

// ─── Halaman utama tab Lainnya (grid menu) ────────────────────────────────────

class _LainnyaHomeScreen extends ConsumerWidget {
  const _LainnyaHomeScreen();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark    = Theme.of(context).brightness == Brightness.dark;
    final aktifUser = ref.watch(authProvider);
    final isAdmin   = aktifUser?.isAdmin ?? false;
    
    // PERUBAHAN: Warna Header dibuat hijau sesuai instruksi
    final headerBg = isDark ? const Color(0xFF134E4A) : AppColors.primary;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.bg,
      body: CustomScrollView(
        slivers: [
          // ── Header Sticky ─────────────────────────────────────────────────────
          SliverPersistentHeader(
            pinned: true,
            delegate: _MenuHeaderDelegate(
              isDark: isDark,
              headerBg: headerBg,
              aktifUser: aktifUser,
              isAdmin: isAdmin,
              onLogout: () => _doLogout(context, ref),
              topPadding: MediaQuery.of(context).padding.top,
            ),
          ),

          // ── Grid menu ────────────────────────────────────────────────────
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: Responsive.gridColumns(context),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 0.95,
              ),
              delegate: SliverChildListDelegate([
                _MenuCard(
                  imagePath: 'assets/icons/menu/mulai_kasir.png',
                  label: 'Mulai Kasir',
                  description: 'Transaksi penjualan',
                  color: AppColors.primary,
                  onTap: () =>
                      ref.read(currentNavIndexProvider.notifier).state = 2,
                ),
                _MenuCard(
                  imagePath: 'assets/icons/menu/tambah_stok.png',
                  label: 'Tambah Produk',
                  description: 'Kelola stok produk',
                  color: AppColors.success,
                  onTap: () =>
                      ref.read(currentNavIndexProvider.notifier).state = 3,
                ),
                _MenuCard(
                  imagePath: 'assets/icons/menu/laporan.png',
                  label: 'Laporan Hari Ini',
                  description: 'Ringkasan penjualan',
                  color: AppColors.warning,
                  onTap: () =>
                      ref.read(currentNavIndexProvider.notifier).state = 1,
                ),
                _MenuCard(
                  imagePath: 'assets/icons/menu/keuangan.png',
                  label: 'Kas & Keuangan',
                  description: 'Kas masuk & keluar',
                  color: AppColors.success,
                  onTap: () => MainNavigation.navigateToKas(context),
                ),
                _MenuCard(
                  imagePath: 'assets/icons/menu/pelanggan.png',
                  label: 'Pelanggan',
                  description: 'Kelola data pelanggan',
                  color: AppColors.primary,
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => ProviderScope(
                        parent: ProviderScope.containerOf(context),
                        child: const PelangganScreen()))),
                ),
                _MenuCard(
                  imagePath: 'assets/icons/menu/pemasok.png',
                  label: 'Pemasok',
                  description: 'Data supplier & sales',
                  color: AppColors.info,
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => ProviderScope(
                        parent: ProviderScope.containerOf(context),
                        child: const SupplierScreen()))),
                ),
                _MenuCard(
                  imagePath: 'assets/icons/menu/riwayat_transaksi.png',
                  label: 'Riwayat Transaksi',
                  description: 'Histori & cetak ulang struk',
                  color: AppColors.success,
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => ProviderScope(
                        parent: ProviderScope.containerOf(context),
                        child: const RiwayatScreen()))),
                ),
                _MenuCard(
                  imagePath: 'assets/icons/menu/hutang.png',
                  label: 'Hutang',
                  description: 'Catat hutang piutang',
                  color: AppColors.warning,
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => ProviderScope(
                        parent: ProviderScope.containerOf(context),
                        child: const HutangScreen()))),
                ),
                _MenuCard(
                  imagePath: 'assets/icons/menu/notifikasi.png',
                  label: 'Notifikasi',
                  description: 'Stok & jatuh tempo',
                  color: AppColors.info,
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => ProviderScope(
                        parent: ProviderScope.containerOf(context),
                        child: const NotifikasiScreen()))),
                ),
                _MenuCard(
                  imagePath: 'assets/icons/menu/kalkulator.png',
                  label: 'Kalkulator',
                  description: 'Hitung cepat',
                  color: AppColors.info,
                  onTap: () => showDialog(
                    context: context,
                    builder: (_) => const _KalkulatorDialog(),
                  ),
                ),
                _MenuCard(
                  imagePath: 'assets/icons/menu/motode_pembayaran.png',
                  label: 'Metode Pembayaran',
                  description: 'QRIS & rekening transfer',
                  color: AppColors.primary,
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => ProviderScope(
                        parent: ProviderScope.containerOf(context),
                        child: const PaymentMethodScreen()))),
                ),
                if (isAdmin) ...[
                  _MenuCard(
                    imagePath: 'assets/icons/menu/kelola_admin.png',
                    label: 'Kelola Kasir',
                    description: 'Tambah & atur akun',
                    color: AppColors.success,
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => ProviderScope(
                          parent: ProviderScope.containerOf(context),
                          child: const KasirManagementScreen()))),
                  ),
                  _MenuCard(
                    imagePath: 'assets/icons/menu/pengaturan.png',
                    label: 'Pengaturan',
                    description: 'Toko, struk & printer',
                    color: AppColors.textSecondary,
                    onTap: () => Navigator.push(context,
                        MaterialPageRoute(builder: (_) => ProviderScope(
                          parent: ProviderScope.containerOf(context),
                          child: const SettingsScreen()))),
                  ),
                ],
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _doLogout(BuildContext context, WidgetRef ref) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.logout_rounded, color: AppColors.danger, size: 22),
          SizedBox(width: 8),
          Text('Logout', style: TextStyle(fontWeight: FontWeight.w700)),
        ]),
        content: const Text('Yakin ingin logout dari akun ini?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.danger,
                foregroundColor: Colors.white),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
    if (confirm == true && context.mounted) {
      await ref.read(authProvider.notifier).logout();
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
    }
  }
}

// ─── Card menu Lainnya ────────────────────────────────────────────────────────

// ─── Menu Header Delegate (Sticky) ───────────────────────────────────────────

class _MenuHeaderDelegate extends SliverPersistentHeaderDelegate {
  final bool isDark;
  final Color headerBg;
  final dynamic aktifUser;
  final bool isAdmin;
  final VoidCallback onLogout;
  final double topPadding;

  const _MenuHeaderDelegate({
    required this.isDark,
    required this.headerBg,
    required this.aktifUser,
    required this.isAdmin,
    required this.onLogout,
    required this.topPadding,
  });

  double get _expandedHeight => topPadding + 90;

  @override
  double get minExtent => _expandedHeight;

  @override
  double get maxExtent => _expandedHeight;

  @override
  bool shouldRebuild(_MenuHeaderDelegate old) =>
      old.isDark != isDark ||
      old.aktifUser != aktifUser ||
      old.isAdmin != isAdmin;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      padding: EdgeInsets.only(
        top: topPadding + 20,
        left: 20,
        right: 20,
        bottom: 20,
      ),
      decoration: BoxDecoration(
        color: headerBg,
        borderRadius: const BorderRadius.vertical(
          bottom: Radius.circular(24),
        ),
        boxShadow: shrinkOffset > 0
            ? [
                BoxShadow(
                    color: Colors.black.withOpacity(0.12),
                    blurRadius: 8,
                    offset: const Offset(0, 4))
              ]
            : [],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Menu',
                  style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Colors.white)),
              const SizedBox(height: 4),
              if (aktifUser != null)
                Row(children: [
                  const Icon(Icons.person_rounded,
                      size: 13, color: Colors.white70),
                  const SizedBox(width: 4),
                  Text(aktifUser.name,
                      style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(isAdmin ? 'Admin' : 'Kasir',
                        style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                  ),
                ]),
            ],
          ),
          GestureDetector(
            onTap: onLogout,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(children: [
                Icon(Icons.logout_rounded, size: 16, color: Colors.white),
                SizedBox(width: 4),
                Text('Logout',
                    style: TextStyle(
                        fontSize: 12,
                        color: Colors.white,
                        fontWeight: FontWeight.w700)),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _MenuCard extends StatelessWidget {
  final IconData? icon;
  final String? imagePath;
  final String label;
  final String description;
  final Color color;
  final VoidCallback onTap;

  const _MenuCard({
    this.icon,
    this.imagePath,
    required this.label,
    required this.description,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppColors.darkCard : Colors.white;
    final descColor = isDark ? const Color(0xFF94A3B8) : AppColors.textSecondary;

    return Material(
      color: cardBg,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? AppColors.darkBorder : AppColors.border,
              width: 0.5,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 64,
                height: 64,
                padding: imagePath != null ? EdgeInsets.zero : const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: imagePath != null
                    ? Image.asset(imagePath!, fit: BoxFit.contain)
                    : Icon(icon ?? Icons.apps, color: color, size: 28),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 9.5,
                      color: descColor,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Custom Bottom Nav Bar ────────────────────────────────────────────────────

class _BottomNavBar extends StatelessWidget {
  final int currentIndex;
  final WidgetRef ref;

  const _BottomNavBar({
    required this.currentIndex,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final navBg = isDark ? const Color(0xFF134E4A) : AppColors.primary;
    final shadowColor = Colors.black.withOpacity(isDark ? 0.35 : 0.15);
    final inactiveColor = Colors.white.withOpacity(0.65);

    final isAdmin = ref.read(isAdminProvider);

    const double barHeight = 72;
    const double fabSize = 58;
    const double floatHeadroom = 20;
    const double cornerRadius = 24;
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return SizedBox(
      height: barHeight + floatHeadroom + bottomInset,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: [
          Container(
            height: barHeight + bottomInset,
            padding: EdgeInsets.only(bottom: bottomInset),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: navBg,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(cornerRadius),
                topRight: Radius.circular(cornerRadius),
              ),
              boxShadow: [
                BoxShadow(
                  color: shadowColor,
                  blurRadius: 24,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: Row(
              children: [
                _NavItem(
                  index: 0,
                  current: currentIndex,
                  icon: Icons.home_outlined,
                  activeIcon: Icons.home_rounded,
                  label: 'Dashboard',
                  ref: ref,
                ),
                _NavItem(
                  index: 1,
                  current: currentIndex,
                  icon: Icons.insert_chart_outlined,
                  activeIcon: Icons.insert_chart_rounded,
                  label: 'Laporan',
                  ref: ref,
                ),
                const Expanded(child: SizedBox()),
                isAdmin
                    ? _NavItem(
                        index: 3,
                        current: currentIndex,
                        icon: Icons.inventory_2_outlined,
                        activeIcon: Icons.inventory_2_rounded,
                        label: 'Stok',
                        ref: ref,
                      )
                    : _NavItemBlocked(
                        icon: Icons.inventory_2_outlined,
                        label: 'Stok',
                      ),
                _NavItem(
                  index: 4,
                  current: currentIndex,
                  icon: Icons.grid_view_outlined,
                  activeIcon: Icons.grid_view_rounded,
                  label: 'Menu',
                  ref: ref,
                  onRetap: () {
                    if (_lainnyaNavKey.currentState?.canPop() ?? false) {
                      _lainnyaNavKey.currentState!.popUntil((route) => route.isFirst);
                    }
                  },
                ),
              ],
            ),
          ),
          Positioned(
            top: 0,
            child: GestureDetector(
              onTap: () =>
                  ref.read(currentNavIndexProvider.notifier).state = 2,
              behavior: HitTestBehavior.opaque,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: fabSize,
                    height: fabSize,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.25),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Icon(
                      Icons.qr_code_scanner_rounded,
                      color: AppColors.primary,
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Kasir',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: currentIndex == 2 ? Colors.white : inactiveColor,
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

// ─── Nav Item biasa ───────────────────────────────────────────────────────────

class _NavItem extends StatelessWidget {
  final int index, current;
  final IconData icon, activeIcon;
  final String label;
  final WidgetRef ref;
  final VoidCallback? onRetap;

  const _NavItem({
    required this.index,
    required this.current,
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.ref,
    this.onRetap,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = index == current;
    const inactiveColor = Colors.white;
    const inactiveOpacity = 0.65;
    final activeBg = Colors.white.withOpacity(0.18);

    return Expanded(
      child: GestureDetector(
        onTap: () {
          if (isActive) {
            onRetap?.call();
          } else {
            ref.read(currentNavIndexProvider.notifier).state = index;
          }
        },
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
              decoration: BoxDecoration(
                color: isActive ? activeBg : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                isActive ? activeIcon : icon,
                color: isActive
                    ? Colors.white
                    : inactiveColor.withOpacity(inactiveOpacity),
                size: 22,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                color: isActive
                    ? Colors.white
                    : inactiveColor.withOpacity(inactiveOpacity),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Kalkulator Dialog ────────────────────────────────────────────────────────

class _KalkulatorDialog extends StatefulWidget {
  const _KalkulatorDialog();
  @override
  State<_KalkulatorDialog> createState() => _KalkulatorDialogState();
}

class _KalkulatorDialogState extends State<_KalkulatorDialog> {
  String _display = '0';
  String _expr = '';
  double? _prev;
  String? _op;
  bool _newNum = true;

  void _press(String v) {
    setState(() {
      if (v == 'C') {
        _display = '0'; _expr = ''; _prev = null; _op = null; _newNum = true;
      } else if (v == '⌫') {
        if (_display.length > 1) {
          _display = _display.substring(0, _display.length - 1);
        } else {
          _display = '0';
        }
      } else if (['+', '-', '×', '÷'].contains(v)) {
        _prev = double.tryParse(_display);
        _op = v;
        _expr = '$_display $v';
        _newNum = true;
      } else if (v == '=') {
        if (_prev != null && _op != null) {
          final cur = double.tryParse(_display) ?? 0;
          double res = 0;
          if (_op == '+') res = _prev! + cur;
          if (_op == '-') res = _prev! - cur;
          if (_op == '×') res = _prev! * cur;
          if (_op == '÷') res = cur != 0 ? _prev! / cur : 0;
          _display = res == res.truncateToDouble()
              ? res.toInt().toString()
              : res.toStringAsFixed(4).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
          _expr = ''; _prev = null; _op = null; _newNum = true;
        }
      } else if (v == '.') {
        if (_newNum) { _display = '0.'; _newNum = false; }
        else if (!_display.contains('.')) _display += '.';
      } else {
        if (_newNum || _display == '0') { _display = v; _newNum = false; }
        else if (_display.length < 12) _display += v;
      }
    });
  }

  Widget _btn(String label, {Color? bg, Color? fg, int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: Material(
          color: bg ?? Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => _press(label),
            child: SizedBox(
              height: 52,
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: fg ?? AppColors.textPrimary,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Kalkulator',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkSurface : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(_expr,
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade500)),
                  const SizedBox(height: 4),
                  Text(_display,
                    style: const TextStyle(
                      fontSize: 34, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(children: [
              _btn('C', bg: AppColors.danger.withOpacity(0.12), fg: AppColors.danger),
              _btn('⌫', bg: AppColors.warning.withOpacity(0.12), fg: AppColors.warning),
              _btn('%', bg: Colors.grey.shade200),
              _btn('÷', bg: AppColors.primary.withOpacity(0.12), fg: AppColors.primary),
            ]),
            Row(children: [_btn('7'), _btn('8'), _btn('9'),
              _btn('×', bg: AppColors.primary.withOpacity(0.12), fg: AppColors.primary)]),
            Row(children: [_btn('4'), _btn('5'), _btn('6'),
              _btn('-', bg: AppColors.primary.withOpacity(0.12), fg: AppColors.primary)]),
            Row(children: [_btn('1'), _btn('2'), _btn('3'),
              _btn('+', bg: AppColors.primary.withOpacity(0.12), fg: AppColors.primary)]),
            Row(children: [
              _btn('0', flex: 2),
              _btn('.'),
              _btn('=', bg: AppColors.primary, fg: Colors.white),
            ]),
          ],
        ),
      ),
    );
  }
}

// ─── Nav Item Diblokir (untuk Kasir) ──────────────────────────────────────────

class _NavItemBlocked extends StatelessWidget {
  final IconData icon;
  final String label;

  const _NavItemBlocked({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(children: [
                Icon(Icons.lock_outline, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Text('Hanya Admin yang dapat mengakses Stok'),
              ]),
              backgroundColor: AppColors.danger,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
            ),
          );
        },
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
              child: Icon(icon, color: Colors.white.withOpacity(0.4), size: 22),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w500,
                color: Colors.white.withOpacity(0.4),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Guard Tab Stok ───────────────────────────────────────────────────────────

class _StokTabGuard extends ConsumerWidget {
  const _StokTabGuard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(isAdminProvider);
    if (isAdmin) {
      return const StokScreen();
    }
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.danger.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.lock_rounded,
                  size: 48, color: AppColors.danger),
            ),
            const SizedBox(height: 16),
            const Text('Akses Ditolak',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: AppColors.danger)),
            const SizedBox(height: 8),
            const Text('Halaman Stok hanya dapat diakses oleh Admin.',
                style: TextStyle(color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }
}

// ─── FITUR TABLET: Side Navigation Rail ───────────────────────────────────────

class _SideNavRail extends StatelessWidget {
  final int currentIndex;
  final WidgetRef ref;

  const _SideNavRail({
    required this.currentIndex,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final railBg = isDark ? const Color(0xFF134E4A) : AppColors.primary;
    final isAdmin = ref.read(isAdminProvider);
    final aktifUser = ref.watch(authProvider);

    return Container(
      width: 220,
      color: railBg,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.storefront_rounded,
                        color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('KasirKu',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 17)),
                        Text('Sistem Kasir Modern',
                            style: TextStyle(
                                color: Colors.white70, fontSize: 10)),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  _SideRailItem(
                    index: 0,
                    current: currentIndex,
                    icon: Icons.home_outlined,
                    activeIcon: Icons.home_rounded,
                    label: 'Dashboard',
                    ref: ref,
                  ),
                  _SideRailItem(
                    index: 2,
                    current: currentIndex,
                    icon: Icons.point_of_sale_outlined,
                    activeIcon: Icons.point_of_sale_rounded,
                    label: 'Kasir',
                    ref: ref,
                  ),
                  isAdmin
                      ? _SideRailItem(
                          index: 3,
                          current: currentIndex,
                          icon: Icons.inventory_2_outlined,
                          activeIcon: Icons.inventory_2_rounded,
                          label: 'Stok',
                          ref: ref,
                        )
                      : _SideRailItemBlocked(
                          icon: Icons.inventory_2_outlined,
                          label: 'Stok',
                        ),
                  _SideRailItem(
                    index: 1,
                    current: currentIndex,
                    icon: Icons.insert_chart_outlined,
                    activeIcon: Icons.insert_chart_rounded,
                    label: 'Laporan',
                    ref: ref,
                  ),
                  _SideRailItem(
                    index: 4,
                    current: currentIndex,
                    icon: Icons.grid_view_outlined,
                    activeIcon: Icons.grid_view_rounded,
                    label: 'Menu Lainnya',
                    ref: ref,
                    onRetap: () {
                      if (_lainnyaNavKey.currentState?.canPop() ?? false) {
                        _lainnyaNavKey.currentState!
                            .popUntil((route) => route.isFirst);
                      }
                    },
                  ),
                ],
              ),
            ),

            Container(
              margin: const EdgeInsets.all(12),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: Colors.white.withOpacity(0.2),
                    child: const Icon(Icons.person_rounded,
                        color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          aktifUser?.name ?? 'Pengguna',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                              fontSize: 12),
                        ),
                        Text(
                          isAdmin ? 'Admin' : 'Kasir',
                          style: const TextStyle(
                              color: Colors.white60, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SideRailItem extends StatelessWidget {
  final int index;
  final int current;
  final IconData icon;
  final IconData activeIcon;
  final String label;
  final WidgetRef ref;
  final VoidCallback? onRetap;

  const _SideRailItem({
    required this.index,
    required this.current,
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.ref,
    this.onRetap,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = current == index;
    final fgColor = isActive ? Colors.white : Colors.white.withOpacity(0.7);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () {
            if (isActive && onRetap != null) {
              onRetap!();
            } else {
              ref.read(currentNavIndexProvider.notifier).state = index;
            }
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isActive ? Colors.white.withOpacity(0.16) : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(isActive ? activeIcon : icon, color: fgColor, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                      color: fgColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SideRailItemBlocked extends StatelessWidget {
  final IconData icon;
  final String label;

  const _SideRailItemBlocked({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(children: [
                Icon(Icons.lock_outline, color: Colors.white, size: 18),
                SizedBox(width: 8),
                Text('Hanya Admin yang dapat mengakses Stok'),
              ]),
              backgroundColor: AppColors.danger,
              behavior: SnackBarBehavior.floating,
              duration: Duration(seconds: 2),
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Icon(icon, color: Colors.white.withOpacity(0.35), size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withOpacity(0.35),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
