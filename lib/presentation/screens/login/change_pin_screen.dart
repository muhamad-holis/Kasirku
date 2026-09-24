// lib/presentation/screens/login/change_pin_screen.dart
//
// NEW SCREEN: Ditampilkan saat user.mustChangePin == true.
// User WAJIB ganti PIN sebelum bisa masuk ke aplikasi.
// Tidak ada tombol "Lewati".

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' hide Column;
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/pin_hasher.dart';
import '../../../data/database/app_database.dart';
import '../../providers/auth_provider.dart';
import '../../providers/database_provider.dart';
import '../../navigation/app_router.dart';

class ChangePinScreen extends ConsumerStatefulWidget {
  const ChangePinScreen({super.key});

  @override
  ConsumerState<ChangePinScreen> createState() => _ChangePinScreenState();
}

class _ChangePinScreenState extends ConsumerState<ChangePinScreen> {
  String _pin        = '';
  String _pinConfirm = '';
  int    _step       = 0; // 0 = buat PIN baru, 1 = konfirmasi
  bool   _saving     = false;
  String? _error;

  static const int _pinLength = 6;

  void _onKey(String d) {
    if (_step == 0) {
      if (_pin.length >= _pinLength) return;
      setState(() { _pin += d; _error = null; });
      if (_pin.length == _pinLength) {
        Future.delayed(const Duration(milliseconds: 200),
            () => setState(() => _step = 1));
      }
    } else {
      if (_pinConfirm.length >= _pinLength) return;
      setState(() { _pinConfirm += d; _error = null; });
      if (_pinConfirm.length == _pinLength) {
        Future.delayed(const Duration(milliseconds: 200), _save);
      }
    }
  }

  void _onDel() {
    if (_step == 0) {
      if (_pin.isEmpty) return;
      setState(() => _pin = _pin.substring(0, _pin.length - 1));
    } else {
      if (_pinConfirm.isEmpty) return;
      setState(() => _pinConfirm = _pinConfirm.substring(0, _pinConfirm.length - 1));
    }
  }

  Future<void> _save() async {
    if (_pin != _pinConfirm) {
      setState(() {
        _error = 'PIN tidak cocok. Ulangi dari awal.';
        _pin = '';
        _pinConfirm = '';
        _step = 0;
      });
      return;
    }

    setState(() => _saving = true);
    try {
      final user = ref.read(authProvider)!;
      final db   = ref.read(databaseProvider);

      // Update PIN + hapus flag mustChangePin
      final hashedPin = await compute(hashPinIsolate, PinHashArgs(_pin));
      await (db.update(db.users)..where((u) => u.id.equals(user.id))).write(
        UsersCompanion(
          pin: Value(hashedPin),
          mustChangePin: const Value(false),
          // Reset failed attempts juga
          failedAttempts: const Value(0),
          lockedUntil: const Value(null),
        ),
      );

      // Audit log
      await db.customStatement(
        "INSERT INTO audit_logs (user_id, action, description) "
        "VALUES (${user.id}, 'change_own_pin', 'Ganti PIN mandatory setelah reset admin')",
      );

      ref.read(authProvider.notifier).clearMustChangePin();

      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MainNavigation()),
      );
    } catch (e) {
      setState(() => _error = 'Gagal menyimpan PIN: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentPin = _step == 0 ? _pin : _pinConfirm;
    final title      = _step == 0 ? 'Buat PIN Baru' : 'Konfirmasi PIN';
    final subtitle   = _step == 0
        ? 'Admin telah mereset PIN Anda.\nBuat PIN baru yang aman (min. $_pinLength digit).'
        : 'Masukkan ulang PIN yang sama untuk konfirmasi.';

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 32),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.warning.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.lock_reset_rounded,
                    color: AppColors.warning, size: 48),
              ),
              const SizedBox(height: 20),
              Text(title,
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(subtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: AppColors.textSecondary, height: 1.5)),
              const SizedBox(height: 32),

              // Dot indicator
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_pinLength, (i) {
                  final filled = i < currentPin.length;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 120),
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    width: 16, height: 16,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: filled ? AppColors.primary : Colors.transparent,
                      border: Border.all(
                        color: filled
                            ? AppColors.primary : Colors.grey.shade300,
                        width: 2,
                      ),
                    ),
                  );
                }),
              ),

              if (_error != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(children: [
                    const Icon(Icons.error_outline,
                        color: AppColors.danger, size: 16),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_error!,
                        style: const TextStyle(
                            color: AppColors.danger, fontSize: 12))),
                  ]),
                ),
              ],

              const Spacer(),
              _saving
                  ? const CircularProgressIndicator(color: AppColors.primary)
                  : _buildNumpad(),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNumpad() {
    const rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['', '0', '⌫'],
    ];
    return Column(
      children: rows.map((row) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: row.map((k) {
          if (k.isEmpty) return const SizedBox(width: 88, height: 60);
          return GestureDetector(
            onTap: k == '⌫' ? _onDel : () => _onKey(k),
            child: Container(
              width: 88, height: 60,
              alignment: Alignment.center,
              child: k == '⌫'
                  ? const Icon(Icons.backspace_outlined,
                      color: AppColors.primary, size: 22)
                  : Text(k, style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w700)),
            ),
          );
        }).toList(),
      )).toList(),
    );
  }
}
