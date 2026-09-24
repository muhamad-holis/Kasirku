import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../../../core/theme/app_theme.dart';
import '../../providers/settings_provider.dart';

class PaymentMethodScreen extends ConsumerStatefulWidget {
  const PaymentMethodScreen({super.key});

  @override
  ConsumerState<PaymentMethodScreen> createState() =>
      _PaymentMethodScreenState();
}

class _PaymentMethodScreenState extends ConsumerState<PaymentMethodScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? AppColors.darkBg : AppColors.bg,
      appBar: AppBar(
        title: const Text('Metode Pembayaran',
            style: TextStyle(fontWeight: FontWeight.w700)),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        bottom: TabBar(
          controller: _tab,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          indicatorWeight: 3,
          tabs: const [
            Tab(icon: Icon(Icons.qr_code), text: 'QRIS'),
            Tab(icon: Icon(Icons.account_balance), text: 'Rekening'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: const [
          _QrisTab(),
          _RekeningTab(),
        ],
      ),
    );
  }
}

// ─── Tab QRIS ─────────────────────────────────────────────────────────────────

class _QrisTab extends ConsumerWidget {
  const _QrisTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store   = ref.watch(storeSettingsProvider);
    final isDark  = Theme.of(context).brightness == Brightness.dark;
    final cardBg  = isDark ? AppColors.darkSurface : Colors.white;
    final subColor= isDark ? const Color(0xFF94A3B8) : AppColors.textSecondary;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Info
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(children: [
              const Icon(Icons.info_outline_rounded,
                  color: AppColors.primary, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Upload gambar QR code QRIS toko kamu. '
                  'Gambar akan ditampilkan otomatis saat customer memilih metode QRIS.',
                  style: TextStyle(fontSize: 12, color: AppColors.primary),
                ),
              ),
            ]),
          ),
          const SizedBox(height: 20),

          // Preview / Upload area
          GestureDetector(
            onTap: () => _pickQrisImage(context, ref),
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: store.qrisImagePath.isNotEmpty
                      ? AppColors.primary
                      : (isDark ? AppColors.darkBorder : Colors.grey.shade200),
                  width: store.qrisImagePath.isNotEmpty ? 2 : 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 8, offset: const Offset(0, 2)),
                ],
              ),
              child: store.qrisImagePath.isNotEmpty &&
                      File(store.qrisImagePath).existsSync()
                  ? Column(children: [
                      ClipRRect(
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(15)),
                        child: Image.file(
                          File(store.qrisImagePath),
                          width: double.infinity,
                          height: 300,
                          fit: BoxFit.contain,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.edit_rounded,
                                size: 16, color: AppColors.primary),
                            const SizedBox(width: 6),
                            Text('Tap untuk ganti gambar',
                                style: TextStyle(
                                    fontSize: 13, color: AppColors.primary,
                                    fontWeight: FontWeight.w500)),
                          ],
                        ),
                      ),
                    ])
                  : Padding(
                      padding: const EdgeInsets.symmetric(vertical: 48),
                      child: Column(children: [
                        Container(
                          width: 72, height: 72,
                          decoration: BoxDecoration(
                            color: AppColors.primaryLight,
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Icon(Icons.qr_code_2_rounded,
                              size: 40, color: AppColors.primary),
                        ),
                        const SizedBox(height: 14),
                        const Text('Upload Gambar QRIS',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        Text('Tap untuk pilih gambar dari galeri',
                            style: TextStyle(fontSize: 13, color: subColor)),
                      ]),
                    ),
            ),
          ),

          if (store.qrisImagePath.isNotEmpty) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.delete_outline_rounded,
                    color: AppColors.danger),
                label: const Text('Hapus Gambar QRIS',
                    style: TextStyle(color: AppColors.danger)),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppColors.danger),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => _deleteQrisImage(context, ref),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _pickQrisImage(BuildContext context, WidgetRef ref) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 90,
    );
    if (picked == null) return;

    // Simpan ke folder app
    final dir  = await getApplicationDocumentsDirectory();
    final dest = File('${dir.path}/qris_image.png');
    await File(picked.path).copy(dest.path);

    await ref.read(storeSettingsProvider.notifier).update(
          (s) => s.copyWith(qrisImagePath: dest.path),
        );

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Gambar QRIS berhasil disimpan'),
          backgroundColor: AppColors.success,
        ),
      );
    }
  }

  Future<void> _deleteQrisImage(BuildContext context, WidgetRef ref) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hapus Gambar QRIS?'),
        content: const Text(
            'Gambar QRIS akan dihapus. Metode QRIS tetap tersedia tapi tanpa tampilan QR.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.danger,
                foregroundColor: Colors.white),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final path = ref.read(storeSettingsProvider).qrisImagePath;
    if (path.isNotEmpty) {
      final file = File(path);
      if (await file.exists()) await file.delete();
    }

    await ref.read(storeSettingsProvider.notifier).update(
          (s) => s.copyWith(qrisImagePath: ''),
        );
  }
}

// ─── Tab Rekening ─────────────────────────────────────────────────────────────

class _RekeningTab extends ConsumerWidget {
  const _RekeningTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final store    = ref.watch(storeSettingsProvider);
    final accounts = store.bankAccounts;
    final isDark   = Theme.of(context).brightness == Brightness.dark;
    final subColor = isDark ? const Color(0xFF94A3B8) : AppColors.textSecondary;

    return Column(
      children: [
        // Info
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(children: [
              const Icon(Icons.info_outline_rounded,
                  color: AppColors.primary, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Tambah rekening bank atau e-wallet. '
                  'Info rekening akan ditampilkan saat customer memilih Transfer.',
                  style: TextStyle(fontSize: 12, color: AppColors.primary),
                ),
              ),
            ]),
          ),
        ),

        // List rekening
        Expanded(
          child: accounts.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.account_balance_outlined,
                          size: 64,
                          color: isDark
                              ? AppColors.darkBorder
                              : Colors.grey.shade300),
                      const SizedBox(height: 12),
                      Text('Belum ada rekening',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: subColor)),
                      const SizedBox(height: 6),
                      Text('Tap tombol + untuk tambah rekening',
                          style:
                              TextStyle(fontSize: 13, color: subColor)),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: accounts.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, i) =>
                      _RekeningCard(account: accounts[i], index: i),
                ),
        ),

        // Tombol tambah
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.add_rounded),
              label: const Text('Tambah Rekening'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () => _showAddDialog(context, ref),
            ),
          ),
        ),
      ],
    );
  }

  void _showAddDialog(BuildContext context, WidgetRef ref,
      {BankAccount? existing}) {
    final isEdit        = existing != null;
    final bankCtrl      = TextEditingController(text: existing?.bankName ?? '');
    final noRekCtrl     = TextEditingController(
        text: existing?.accountNumber ?? '');
    final holderCtrl    = TextEditingController(
        text: existing?.accountHolder ?? '');

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(isEdit ? 'Edit Rekening' : 'Tambah Rekening',
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w800)),
              const SizedBox(height: 20),

              // Dropdown bank populer
              _BankDropdownField(controller: bankCtrl),
              const SizedBox(height: 12),

              TextField(
                controller: noRekCtrl,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: const InputDecoration(
                  labelText: 'Nomor Rekening / No. HP',
                  prefixIcon: Icon(Icons.tag_rounded),
                ),
              ),
              const SizedBox(height: 12),

              TextField(
                controller: holderCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Nama Pemilik Rekening',
                  prefixIcon: Icon(Icons.person_outline_rounded),
                ),
              ),
              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    final bank   = bankCtrl.text.trim();
                    final noRek  = noRekCtrl.text.trim();
                    final holder = holderCtrl.text.trim();

                    if (bank.isEmpty || noRek.isEmpty || holder.isEmpty) {
                      ScaffoldMessenger.of(ctx).showSnackBar(
                        const SnackBar(
                            content: Text('Semua field wajib diisi'),
                            backgroundColor: AppColors.danger),
                      );
                      return;
                    }

                    final account = BankAccount(
                      id:            existing?.id ?? const Uuid().v4(),
                      bankName:      bank,
                      accountNumber: noRek,
                      accountHolder: holder,
                    );

                    final store    = ref.read(storeSettingsProvider);
                    List<BankAccount> updated;
                    if (isEdit) {
                      updated = store.bankAccounts
                          .map((a) => a.id == account.id ? account : a)
                          .toList();
                    } else {
                      updated = [...store.bankAccounts, account];
                    }

                    ref.read(storeSettingsProvider.notifier).update(
                          (s) => s.copyWith(bankAccounts: updated),
                        );

                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(isEdit
                            ? 'Rekening berhasil diperbarui'
                            : 'Rekening berhasil ditambahkan'),
                        backgroundColor: AppColors.success,
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(isEdit ? 'Simpan Perubahan' : 'Tambah'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Rekening Card ────────────────────────────────────────────────────────────

class _RekeningCard extends ConsumerWidget {
  final BankAccount account;
  final int index;
  const _RekeningCard({required this.account, required this.index});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark  = Theme.of(context).brightness == Brightness.dark;
    final cardBg  = isDark ? AppColors.darkSurface : Colors.white;

    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2)),
        ],
      ),
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: AppColors.primaryLight,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.account_balance_rounded,
              color: AppColors.primary, size: 22),
        ),
        title: Text(account.bankName,
            style: const TextStyle(
                fontWeight: FontWeight.w700, fontSize: 14)),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(account.accountNumber,
                style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    letterSpacing: 1)),
            Text('a/n ${account.accountHolder}',
                style: TextStyle(fontSize: 12,
                    color: isDark
                        ? const Color(0xFF94A3B8)
                        : AppColors.textSecondary)),
          ],
        ),
        trailing: PopupMenuButton<String>(
          onSelected: (val) {
            if (val == 'edit') {
              _showEditDialog(context, ref);
            } else if (val == 'delete') {
              _delete(context, ref);
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(
                value: 'edit',
                child: Row(children: [
                  Icon(Icons.edit_rounded, size: 18),
                  SizedBox(width: 8),
                  Text('Edit'),
                ])),
            const PopupMenuItem(
                value: 'delete',
                child: Row(children: [
                  Icon(Icons.delete_outline_rounded,
                      size: 18, color: AppColors.danger),
                  SizedBox(width: 8),
                  Text('Hapus',
                      style: TextStyle(color: AppColors.danger)),
                ])),
          ],
        ),
      ),
    );
  }

  void _showEditDialog(BuildContext context, WidgetRef ref) {
    // Reuse fungsi dari _RekeningTab
    final tab = const _RekeningTab();
    tab._showAddDialog(context, ref, existing: account);
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hapus Rekening?'),
        content: Text(
            'Rekening ${account.bankName} - ${account.accountNumber} akan dihapus.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.danger,
                foregroundColor: Colors.white),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final store = ref.read(storeSettingsProvider);
    final updated =
        store.bankAccounts.where((a) => a.id != account.id).toList();
    ref
        .read(storeSettingsProvider.notifier)
        .update((s) => s.copyWith(bankAccounts: updated));
  }
}

// ─── Bank Dropdown ────────────────────────────────────────────────────────────

class _BankDropdownField extends StatefulWidget {
  final TextEditingController controller;
  const _BankDropdownField({required this.controller});

  @override
  State<_BankDropdownField> createState() => _BankDropdownFieldState();
}

class _BankDropdownFieldState extends State<_BankDropdownField> {
  static const _banks = [
    'BCA', 'BRI', 'BNI', 'Mandiri', 'BSI', 'CIMB Niaga',
    'Danamon', 'Permata', 'BTN', 'Bank Jago',
    'GoPay', 'OVO', 'Dana', 'ShopeePay', 'LinkAja',
    'SeaBank', 'Jenius',
  ];

  @override
  Widget build(BuildContext context) {
    return Autocomplete<String>(
      optionsBuilder: (textEditingValue) {
        if (textEditingValue.text.isEmpty) return _banks;
        return _banks.where((b) => b
            .toLowerCase()
            .contains(textEditingValue.text.toLowerCase()));
      },
      onSelected: (val) => widget.controller.text = val,
      fieldViewBuilder: (_, ctrl, focusNode, __) {
        // Sync controller
        ctrl.text = widget.controller.text;
        ctrl.addListener(() => widget.controller.text = ctrl.text);
        return TextField(
          controller: ctrl,
          focusNode: focusNode,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Bank / E-Wallet',
            prefixIcon: Icon(Icons.account_balance_rounded),
            hintText: 'Pilih atau ketik nama bank',
          ),
        );
      },
    );
  }
}
