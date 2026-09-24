// lib/presentation/screens/splash/splash_screen.dart
//
// SECURITY PATCH:
// - Baca session dari flutter_secure_storage (bukan SharedPreferences)
// - Verifikasi session ke DB (cek user masih aktif)
// - Cek needsSetup → redirect ke SetupWizard jika DB kosong
// - Migrasi one-time dari SharedPrefs lama ke SecureStorage

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import '../../../core/theme/app_theme.dart';
import '../login/login_screen.dart';
import '../setup_wizard/setup_wizard_screen.dart';
import '../../navigation/app_router.dart';
import '../../providers/database_provider.dart';
import '../../providers/auth_provider.dart';
import '../../../core/utils/secure_session.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  late VideoPlayerController _videoController;
  bool _videoReady = false;
  bool _navigated  = false;

  @override
  void initState() {
    super.initState();
    _initVideo();
  }

  Future<void> _initVideo() async {
    // BUG-10 FIX: wrap seluruh inisialisasi video dalam try-catch.
    // Jika video gagal (file korup, codec tidak didukung, dsb), fallback
    // langsung ke _afterSplash dengan delay singkat agar user tidak terjebak
    // di layar hitam selamanya.
    try {
      _videoController = VideoPlayerController.asset('assets/videos/splash.mp4');
      await _videoController.initialize();

      if (mounted) {
        setState(() => _videoReady = true);
        _videoController.setLooping(false);
        _videoController.setVolume(1.0);
        _videoController.play();
      }

      _videoController.addListener(() {
        if (!_navigated &&
            _videoController.value.duration > Duration.zero &&
            _videoController.value.position >=
                _videoController.value.duration) {
          _afterSplash();
        }
      });

      // Fallback: jika video selesai tapi listener tidak terpanggil
      Future.delayed(const Duration(seconds: 5), _afterSplash);
    } catch (_) {
      // Video gagal diinisialisasi — langsung lanjut ke logika splash
      // tanpa menampilkan video sama sekali
      Future.delayed(const Duration(milliseconds: 300), _afterSplash);
    }
  }

  Future<void> _afterSplash() async {
    if (!mounted || _navigated) return;
    _navigated = true;

    // ── 1. Cek apakah DB perlu setup ──────────────────────────────────────
    final db = ref.read(databaseProvider);
    final needsSetup = await db.needsSetup();
    if (needsSetup) {
      // FIX: Hapus sisa session lama dari SecureStorage saat fresh install.
      // Android Auto Backup atau Keystore yang persisten bisa menyebabkan
      // session lama masih ada meski DB sudah terhapus saat uninstall.
      // Tanpa ini, session != null → app langsung ke LoginScreen, melewati
      // SetupWizard padahal tabel users sudah kosong.
      await SecureSession.clearSession();
      if (mounted) _navigate(const SetupWizardScreen());
      return;
    }

    // ── 2. Migrasi SharedPrefs → SecureStorage (one-time) ─────────────────
    await _migrateSharedPrefsIfNeeded();

    // ── 3. Baca session dari SecureStorage ────────────────────────────────
    final session = await SecureSession.getSession();

    // ── 4. Cek biometrik ──────────────────────────────────────────────────
    if (session != null) {
      final biometricOn = await _getBiometricSetting();
      if (biometricOn) {
        final ok = await _tryBiometric();
        if (!mounted) return;
        if (ok) {
          final restored = await ref.read(authProvider.notifier)
              .restoreSession(session);
          if (restored) { _navigate(const MainNavigation()); return; }
        }
      }
    }

    if (mounted) _navigate(const LoginScreen());
  }

  Future<bool> _getBiometricSetting() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('biometric_enabled') ?? false;
  }

  /// One-time migration: pindahkan last_user_* dari SharedPrefs ke SecureStorage
  Future<void> _migrateSharedPrefsIfNeeded() async {
    try {
      final existing = await SecureSession.getSession();
      if (existing != null) return; // sudah ada di secure storage

      final prefs    = await SharedPreferences.getInstance();
      final lastId   = prefs.getInt('last_user_id');
      final lastName = prefs.getString('last_user_name');
      final lastRole = prefs.getString('last_user_role');

      if (lastId != null && lastName != null && lastRole != null) {
        // BUG-11 FIX: ambil username dari DB menggunakan lastId agar tidak
        // salah derive (mis. "Budi Santoso" → "budi_santoso" tapi di DB "admin").
        // Jika DB lookup gagal, fallback ke derivasi nama sebagai last resort.
        final db = ref.read(databaseProvider);
        final user = await db.usersDao.getUserById(lastId);

        final username = user?.username ??
            lastName.toLowerCase().replaceAll(' ', '_');
        final displayName = user?.displayName ?? lastName;
        final role = user?.role ?? lastRole;

        await SecureSession.saveSession(
          userId:      lastId,
          username:    username,
          displayName: displayName,
          role:        role,
        );
        // Hapus dari SharedPrefs
        await prefs.remove('last_user_id');
        await prefs.remove('last_user_name');
        await prefs.remove('last_user_role');
      }
    } catch (_) {
      // Migrasi gagal tidak fatal — user cukup login ulang
    }
  }

  Future<bool> _tryBiometric() async {
    try {
      final auth = LocalAuthentication();
      if (!await auth.canCheckBiometrics) return false;
      if (!await auth.isDeviceSupported()) return false;
      final available = await auth.getAvailableBiometrics();
      if (available.isEmpty) return false;

      final hasFace = available.contains(BiometricType.face);
      final hasFP   = available.contains(BiometricType.fingerprint);
      String label = hasFace && hasFP
          ? 'Fingerprint / Face ID' : hasFace ? 'Face ID' : 'Fingerprint';

      return await auth.authenticate(
        localizedReason: 'Gunakan $label untuk masuk ke KasirKu',
        options: const AuthenticationOptions(
            stickyAuth: true, biometricOnly: true),
      );
    } catch (_) {
      return false;
    }
  }

  void _navigate(Widget screen) {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => screen,
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  @override
  void dispose() {
    _videoController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: _videoReady
          ? SizedBox.expand(
              child: FittedBox(
                fit: BoxFit.cover,
                child: SizedBox(
                  width:  _videoController.value.size.width,
                  height: _videoController.value.size.height,
                  child:  VideoPlayer(_videoController),
                ),
              ),
            )
          : const Center(
              child: CircularProgressIndicator(color: AppColors.primary)),
    );
  }
}
