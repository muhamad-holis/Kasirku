// lib/presentation/screens/kasir_management/kasir_management_screen.dart
//
// SECURITY PATCH:
// - Guard: redirect ke AccessDeniedWidget jika bukan admin
// - insertUser/updateUser/softDeleteUser sekarang passing actorId
// - PIN minimum 6 digit (naik dari 4)
// - Cegah hapus admin terakhir (ditangani di DAO, tapi UI juga kasih info)
// - Username field untuk membedakan user dengan nama sama

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:drift/drift.dart' hide Column;

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/pin_hasher.dart';
import '../../../data/database/app_database.dart';
import '../../providers/auth_provider.dart';
import '../../providers/database_provider.dart';

class KasirManagementScreen extends ConsumerWidget {
  const KasirManagementScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // ── SECURITY GUARD: hanya admin ──────────────────────────────────────────
    final isAdmin = ref.watch(isAdminProvider);
    if (!isAdmin) return const _AccessDenied();

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final users  = ref.watch(allUsersProvider);

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.bg,
      appBar: AppBar(
        title: const Text('Kelola Kasir',
            style: TextStyle(fontWeight: FontWeight.w800)),
        backgroundColor: isDark ? AppColors.darkSurface : Colors.white,
        foregroundColor: isDark ? Colors.white : AppColors.textPrimary,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_rounded, color: AppColors.primary),
            onPressed: () => _showAddEdit(context, ref, null),
          ),
        ],
      ),
      body: users.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) {
          // Unauthorized: tampilkan akses ditolak
          if (e is UnauthorizedException) return const _AccessDenied();
          return Center(child: Text('Error: $e'));
        },
        data: (list) => list.isEmpty
            ? _Empty(isDark: isDark)
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) => _UserCard(
                  user: list[i],
                  isDark: isDark,
                  onEdit:     () => _showAddEdit(context, ref, list[i]),
                  onDelete:   () => _confirmDelete(context, ref, list[i]),
                  onResetPin: () => _showResetPin(context, ref, list[i]),
                ),
              ),
      ),
    );
  }

  void _showAddEdit(BuildContext context, WidgetRef ref, User? user) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ProviderScope(
        parent: ProviderScope.containerOf(context),
        child: _AddEditSheet(user: user),
      ),
    );
  }

  void _showResetPin(BuildContext context, WidgetRef ref, User user) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ProviderScope(
        parent: ProviderScope.containerOf(context),
        child: _ResetPinSheet(user: user),
      ),
    );
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, User user) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Hapus Kasir',
            style: TextStyle(fontWeight: FontWeight.w700)),
        content: Text(
            'Hapus akun "${user.displayName}"? Data transaksinya tetap tersimpan.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _doDelete(context, ref, user);
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.danger,
                foregroundColor: Colors.white),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
  }

  Future<void> _doDelete(
      BuildContext context, WidgetRef ref, User user) async {
    final actorId = ref.read(authProvider)!.id;
    try {
      await ref.read(databaseProvider).usersDao
          .softDeleteUser(user.id, actorId: actorId);
      ref.invalidate(allUsersProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Kasir dihapus'),
          backgroundColor: AppColors.success,
        ));
      }
    } on LastAdminException {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Minimal harus ada satu admin aktif'),
          backgroundColor: AppColors.danger,
        ));
      }
    } on UnauthorizedException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.message),
          backgroundColor: AppColors.danger,
        ));
      }
    }
  }
}

// ─── Access Denied Widget ─────────────────────────────────────────────────────

class _AccessDenied extends StatelessWidget {
  const _AccessDenied();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Akses Ditolak')),
      body: const Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.block_rounded, size: 64, color: AppColors.danger),
          SizedBox(height: 16),
          Text('Akses Ditolak',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800,
                  color: AppColors.danger)),
          SizedBox(height: 8),
          Text('Halaman ini hanya dapat diakses oleh Admin.',
              style: TextStyle(color: AppColors.textSecondary)),
        ]),
      ),
    );
  }
}

// ─── Card kasir ───────────────────────────────────────────────────────────────

class _UserCard extends StatelessWidget {
  final User user;
  final bool isDark;
  final VoidCallback onEdit, onDelete, onResetPin;
  const _UserCard({
    required this.user, required this.isDark,
    required this.onEdit, required this.onDelete,
    required this.onResetPin,
  });

  @override
  Widget build(BuildContext context) {
    final isAdmin   = user.role == 'admin';
    final roleColor = isAdmin ? AppColors.primary : AppColors.success;
    final roleLabel = isAdmin ? 'Admin' : 'Kasir';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDark ? AppColors.darkBorder : AppColors.border,
          width: 0.5,
        ),
      ),
      child: Row(children: [
        Container(
          width: 46, height: 46,
          decoration: BoxDecoration(
            color: roleColor.withOpacity(0.12), shape: BoxShape.circle),
          child: Center(
            child: Text(
              user.displayName.isNotEmpty
                  ? user.displayName[0].toUpperCase() : '?',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800,
                  color: roleColor),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text(user.displayName,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : AppColors.textPrimary)),
            const SizedBox(height: 2),
            Text('@${user.username}',
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 4),
            Row(children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: roleColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(roleLabel, style: TextStyle(
                    fontSize: 11, color: roleColor,
                    fontWeight: FontWeight.w700)),
              ),
              if (!user.isActive) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text('Nonaktif', style: TextStyle(
                      fontSize: 11, color: AppColors.danger,
                      fontWeight: FontWeight.w700)),
                ),
              ],
              if (user.mustChangePin) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.warning.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text('Ganti PIN', style: TextStyle(
                      fontSize: 11, color: AppColors.warning,
                      fontWeight: FontWeight.w700)),
                ),
              ],
            ]),
          ]),
        ),
        PopupMenuButton<String>(
          icon: Icon(Icons.more_vert_rounded,
              color: isDark
                  ? const Color(0xFF94A3B8) : AppColors.textSecondary),
          onSelected: (v) {
            if (v == 'edit')   onEdit();
            if (v == 'pin')    onResetPin();
            if (v == 'delete') onDelete();
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'edit',
                child: Row(children: [
                  Icon(Icons.edit_outlined, size: 18, color: AppColors.primary),
                  SizedBox(width: 8), Text('Edit nama & role'),
                ])),
            PopupMenuItem(value: 'pin',
                child: Row(children: [
                  Icon(Icons.lock_reset_rounded, size: 18,
                      color: AppColors.warning),
                  SizedBox(width: 8), Text('Reset PIN'),
                ])),
            PopupMenuItem(value: 'delete',
                child: Row(children: [
                  Icon(Icons.delete_outline, size: 18, color: AppColors.danger),
                  SizedBox(width: 8),
                  Text('Hapus', style: TextStyle(color: AppColors.danger)),
                ])),
          ],
        ),
      ]),
    );
  }
}

// ─── Sheet tambah / edit ──────────────────────────────────────────────────────

class _AddEditSheet extends ConsumerStatefulWidget {
  final User? user;
  const _AddEditSheet({this.user});

  @override
  ConsumerState<_AddEditSheet> createState() => _AddEditSheetState();
}

class _AddEditSheetState extends ConsumerState<_AddEditSheet> {
  final _usernameCtrl    = TextEditingController();
  final _displayNameCtrl = TextEditingController();
  final _pinCtrl         = TextEditingController();
  String _role = 'kasir';
  bool   _saving = false;
  bool   _pinVisible = false;

  // SECURITY: PIN min 6 digit
  static const int _pinLength = 6;

  bool get isEdit => widget.user != null;

  @override
  void initState() {
    super.initState();
    if (isEdit) {
      _usernameCtrl.text    = widget.user!.username;
      _displayNameCtrl.text = widget.user!.displayName;
      _role = widget.user!.role;
    }
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _displayNameCtrl.dispose();
    _pinCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final username    = _usernameCtrl.text.trim().toLowerCase();
    final displayName = _displayNameCtrl.text.trim();
    final pin         = _pinCtrl.text.trim();

    if (username.length < 3) {
      _snack('Username minimal 3 karakter'); return;
    }
    if (!RegExp(r'^[a-z0-9_]+$').hasMatch(username)) {
      _snack('Username hanya boleh huruf kecil, angka, underscore'); return;
    }
    if (displayName.isEmpty) {
      _snack('Nama tampilan tidak boleh kosong'); return;
    }
    if (!isEdit && pin.length < _pinLength) {
      _snack('PIN harus $_pinLength digit'); return;
    }
    if (!isEdit && !RegExp(r'^\d+$').hasMatch(pin)) {
      _snack('PIN hanya boleh angka'); return;
    }

    setState(() => _saving = true);
    final db      = ref.read(databaseProvider);
    final actorId = ref.read(authProvider)!.id;

    try {
      if (isEdit) {
        await db.usersDao.updateUser(
          UsersCompanion(
            id:          Value(widget.user!.id),
            username:    Value(username),
            displayName: Value(displayName),
            role:        Value(_role),
          ),
          actorId: actorId,
        );
      } else {
        final hashedPin = await compute(hashPinIsolate, PinHashArgs(pin));
        await db.usersDao.insertUser(
          UsersCompanion.insert(
            username:    username,
            displayName: displayName,
            pin:         hashedPin,
            role:        Value(_role),
          ),
          actorId: actorId,
        );
      }
      ref.invalidate(allUsersProvider);
      if (mounted) Navigator.pop(context);
    } on UsernameTakenException {
      _snack('Username "@$username" sudah dipakai');
    } on LastAdminException {
      _snack('Minimal harus ada satu admin aktif');
    } on UnauthorizedException catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack('Gagal menyimpan: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg), backgroundColor: AppColors.danger));
  }

  @override
  Widget build(BuildContext context) {
    final isDark  = Theme.of(context).brightness == Brightness.dark;
    final sheetBg = isDark ? AppColors.darkSurface : Colors.white;
    final text    = isDark ? Colors.white : AppColors.textPrimary;
    final bottom  = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: BoxDecoration(
        color: sheetBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(24, 12, 24, bottom > 0 ? bottom + 16 : 36),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 40, height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
                color: isDark ? AppColors.darkBorder : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2))),
          Text(isEdit ? 'Edit Kasir' : 'Tambah Kasir',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800,
                  color: text)),
          const SizedBox(height: 20),

          // Username
          TextField(
            controller: _usernameCtrl,
            autocorrect: false,
            enabled: !isEdit, // username tidak boleh diubah setelah dibuat
            decoration: InputDecoration(
              labelText: 'Username (unik)',
              hintText: 'contoh: budi_kasir',
              helperText: isEdit ? 'Username tidak dapat diubah' : null,
              prefixIcon: const Icon(Icons.alternate_email_rounded,
                  color: AppColors.primary),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 12),

          // Display name
          TextField(
            controller: _displayNameCtrl,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: 'Nama tampilan',
              prefixIcon: const Icon(Icons.person_outline_rounded,
                  color: AppColors.primary),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 16),

          // Role
          // BUG #1 FIX: Saat tambah user baru, hanya bisa pilih Kasir.
          // Admin tidak boleh membuat Admin baru — hanya bisa tambah Kasir.
          // Saat edit, role ditampilkan tapi tidak bisa diubah (readonly).
          Container(
            decoration: BoxDecoration(
              border: Border.all(
                  color: isDark ? AppColors.darkBorder : AppColors.border),
              borderRadius: BorderRadius.circular(12),
            ),
            child: isEdit
                // Mode edit: tampilkan role saat ini sebagai readonly
                ? Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    child: Row(children: [
                      Icon(
                        _role == 'admin'
                            ? Icons.admin_panel_settings_rounded
                            : Icons.badge_rounded,
                        color: _role == 'admin'
                            ? AppColors.primary : AppColors.success,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        'Role: ${_role == 'admin' ? 'Admin' : 'Kasir'}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _role == 'admin'
                              ? AppColors.primary : AppColors.success,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text('(tidak dapat diubah)',
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade500)),
                    ]),
                  )
                // Mode tambah baru: hanya tampilkan Kasir
                : RadioListTile<String>(
                    title: const Text('Kasir', style: TextStyle(fontSize: 14)),
                    subtitle: const Text('Admin hanya dapat menambah akun Kasir',
                        style: TextStyle(fontSize: 11)),
                    value: 'kasir',
                    groupValue: _role,
                    activeColor: AppColors.primary,
                    onChanged: (v) => setState(() => _role = v!),
                    dense: true,
                  ),
          ),

          // PIN hanya saat tambah baru
          if (!isEdit) ...[
            const SizedBox(height: 16),
            TextField(
              controller: _pinCtrl,
              keyboardType: TextInputType.number,
              obscureText: !_pinVisible,
              maxLength: _pinLength,
              decoration: InputDecoration(
                labelText: 'PIN ($_pinLength digit)',
                hintText: 'Masukkan PIN 6 angka',
                prefixIcon: const Icon(Icons.lock_outline_rounded,
                    color: AppColors.primary),
                suffixIcon: IconButton(
                  icon: Icon(
                    _pinVisible ? Icons.visibility_off : Icons.visibility,
                    color: AppColors.primary,
                  ),
                  onPressed: () => setState(() => _pinVisible = !_pinVisible),
                ),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
                counterText: '',
              ),
            ),
          ],

          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: _saving
                  ? const SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : Text(isEdit ? 'Simpan Perubahan' : 'Tambah Kasir',
                      style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ]),
      ),
    );
  }
}

// ─── Sheet reset PIN ──────────────────────────────────────────────────────────

class _ResetPinSheet extends ConsumerStatefulWidget {
  final User user;
  const _ResetPinSheet({required this.user});

  @override
  ConsumerState<_ResetPinSheet> createState() => _ResetPinSheetState();
}

class _ResetPinSheetState extends ConsumerState<_ResetPinSheet> {
  String _pin  = '';
  bool _saving = false;

  // SECURITY: PIN min 6 digit
  static const int _pinLength = 6;

  void _onKey(String d) {
    if (_pin.length >= _pinLength) return;
    setState(() => _pin += d);
  }

  void _onDel() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  Future<void> _save() async {
    if (_pin.length < _pinLength) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('PIN harus $_pinLength digit'),
          backgroundColor: AppColors.danger));
      return;
    }
    setState(() => _saving = true);
    try {
      final actorId = ref.read(authProvider)!.id;
      final hashedPin = await compute(hashPinIsolate, PinHashArgs(_pin));
      await ref.read(databaseProvider).usersDao.adminResetPin(
        widget.user.id,
        hashedPin,
        actorId: actorId,
      );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              'PIN ${widget.user.displayName} direset. User wajib ganti PIN saat login berikutnya.'),
          backgroundColor: AppColors.success,
        ));
      }
    } on UnauthorizedException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.message), backgroundColor: AppColors.danger));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Gagal: $e'), backgroundColor: AppColors.danger));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark  = Theme.of(context).brightness == Brightness.dark;
    final sheetBg = isDark ? AppColors.darkSurface : Colors.white;
    final text    = isDark ? Colors.white : AppColors.textPrimary;
    final bottom  = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: BoxDecoration(
        color: sheetBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(24, 12, 24, bottom > 0 ? bottom + 16 : 36),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 40, height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
                color: isDark ? AppColors.darkBorder : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2))),
          Text('Reset PIN — ${widget.user.displayName}',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800,
                  color: text)),
          const SizedBox(height: 4),
          const Text('User akan diwajibkan ganti PIN saat login berikutnya.',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              textAlign: TextAlign.center),
          const SizedBox(height: 20),
          Text('PIN baru (${_pin.length}/$_pinLength)',
              style: TextStyle(fontSize: 13,
                  color: isDark
                      ? const Color(0xFF94A3B8) : AppColors.textSecondary)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(_pinLength, (i) {
              final filled = i < _pin.length;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                margin: const EdgeInsets.symmetric(horizontal: 6),
                width: 14, height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: filled ? AppColors.primary : Colors.transparent,
                  border: Border.all(
                    color: filled
                        ? AppColors.primary
                        : isDark
                            ? const Color(0xFF475569) : Colors.grey.shade300,
                    width: 2,
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 16),
          _MiniNumpad(onKey: _onKey, onDel: _onDel),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: _saving
                  ? const SizedBox(width: 20, height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Text('Simpan PIN Baru',
                      style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ]),
      ),
    );
  }
}

// ─── Mini numpad ──────────────────────────────────────────────────────────────

class _MiniNumpad extends StatelessWidget {
  final void Function(String) onKey;
  final VoidCallback onDel;
  const _MiniNumpad({required this.onKey, required this.onDel});

  @override
  Widget build(BuildContext context) {
    const rows = [
      ['1','2','3'],
      ['4','5','6'],
      ['7','8','9'],
      ['','0','⌫'],
    ];
    return Column(
      children: rows.map((row) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: row.map((k) {
          if (k.isEmpty) return const SizedBox(width: 80, height: 52);
          return GestureDetector(
            onTap: k == '⌫' ? onDel : () => onKey(k),
            child: Container(
              width: 80, height: 52,
              alignment: Alignment.center,
              child: k == '⌫'
                  ? const Icon(Icons.backspace_outlined,
                      color: AppColors.primary, size: 20)
                  : Text(k, style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w700)),
            ),
          );
        }).toList(),
      )).toList(),
    );
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────────

class _Empty extends StatelessWidget {
  final bool isDark;
  const _Empty({required this.isDark});

  @override
  Widget build(BuildContext context) => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Icon(Icons.people_outline_rounded, size: 64,
          color: (isDark
              ? const Color(0xFF94A3B8) : AppColors.textSecondary)
                  .withOpacity(0.4)),
      const SizedBox(height: 12),
      Text('Belum ada kasir',
          style: TextStyle(
              color: isDark
                  ? const Color(0xFF94A3B8) : AppColors.textSecondary)),
    ]),
  );
}
