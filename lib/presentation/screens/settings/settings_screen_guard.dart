// lib/presentation/screens/settings/settings_screen_guard.dart
//
// SECURITY PATCH: Wrapper guard untuk SettingsScreen.
// Import file ini dan gunakan SettingsScreenGuard sebagai pengganti SettingsScreen
// langsung di navigation.
//
// Cara pakai (di app_router.dart / _LainnyaHomeScreen):
//   child: const SettingsScreenGuard()   // bukan const SettingsScreen()

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/app_theme.dart';
import '../../providers/auth_provider.dart';
import 'settings_screen.dart';

/// Guard wrapper: hanya render SettingsScreen jika user adalah admin.
/// Jika bukan admin, tampilkan AccessDenied.
class SettingsScreenGuard extends ConsumerWidget {
  const SettingsScreenGuard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(isAdminProvider);
    if (!isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Pengaturan')),
        body: const Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.block_rounded, size: 64, color: AppColors.danger),
            SizedBox(height: 16),
            Text('Akses Ditolak',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800,
                    color: AppColors.danger)),
            SizedBox(height: 8),
            Text('Halaman Pengaturan hanya untuk Admin.',
                style: TextStyle(color: AppColors.textSecondary)),
          ]),
        ),
      );
    }
    return const SettingsScreen();
  }
}
