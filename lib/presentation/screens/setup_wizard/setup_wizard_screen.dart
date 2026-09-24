// lib/presentation/screens/setup_wizard/setup_wizard_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' hide Column;
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/pin_hasher.dart';
import '../../../data/database/app_database.dart';
import '../../providers/database_provider.dart';
import '../../providers/auth_provider.dart';
import '../login/login_screen.dart';

class SetupWizardScreen extends ConsumerStatefulWidget {
  const SetupWizardScreen({super.key});

  @override
  ConsumerState<SetupWizardScreen> createState() => _SetupWizardScreenState();
}

class _SetupWizardScreenState extends ConsumerState<SetupWizardScreen>
    with TickerProviderStateMixin {
  final _usernameCtrl     = TextEditingController();
  final _displayNameCtrl  = TextEditingController();
  final _pinCtrl          = TextEditingController();
  final _pinConfirmCtrl   = TextEditingController();

  bool    _saving           = false;
  bool    _pinVisible       = false;
  bool    _pinConfirmVisible = false;
  String? _error;
  int     _step             = 0;

  static const int _pinLength = 6;

  late final AnimationController _fadeCtrl;
  late final Animation<double>    _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 350));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeInOut);
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _usernameCtrl.dispose();
    _displayNameCtrl.dispose();
    _pinCtrl.dispose();
    _pinConfirmCtrl.dispose();
    super.dispose();
  }

  // ─── Validasi ──────────────────────────────────────────────────────────────

  String? _validateStep1() {
    final u = _usernameCtrl.text.trim().toLowerCase();
    final d = _displayNameCtrl.text.trim();
    if (u.length < 3) return 'Username minimal 3 karakter';
    if (!RegExp(r'^[a-z0-9_]+$').hasMatch(u))
      return 'Username hanya boleh huruf kecil, angka, dan underscore';
    if (d.isEmpty) return 'Nama tampilan tidak boleh kosong';
    return null;
  }

  String? _validateStep2() {
    if (_pinCtrl.text.trim().length < _pinLength)
      return 'PIN harus $_pinLength digit';
    return null;
  }

  String? _validateStep3() {
    if (_pinConfirmCtrl.text.trim().length < _pinLength)
      return 'Konfirmasi PIN harus $_pinLength digit';
    if (_pinCtrl.text.trim() != _pinConfirmCtrl.text.trim())
      return 'Konfirmasi PIN tidak cocok';
    return null;
  }

  // ─── Navigasi ──────────────────────────────────────────────────────────────

  void _next() {
    setState(() => _error = null);
    if (_step == 1) {
      final e = _validateStep1();
      if (e != null) { setState(() => _error = e); return; }
    }
    if (_step == 2) {
      final e = _validateStep2();
      if (e != null) { setState(() => _error = e); return; }
    }
    if (_step == 3) {
      final e = _validateStep3();
      if (e != null) { setState(() => _error = e); return; }
      _saveAdmin();
      return;
    }
    FocusScope.of(context).unfocus();
    _fadeCtrl.reset();
    setState(() => _step++);
    _fadeCtrl.forward();
  }

  void _back() {
    if (_step == 0) return;
    FocusScope.of(context).unfocus();
    _fadeCtrl.reset();
    setState(() {
      _step--;
      _error = null;
      if (_step == 2) { _pinCtrl.clear(); _pinConfirmCtrl.clear(); }
    });
    _fadeCtrl.forward();
  }

  // ─── Simpan ────────────────────────────────────────────────────────────────

  Future<void> _saveAdmin() async {
    setState(() { _saving = true; _error = null; });
    try {
      final db = ref.read(databaseProvider);
      final hashedPin = await compute(hashPinIsolate, PinHashArgs(_pinCtrl.text.trim()));
      await db.usersDao.insertFirstAdmin(UsersCompanion.insert(
        username:    _usernameCtrl.text.trim().toLowerCase(),
        displayName: _displayNameCtrl.text.trim(),
        pin:         hashedPin,
        role:        const Value('admin'),
      ));
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Akun admin berhasil dibuat. Silakan login.'),
        backgroundColor: AppColors.success,
      ));
    } on UsernameTakenException {
      setState(() => _error = 'Username sudah dipakai, coba yang lain');
    } on UnauthorizedException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Gagal menyimpan: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ─── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // ── Gradient background ──
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF0D9488),
                  Color(0xFF0F766E),
                  Color(0xFF134E4A),
                ],
              ),
            ),
          ),

          // ── Decorative circles ──
          Positioned(
            top: -60, right: -60,
            child: Container(
              width: 220, height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.06),
              ),
            ),
          ),
          Positioned(
            bottom: 100, left: -80,
            child: Container(
              width: 280, height: 280,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.04),
              ),
            ),
          ),

          // ── Content ──
          SafeArea(
            child: Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                  child: Column(
                    children: [
                      // FIX #1: Logo dari asset app_icon.png
                      Container(
                        width: 56, height: 56,
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: Colors.white.withOpacity(0.3), width: 1),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Image.asset(
                            'assets/images/app_icon.png',
                            width: 56, height: 56,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // FIX #2: Title konsisten w800
                      RichText(text: const TextSpan(children: [
                        TextSpan(text: 'Kasir',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          )),
                        TextSpan(text: 'Ku',
                          style: TextStyle(
                            color: Color(0xFF99F6E4),
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          )),
                      ])),
                      const SizedBox(height: 4),
                      Text('Setup Awal',
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.7),
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                      const SizedBox(height: 24),
                      _buildStepper(),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Card body
                Expanded(
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Color(0xFFF0FAFA),
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(32),
                        topRight: Radius.circular(32),
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(32),
                        topRight: Radius.circular(32),
                      ),
                      child: Column(
                        children: [
                          // Drag handle
                          const SizedBox(height: 12),
                          Container(
                            width: 40, height: 4,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade300,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(height: 20),

                          Expanded(
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.symmetric(horizontal: 24),
                              child: FadeTransition(
                                opacity: _fadeAnim,
                                child: _buildStep(),
                              ),
                            ),
                          ),

                          // Error
                          if (_error != null)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 24, vertical: 8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 14, vertical: 10),
                                decoration: BoxDecoration(
                                  color: AppColors.danger.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                      color: AppColors.danger.withOpacity(0.3)),
                                ),
                                child: Row(children: [
                                  const Icon(Icons.error_outline_rounded,
                                      color: AppColors.danger, size: 18),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(_error!,
                                        style: const TextStyle(
                                            color: AppColors.danger,
                                            fontSize: 13)),
                                  ),
                                ]),
                              ),
                            ),

                          // Actions
                          Padding(
                            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                            child: _buildActions(),
                          ),
                        ],
                      ),
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

  // ─── Stepper ───────────────────────────────────────────────────────────────

  Widget _buildStepper() {
    const labels = ['Mulai', 'Akun', 'PIN', 'Konfirmasi'];
    return Row(
      children: List.generate(labels.length, (i) {
        final done   = i < _step;
        final active = i == _step;
        return Expanded(
          child: Row(children: [
            Expanded(
              child: Column(children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                  width: 30, height: 30,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: done
                        ? Colors.white
                        : active
                            ? Colors.white
                            : Colors.white.withOpacity(0.2),
                    border: Border.all(
                      color: done || active
                          ? Colors.white
                          : Colors.white.withOpacity(0.3),
                      width: 2,
                    ),
                  ),
                  child: Center(
                    child: done
                        ? const Icon(Icons.check_rounded,
                            color: AppColors.primary, size: 16)
                        : Text('${i + 1}',
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                color: active
                                    ? AppColors.primary
                                    : Colors.white.withOpacity(0.6))),
                  ),
                ),
                const SizedBox(height: 4),
                Text(labels[i],
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: active
                            ? FontWeight.w700 : FontWeight.normal,
                        color: active
                            ? Colors.white
                            : Colors.white.withOpacity(0.6))),
              ]),
            ),
            if (i < labels.length - 1)
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  height: 2,
                  margin: const EdgeInsets.only(bottom: 20),
                  color: i < _step
                      ? Colors.white
                      : Colors.white.withOpacity(0.25),
                ),
              ),
          ]),
        );
      }),
    );
  }

  // ─── Step content ──────────────────────────────────────────────────────────

  Widget _buildStep() {
    switch (_step) {
      case 0:  return _buildStepInfo();
      case 1:  return _buildStepData();
      case 2:  return _buildStepPin();
      case 3:  return _buildStepConfirm();
      default: return const SizedBox();
    }
  }

  Widget _buildStepInfo() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Banner
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF0D9488), Color(0xFF0F766E)],
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withOpacity(0.3),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.admin_panel_settings_rounded,
                color: Colors.white, size: 32),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Selamat Datang!',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800)),
              SizedBox(height: 4),
              Text('Buat akun Admin utama\nuntuk mulai menggunakan KasirKu.',
                  style: TextStyle(
                      color: Colors.white70, fontSize: 12, height: 1.5)),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 24),

      const Text('Yang perlu kamu siapkan',
          style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary)),
      const SizedBox(height: 12),

      _featureCard(
        Icons.person_rounded,
        'Username Unik',
        'Dipakai untuk login, min. 3 karakter',
        AppColors.info,
      ),
      const SizedBox(height: 10),
      _featureCard(
        Icons.lock_rounded,
        'PIN 6 Digit',
        'Lebih aman dari PIN 4 digit biasa',
        AppColors.primary,
      ),
      const SizedBox(height: 10),
      _featureCard(
        Icons.security_rounded,
        'Tidak Ada Akun Bawaan',
        'Kamu yang tentukan credential-nya',
        AppColors.success,
      ),
      const SizedBox(height: 10),
      _featureCard(
        Icons.history_rounded,
        'Audit Log Otomatis',
        'Semua aksi tercatat secara otomatis',
        AppColors.warning,
      ),
      const SizedBox(height: 8),
    ]);
  }

  Widget _featureCard(IconData icon, String title, String sub, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(sub,
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary)),
          ]),
        ),
        Icon(Icons.check_circle_rounded,
            color: color.withOpacity(0.6), size: 18),
      ]),
    );
  }

  Widget _buildStepData() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _stepHeader(Icons.person_outline_rounded, 'Data Akun Admin',
          'Informasi ini digunakan untuk login setiap hari.'),
      const SizedBox(height: 24),

      _fieldLabel('Username', required: true),
      const SizedBox(height: 6),
      TextField(
        controller: _usernameCtrl,
        keyboardType: TextInputType.text,
        textInputAction: TextInputAction.next,
        autocorrect: false,
        onChanged: (_) => setState(() => _error = null),
        decoration: InputDecoration(
          hintText: 'Contoh: admin_toko',
          prefixIcon: const Icon(Icons.alternate_email_rounded,
              color: AppColors.primary, size: 20),
          helperText: 'Huruf kecil, angka, dan underscore saja',
          helperStyle: const TextStyle(fontSize: 11),
        ),
      ),
      const SizedBox(height: 20),

      _fieldLabel('Nama Tampilan', required: true),
      const SizedBox(height: 6),
      TextField(
        controller: _displayNameCtrl,
        textCapitalization: TextCapitalization.words,
        textInputAction: TextInputAction.done,
        onChanged: (_) => setState(() => _error = null),
        decoration: const InputDecoration(
          hintText: 'Contoh: Budi Santoso',
          prefixIcon: Icon(Icons.badge_rounded,
              color: AppColors.primary, size: 20),
          helperText: 'Nama yang muncul di tampilan aplikasi',
          helperStyle: TextStyle(fontSize: 11),
        ),
      ),
      const SizedBox(height: 8),

      // Tips box
      Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.info.withOpacity(0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.info.withOpacity(0.2)),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.lightbulb_outline_rounded,
              color: AppColors.info, size: 16),
          const SizedBox(width: 8),
          const Expanded(
            child: Text(
              'Username tidak bisa diubah setelah dibuat. Pilih yang mudah diingat.',
              style: TextStyle(
                  fontSize: 12, color: AppColors.info, height: 1.5),
            ),
          ),
        ]),
      ),
    ]);
  }

  Widget _buildStepPin() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _stepHeader(Icons.lock_outline_rounded, 'Buat PIN Admin',
          'PIN digunakan untuk login setiap hari. Jangan bagikan ke siapapun.'),
      const SizedBox(height: 24),

      _fieldLabel('PIN', required: true),
      const SizedBox(height: 6),
      TextField(
        controller: _pinCtrl,
        keyboardType: TextInputType.number,
        obscureText: !_pinVisible,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(_pinLength),
        ],
        textInputAction: TextInputAction.done,
        onChanged: (_) => setState(() => _error = null),
        decoration: InputDecoration(
          hintText: '6 digit angka',
          prefixIcon: const Icon(Icons.pin_rounded,
              color: AppColors.primary, size: 20),
          suffixIcon: IconButton(
            icon: Icon(
              _pinVisible
                  ? Icons.visibility_off_rounded
                  : Icons.visibility_rounded,
              color: AppColors.textSecondary, size: 20,
            ),
            onPressed: () => setState(() => _pinVisible = !_pinVisible),
          ),
          helperText: 'Minimal $_pinLength digit angka',
          helperStyle: const TextStyle(fontSize: 11),
        ),
      ),
      const SizedBox(height: 20),

      // Security tips
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.warning.withOpacity(0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.warning.withOpacity(0.25)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.shield_rounded, color: AppColors.warning, size: 16),
            SizedBox(width: 6),
            Text('Tips Keamanan PIN',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.warning)),
          ]),
          const SizedBox(height: 10),
          _tipItem('Jangan gunakan tanggal lahir atau nomor HP'),
          _tipItem('Jangan bagikan PIN ke siapapun termasuk kasir'),
          _tipItem('Ganti PIN secara berkala untuk keamanan'),
        ]),
      ),
    ]);
  }

  Widget _tipItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('• ',
            style: TextStyle(color: AppColors.warning, fontSize: 13)),
        Expanded(
          child: Text(text,
              style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.warning,
                  height: 1.4)),
        ),
      ]),
    );
  }

  Widget _buildStepConfirm() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _stepHeader(Icons.verified_user_rounded, 'Konfirmasi PIN',
          'Masukkan kembali PIN yang sama untuk memastikan tidak ada typo.'),
      const SizedBox(height: 24),

      _fieldLabel('Konfirmasi PIN', required: true),
      const SizedBox(height: 6),
      TextField(
        controller: _pinConfirmCtrl,
        keyboardType: TextInputType.number,
        obscureText: !_pinConfirmVisible,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(_pinLength),
        ],
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _next(),
        onChanged: (_) => setState(() => _error = null),
        decoration: InputDecoration(
          hintText: '6 digit angka',
          prefixIcon: const Icon(Icons.pin_rounded,
              color: AppColors.primary, size: 20),
          suffixIcon: IconButton(
            icon: Icon(
              _pinConfirmVisible
                  ? Icons.visibility_off_rounded
                  : Icons.visibility_rounded,
              color: AppColors.textSecondary, size: 20,
            ),
            onPressed: () =>
                setState(() => _pinConfirmVisible = !_pinConfirmVisible),
          ),
          helperText: 'Harus sama dengan PIN yang dibuat tadi',
          helperStyle: const TextStyle(fontSize: 11),
        ),
      ),
      const SizedBox(height: 20),

      // Summary card
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Row(children: [
            Icon(Icons.summarize_rounded,
                color: AppColors.primary, size: 16),
            SizedBox(width: 6),
            Text('Ringkasan Akun',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary)),
          ]),
          const Divider(height: 16),
          _summaryRow('Username',
              '@${_usernameCtrl.text.trim().toLowerCase()}'),
          const SizedBox(height: 8),
          _summaryRow('Nama Tampilan', _displayNameCtrl.text.trim()),
          const SizedBox(height: 8),
          _summaryRow('Role', 'Admin'),
          const SizedBox(height: 8),
          _summaryRow('PIN', '••••••'),
        ]),
      ),
    ]);
  }

  Widget _summaryRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 13, color: AppColors.textSecondary)),
        Text(value,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700)),
      ],
    );
  }

  // ─── Helpers ───────────────────────────────────────────────────────────────

  Widget _stepHeader(IconData icon, String title, String subtitle) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppColors.primary.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: AppColors.primary, size: 24),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(subtitle,
              style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textSecondary,
                  height: 1.4)),
        ]),
      ),
    ]);
  }

  Widget _fieldLabel(String label, {bool required = false}) {
    return Row(children: [
      Text(label,
          style: const TextStyle(
              fontSize: 13, fontWeight: FontWeight.w700)),
      if (required)
        const Text(' *',
            style: TextStyle(color: AppColors.danger, fontSize: 13)),
    ]);
  }

  // ─── Actions ───────────────────────────────────────────────────────────────

  Widget _buildActions() {
    return Row(children: [
      if (_step > 0) ...[
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _saving ? null : _back,
            icon: const Icon(Icons.arrow_back_rounded, size: 16),
            label: const Text('Kembali'),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.primary),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
        const SizedBox(width: 12),
      ],
      Expanded(
        flex: 2,
        child: ElevatedButton(
          onPressed: _saving ? null : _next,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
          ),
          child: _saving
              ? const SizedBox(
                  width: 20, height: 20,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2.5))
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _step == 0 ? 'Mulai Setup' :
                      _step == 1 ? 'Lanjut ke PIN' :
                      _step == 2 ? 'Lanjut' : 'Buat Akun Admin',
                      style: const TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      _step == 3
                          ? Icons.check_rounded
                          : Icons.arrow_forward_rounded,
                      size: 18,
                    ),
                  ],
                ),
        ),
      ),
    ]);
  }
}
