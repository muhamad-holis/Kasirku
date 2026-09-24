import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:local_auth/local_auth.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/currency.dart';
import '../../providers/settings_provider.dart';
import '../../providers/database_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/backup_provider.dart';
import '../../providers/update_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // BUG #2 FIX: Guard — hanya Admin yang boleh akses Settings.
    // Kasir yang masuk lewat shortcut dashboard akan lihat halaman akses ditolak.
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
            Text('Pengaturan hanya dapat diakses oleh Admin.',
                style: TextStyle(color: AppColors.textSecondary)),
          ]),
        ),
      );
    }

    final isDark        = ref.watch(themeModeProvider);
    final store         = ref.watch(storeSettingsProvider);
    final printer       = ref.watch(printerSettingsProvider);
    final pinValue      = ref.watch(pinProvider);
    final pinActive     = pinValue != null && pinValue.isNotEmpty;
    final biometricOn   = ref.watch(biometricProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pengaturan',
            style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [

          // ── Tampilan ──────────────────────────────────────
          _Section('Tampilan', [
            SwitchListTile(
              title: const Text('Mode Gelap',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              subtitle: const Text('Aktifkan tema gelap',
                  style: TextStyle(fontSize: 12)),
              value: isDark,
              onChanged: (_) =>
                  ref.read(themeModeProvider.notifier).toggle(),
              secondary: _TileIcon(
                  Icons.dark_mode_outlined, AppColors.primary),
            ),
          ]),

          // ── Toko ──────────────────────────────────────────
          _Section('Toko', [
            _Tile(
              icon: Icons.store_outlined,
              title: 'Nama Toko',
              subtitle: store.storeName.isEmpty
                  ? 'Belum diset' : store.storeName,
              onTap: () => _editField(
                context, ref,
                label: 'Nama Toko',
                value: store.storeName,
                onSave: (v) => ref.read(storeSettingsProvider.notifier)
                    .update((s) => s.copyWith(storeName: v)),
              ),
            ),
            _Tile(
              icon: Icons.location_on_outlined,
              title: 'Alamat Toko',
              subtitle: store.storeAddress.isEmpty
                  ? 'Belum diset' : store.storeAddress,
              onTap: () => _editField(
                context, ref,
                label: 'Alamat Toko',
                value: store.storeAddress,
                maxLines: 3,
                onSave: (v) => ref.read(storeSettingsProvider.notifier)
                    .update((s) => s.copyWith(storeAddress: v)),
              ),
            ),
            _Tile(
              icon: Icons.phone_outlined,
              title: 'Nomor Telepon',
              subtitle: store.storePhone.isEmpty
                  ? 'Belum diset' : store.storePhone,
              onTap: () => _editField(
                context, ref,
                label: 'Nomor Telepon',
                value: store.storePhone,
                keyboardType: TextInputType.phone,
                onSave: (v) => ref.read(storeSettingsProvider.notifier)
                    .update((s) => s.copyWith(storePhone: v)),
              ),
            ),
          ]),

          // ── Struk ─────────────────────────────────────────
          _Section('Struk', [
            _Tile(
              icon: Icons.receipt_long_outlined,
              title: 'Catatan Struk',
              subtitle: store.storeNote.isEmpty
                  ? 'Belum diset' : store.storeNote,
              onTap: () => _editField(
                context, ref,
                label: 'Catatan di bawah struk',
                value: store.storeNote,
                maxLines: 3,
                onSave: (v) => ref.read(storeSettingsProvider.notifier)
                    .update((s) => s.copyWith(storeNote: v)),
              ),
            ),
            _Tile(
              icon: Icons.straighten_outlined,
              title: 'Ukuran Kertas',
              subtitle: store.receiptSize,
              onTap: () => _pickReceiptSize(context, ref, store),
            ),
            SwitchListTile(
              title: const Text('Tampilkan Logo',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              subtitle: const Text('Cetak logo toko di bagian atas struk',
                  style: TextStyle(fontSize: 12)),
              value: store.showLogo,
              onChanged: (v) =>
                  ref.read(storeSettingsProvider.notifier)
                      .update((s) => s.copyWith(showLogo: v)),
              secondary: _TileIcon(
                  Icons.image_outlined, AppColors.primary),
            ),
            _Tile(
              icon: Icons.add_photo_alternate_outlined,
              title: 'Ganti Logo Struk',
              subtitle: store.logoPath.isNotEmpty
                  ? 'Logo custom aktif — ketuk untuk ganti'
                  : 'Gunakan gambar dari galeri',
              color: store.logoPath.isNotEmpty
                  ? AppColors.success : AppColors.primary,
              onTap: () => _ggantiLogo(context, ref),
            ),
            SwitchListTile(
              title: const Text('Cetak Otomatis',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
              subtitle: const Text('Print struk setelah transaksi',
                  style: TextStyle(fontSize: 12)),
              value: store.printAfterTransaction,
              onChanged: (v) =>
                  ref.read(storeSettingsProvider.notifier)
                      .update((s) =>
                          s.copyWith(printAfterTransaction: v)),
              secondary: _TileIcon(
                  Icons.print_outlined, AppColors.primary),
            ),
            _Tile(
              icon: Icons.preview_outlined,
              title: 'Preview Struk',
              subtitle: 'Lihat contoh tampilan struk',
              onTap: () => _showReceiptPreview(context, store),
            ),
          ]),

          // ── Printer ───────────────────────────────────────
          _Section('Printer Bluetooth', [
            if (printer.deviceName != null) ...[
              ListTile(
                leading: _TileIcon(
                    Icons.bluetooth_connected, AppColors.success),
                title: Text(printer.deviceName!,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14)),
                subtitle: Text(printer.deviceAddress ?? '',
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade500)),
                trailing: TextButton(
                  onPressed: () => ref
                      .read(printerSettingsProvider.notifier)
                      .clearPrinter(),
                  child: const Text('Putus',
                      style: TextStyle(color: AppColors.danger)),
                ),
              ),
            ],
            _Tile(
              icon: printer.deviceName != null
                  ? Icons.bluetooth_searching
                  : Icons.bluetooth_outlined,
              title: printer.deviceName != null
                  ? 'Ganti Printer'
                  : 'Hubungkan Printer',
              subtitle: 'Cari printer Bluetooth thermal',
              onTap: () => _showBluetoothScanner(context, ref),
            ),
            _Tile(
              icon: Icons.print_outlined,
              title: 'Test Print',
              subtitle: 'Cetak struk uji coba',
              color: AppColors.primary,
              onTap: () {
                if (printer.deviceName == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Hubungkan printer Bluetooth terlebih dahulu'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                } else {
                  _testPrint(context, ref, store);
                }
              },
            ),
          ]),

          // ── Keamanan ──────────────────────────────────────
          _Section('Keamanan', [
            _Tile(
              icon: pinActive
                  ? Icons.lock_rounded
                  : Icons.lock_outline,
              title: 'PIN Aplikasi',
              subtitle: pinActive
                  ? 'Aktif — ketuk untuk ubah atau nonaktifkan'
                  : 'Belum diaktifkan',
              color: pinActive ? AppColors.success : null,
              onTap: () => _showPinSetup(context, ref, isPinActive: pinActive),
            ),
            _SwitchTile(
              icon: Icons.fingerprint_outlined,
              title: 'Biometrik',
              subtitle: biometricOn
                  ? 'Aktif — login pakai fingerprint/Face ID'
                  : 'Fingerprint / Face ID',
              color: biometricOn ? AppColors.success : null,
              value: biometricOn,
              onChanged: (val) => _toggleBiometric(context, ref, val),
            ),
          ]),

          // ── Data ──────────────────────────────────────────
          _Section('Data', [
            _Tile(
              icon: Icons.backup_outlined,
              title: 'Backup Data',
              subtitle: 'Ekspor database ke file',
              color: AppColors.primary,
              onTap: () => _backupData(context, ref),
            ),
            _Tile(
              icon: Icons.restore_outlined,
              title: 'Restore Backup',
              subtitle: 'Import file backup .db',
              color: AppColors.info,
              onTap: () => _restoreBackup(context, ref),
            ),
            _Tile(
              icon: Icons.delete_forever_outlined,
              title: 'Hapus Semua Data',
              subtitle: 'Hapus semua transaksi & stok',
              color: AppColors.danger,
              onTap: () => _confirmReset(context, ref),
            ),
          ]),

          // ── Backup & Restore ───────────────────────────────
          _Section('Backup & Restore', [
            _BackupTile(),
          ]),

          // ── Tentang ───────────────────────────────────────
          _Section('Tentang', [
            _Tile(
              icon: Icons.info_outline_rounded,
              title: 'Tentang Aplikasi',
              subtitle: 'Versi, lisensi & informasi app',
              color: AppColors.primary,
              onTap: () => _showAbout(context),
            ),
            _Tile(
              icon: Icons.system_update_rounded,
              title: 'Cek Update',
              subtitle: 'Periksa versi terbaru aplikasi',
              color: AppColors.primary,
              onTap: () => _showUpdateSheet(context, ref),
            ),
          ]),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ── Edit field dialog ──────────────────────────────────────────────────────

  void _editField(
    BuildContext context,
    WidgetRef ref, {
    required String label,
    required String value,
    required Future<void> Function(String) onSave,
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
  }) {
    final ctrl = TextEditingController(text: value);
    showDialog(
      context: context,
      // FIX: Gunakan 'dialogCtx' (context milik dialog itu sendiri) untuk
      // Navigator.pop, bukan 'context' dari luar (Settings screen).
      // Bug sebelumnya: Simpan memanggil pop pada context yang salah sehingga
      // dialog tidak tertutup, seolah tidak terjadi apapun padahal data
      // sudah tersimpan ke database.
      builder: (dialogCtx) => AlertDialog(
        title: Text(label,
            style: const TextStyle(fontWeight: FontWeight.w700)),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: maxLines,
          keyboardType: keyboardType,
          decoration: InputDecoration(labelText: label),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Batal')),
          ElevatedButton(
              onPressed: () async {
                await onSave(ctrl.text.trim());
                if (dialogCtx.mounted) Navigator.pop(dialogCtx);
              },
              child: const Text('Simpan')),
        ],
      ),
    );
  }

  // ── Pick receipt size ──────────────────────────────────────────────────────

  void _pickReceiptSize(
      BuildContext context, WidgetRef ref, StoreSettings store) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Ukuran Kertas Struk',
                style: TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 16),
            for (final size in ['58mm', '80mm'])
              ListTile(
                title: Text(size),
                subtitle: Text(size == '58mm'
                    ? 'Printer thermal standar'
                    : 'Printer thermal lebar'),
                leading: Radio<String>(
                  value: size,
                  groupValue: store.receiptSize,
                  onChanged: (v) {
                    ref.read(storeSettingsProvider.notifier)
                        .update((s) =>
                            s.copyWith(receiptSize: v));
                    Navigator.pop(context);
                  },
                  activeColor: AppColors.primary,
                ),
                onTap: () {
                  ref.read(storeSettingsProvider.notifier)
                      .update((s) => s.copyWith(receiptSize: size));
                  Navigator.pop(context);
                },
              ),
          ],
        ),
      ),
    );
  }

  // ── Receipt preview ────────────────────────────────────────────────────────

  void _showReceiptPreview(
      BuildContext context, StoreSettings store) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        builder: (_, ctrl) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Row(children: [
                const Expanded(
                  child: Text('Preview Struk',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 16))),
                IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context)),
              ]),
            ),
            Expanded(
              child: SingleChildScrollView(
                controller: ctrl,
                padding: const EdgeInsets.all(20),
                child: Center(
                  child: Container(
                    width: store.receiptSize == '58mm' ? 220 : 300,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                    child: _ReceiptPreview(store: store),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Bluetooth scanner ──────────────────────────────────────────────────────

  void _showBluetoothScanner(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => ProviderScope(
        parent: ProviderScope.containerOf(context),
        child: _BluetoothScanSheet(),
      ),
    );
  }

  // ── Helper: load & konversi logo asset ke bitmap ESC/POS ──────────────────

  Future<img.Image?> _loadLogoImage(int maxWidth, WidgetRef ref) async {
    try {
      final store = ref.read(storeSettingsProvider);
      img.Image? original;

      // Pakai logo custom jika ada
      if (store.logoPath.isNotEmpty && File(store.logoPath).existsSync()) {
        final bytes = await File(store.logoPath).readAsBytes();
        original = img.decodeImage(bytes);
      } else {
        // Fallback ke header logo — konsisten dengan kasir & riwayat screen
        final ByteData data =
            await rootBundle.load('assets/logo/header.png');
        final Uint8List bytes = data.buffer.asUint8List();
        original = img.decodeImage(bytes);
      }

      if (original == null) return null;
      // Trim padding transparan agar logo tidak terlihat kecil
      original = img.trim(original, mode: img.TrimMode.transparent);
      if (original.width > maxWidth) {
        original = img.copyResize(original, width: maxWidth);
      }
      return img.grayscale(original);
    } catch (_) {
      return null;
    }
  }

  // ── Ganti logo toko ────────────────────────────────────────────────────────

  Future<void> _ggantiLogo(BuildContext context, WidgetRef ref) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
    );
    if (picked == null) return;

    // Simpan ke folder app agar path permanen
    final appDir = await getApplicationDocumentsDirectory();
    final savedFile = await File(picked.path)
        .copy('${appDir.path}/store_logo.png');

    final store = ref.read(storeSettingsProvider);
    await ref.read(storeSettingsProvider.notifier)
        .save(store.copyWith(logoPath: savedFile.path));

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Logo berhasil diganti!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  // ── Test print ─────────────────────────────────────────────────────────────

  Future<void> _testPrint(
      BuildContext context, WidgetRef ref, StoreSettings store) async {
    final printer = ref.read(printerSettingsProvider);
    if (printer.deviceAddress == null) return;

    // Tampilkan loading
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Mengirim test print ke printer...'),
        backgroundColor: AppColors.primary,
        duration: Duration(seconds: 2),
      ),
    );

    try {
      // Pastikan terhubung ke printer
      final bool connected = await PrintBluetoothThermal.connectionStatus;
      if (!connected) {
        final bool result = await PrintBluetoothThermal.connect(
          macPrinterAddress: printer.deviceAddress!,
        );
        if (!result) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Gagal terhubung ke printer'),
                backgroundColor: AppColors.danger,
              ),
            );
          }
          return;
        }
      }

      final profile = await CapabilityProfile.load();
      final paperSize =
          store.receiptSize == '80mm' ? PaperSize.mm80 : PaperSize.mm58;
      final logoMaxWidth = store.receiptSize == '80mm' ? 300 : 200;
      final generator = Generator(paperSize, profile);
      var bytes = <int>[];

      // ── Logo ────────────────────────────────────────────────────────────
      if (store.showLogo) {
        final logoImg = await _loadLogoImage(logoMaxWidth, ref);
        if (logoImg != null) {
          bytes += generator.image(logoImg);
          bytes += generator.feed(1);
        }
      }

      final storeName = store.storeName.isEmpty ? 'KasirKu' : store.storeName;
      final now = DateTime.now();
      final dateStr =
          '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year} '
          '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

      // ── Header toko ─────────────────────────────────────────────────────
      bytes += generator.text(storeName,
          styles: const PosStyles(
              align: PosAlign.center,
              bold: true,
              height: PosTextSize.size2,
              width: PosTextSize.size2));
      if (store.storeAddress.isNotEmpty) {
        bytes += generator.text(store.storeAddress,
            styles: const PosStyles(align: PosAlign.center));
      }
      if (store.storePhone.isNotEmpty) {
        bytes += generator.text('Telp: ${store.storePhone}',
            styles: const PosStyles(align: PosAlign.center));
      }
      bytes += generator.hr();
      bytes += generator.text('*** STRUK UJI COBA ***',
          styles: const PosStyles(align: PosAlign.center, bold: true));
      bytes += generator.text(dateStr,
          styles: const PosStyles(align: PosAlign.center));
      bytes += generator.hr();

      // Contoh item
      bytes += generator.text('Aqua Botol 600ml',
          styles: const PosStyles(bold: true));
      bytes += generator.row([
        PosColumn(
            text: '  2 x Rp 4.000',
            width: 8,
            styles: const PosStyles(align: PosAlign.left)),
        PosColumn(
            text: 'Rp 8.000',
            width: 4,
            styles: const PosStyles(align: PosAlign.right)),
      ]);
      bytes += generator.text('Indomie Goreng',
          styles: const PosStyles(bold: true));
      bytes += generator.row([
        PosColumn(
            text: '  3 x Rp 3.500',
            width: 8,
            styles: const PosStyles(align: PosAlign.left)),
        PosColumn(
            text: 'Rp 10.500',
            width: 4,
            styles: const PosStyles(align: PosAlign.right)),
      ]);
      bytes += generator.hr();

      // Total
      bytes += generator.row([
        PosColumn(
            text: 'TOTAL',
            width: 6,
            styles: const PosStyles(bold: true, align: PosAlign.left)),
        PosColumn(
            text: 'Rp 18.500',
            width: 6,
            styles: const PosStyles(bold: true, align: PosAlign.right)),
      ]);
      bytes += generator.row([
        PosColumn(
            text: 'Bayar',
            width: 6,
            styles: const PosStyles(align: PosAlign.left)),
        PosColumn(
            text: 'Rp 20.000',
            width: 6,
            styles: const PosStyles(align: PosAlign.right)),
      ]);
      bytes += generator.row([
        PosColumn(
            text: 'Kembali',
            width: 6,
            styles: const PosStyles(align: PosAlign.left)),
        PosColumn(
            text: 'Rp 1.500',
            width: 6,
            styles: const PosStyles(align: PosAlign.right)),
      ]);
      bytes += generator.hr();

      // Footer
      if (store.storeNote.isNotEmpty) {
        bytes += generator.text(store.storeNote,
            styles: const PosStyles(align: PosAlign.center));
      }
      bytes += generator.text('Printer OK - Test Berhasil',
          styles: const PosStyles(align: PosAlign.center, bold: true));
      bytes += generator.feed(3);
      bytes += generator.cut();

      await PrintBluetoothThermal.writeBytes(bytes);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Test print berhasil!'),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal test print: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  // ── PIN setup ──────────────────────────────────────────────────────────────

  void _showPinSetup(BuildContext context, WidgetRef ref,
      {required bool isPinActive}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (_) => ProviderScope(
        parent: ProviderScope.containerOf(context),
        child: _PinSetupSheet(isPinActive: isPinActive),
      ),
    );
  }

  // ── Biometric toggle ───────────────────────────────────────────────────────

  Future<void> _toggleBiometric(
      BuildContext context, WidgetRef ref, bool enable) async {
    // Jika nonaktifkan — langsung simpan false
    if (!enable) {
      await ref.read(biometricProvider.notifier).setEnabled(false);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Biometrik dinonaktifkan'),
            backgroundColor: AppColors.warning,
          ),
        );
      }
      return;
    }

    // Jika aktifkan — verifikasi dulu
    final auth = LocalAuthentication();
    final bool canCheck = await auth.canCheckBiometrics;
    final bool isSupported = await auth.isDeviceSupported();

    if (!canCheck || !isSupported) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Perangkat tidak mendukung biometrik'),
            backgroundColor: AppColors.warning,
          ),
        );
      }
      return;
    }

    final List<BiometricType> available = await auth.getAvailableBiometrics();
    if (available.isEmpty) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Belum ada data biometrik. Daftarkan fingerprint/Face ID di pengaturan HP terlebih dahulu.'),
            backgroundColor: AppColors.warning,
            duration: Duration(seconds: 4),
          ),
        );
      }
      return;
    }

    final hasFace        = available.contains(BiometricType.face);
    final hasFingerprint = available.contains(BiometricType.fingerprint);
    String label = 'Biometrik';
    if (hasFace && hasFingerprint) label = 'Fingerprint / Face ID';
    else if (hasFace) label = 'Face ID';
    else if (hasFingerprint) label = 'Fingerprint';

    try {
      final bool ok = await auth.authenticate(
        localizedReason: 'Verifikasi $label untuk mengaktifkan login biometrik',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );

      if (!context.mounted) return;

      if (ok) {
        // Simpan status aktif ke SharedPreferences
        await ref.read(biometricProvider.notifier).setEnabled(true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ $label aktif — login berikutnya pakai $label'),
            backgroundColor: AppColors.success,
            duration: const Duration(seconds: 3),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Verifikasi dibatalkan, biometrik tidak diaktifkan'),
            backgroundColor: AppColors.warning,
          ),
        );
      }
    } on PlatformException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error biometrik: ${e.message ?? e.code}'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  // ── Backup data ────────────────────────────────────────────────────────────

  Future<void> _backupData(BuildContext context, WidgetRef ref) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final dbFile = File('${dir.path}/kasirku.db');
      if (!dbFile.existsSync()) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Database tidak ditemukan')));
        return;
      }
      final now = DateTime.now();
      final backupName =
          'kasirku_backup_${now.year}${now.month.toString().padLeft(2,'0')}${now.day.toString().padLeft(2,'0')}.db';
      final backup = File('${dir.path}/$backupName');
      await dbFile.copy(backup.path);
      await Share.shareXFiles(
        [XFile(backup.path)],
        subject: 'Backup KasirKu',
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal backup: $e'),
              backgroundColor: AppColors.danger));
      }
    }
  }

  // ── Reset data ─────────────────────────────────────────────────────────────

  Future<void> _confirmReset(BuildContext context, WidgetRef ref) async {
    final ctrl = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('⚠️ Hapus Semua Data?',
            style: TextStyle(fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Semua transaksi, hutang, riwayat stok, dan poin pelanggan akan dihapus permanen. Produk & pengaturan tetap ada.',
              style: TextStyle(fontSize: 13),
            ),
            const SizedBox(height: 16),
            const Text('Ketik HAPUS untuk konfirmasi:',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            TextField(
              controller: ctrl,
              decoration: const InputDecoration(
                hintText: 'HAPUS',
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Batal')),
          ElevatedButton(
              onPressed: () =>
                  Navigator.pop(context, ctrl.text == 'HAPUS'),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.danger),
              child: const Text('Hapus Semua')),
        ],
      ),
    );
    if (confirm == true && context.mounted) {
      try {
        final db = ref.read(databaseProvider);
        await db.resetAllData();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Semua data berhasil dihapus'),
              backgroundColor: AppColors.success));
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Gagal reset: $e'),
              backgroundColor: AppColors.danger));
        }
      }
    }
  }

  // ── Restore Backup ─────────────────────────────────────────────────────────

  Future<void> _restoreBackup(BuildContext context, WidgetRef ref) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('⚠️ Restore Backup?',
            style: TextStyle(fontWeight: FontWeight.w700)),
        content: const Text(
          'Database saat ini akan DIGANTIKAN dengan file backup yang kamu pilih. '
          'Semua data yang belum di-backup akan hilang.',
          style: TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Batal')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.warning),
              child: const Text('Lanjutkan')),
        ],
      ),
    );
    if (confirm != true) return;
    if (!context.mounted) return;

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['db'],
      );
      if (result == null || result.files.single.path == null) return;

      final srcPath = result.files.single.path!;
      final dir = await getApplicationDocumentsDirectory();
      final dbPath = '${dir.path}/kasirku.db';

      // Tutup koneksi DB dulu — tidak bisa dilakukan runtime, jadi copy file
      // dan minta user restart
      await File(srcPath).copy(dbPath);

      if (context.mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => AlertDialog(
            title: const Text('Restore Berhasil',
                style: TextStyle(fontWeight: FontWeight.w700)),
            content: const Text(
              'File backup berhasil dikopi. Tutup dan buka kembali aplikasi untuk memuat data yang dipulihkan.',
            ),
            actions: [
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal restore: $e'),
            backgroundColor: AppColors.danger));
      }
    }
  }

  // ── Cek Update ───────────────────────────────────────────────────────────────

  void _showUpdateSheet(BuildContext context, WidgetRef ref) {
    // Langsung cek update saat sheet dibuka
    ref.read(updateProvider.notifier).checkUpdate();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _UpdateSheet(),
    );
  }

  // ── Tentang Aplikasi ──────────────────────────────────────────────────────

  void _showAbout(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _AboutSheet(),
    );
  }
}

// ─── About Sheet ──────────────────────────────────────────────────────────────

class _AboutSheet extends StatefulWidget {
  const _AboutSheet();

  @override
  State<_AboutSheet> createState() => _AboutSheetState();
}

class _AboutSheetState extends State<_AboutSheet> {
  String _appVersion = '...';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (mounted) setState(() => _appVersion = info.version);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sheetBg     = isDark ? AppColors.darkSurface : Colors.white;
    final handleColor = isDark ? AppColors.darkBorder   : Colors.grey.shade300;
    final textColor   = isDark ? Colors.white           : AppColors.textPrimary;
    final subColor    = isDark ? const Color(0xFF94A3B8): AppColors.textSecondary;
    final divColor    = isDark ? AppColors.darkBorder   : AppColors.border;
    final cardBg      = isDark ? AppColors.darkBg       : AppColors.bg;
    final offlineBg   = isDark
        ? AppColors.primary.withOpacity(0.12)
        : AppColors.primary.withOpacity(0.07);

    return SingleChildScrollView(
      child: Container(
        decoration: BoxDecoration(
          color: sheetBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Handle bar ──────────────────────────────────────────────────
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 24),
              decoration: BoxDecoration(
                color: handleColor,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // ── Logo + nama ─────────────────────────────────────────────────
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                borderRadius: BorderRadius.circular(22),
              ),
              child: const Icon(
                Icons.point_of_sale_rounded,
                color: AppColors.primary,
                size: 40,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              'KasirKu Pro',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: textColor,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Solusi Kasir Praktis untuk Bisnismu',
              style: TextStyle(fontSize: 13, color: subColor),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            // Badge developer
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                'Oleh Artholic Studio',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                ),
              ),
            ),
            const SizedBox(height: 20),

            // ── Info Offline Mode ───────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: offlineBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: AppColors.primary.withOpacity(0.25), width: 0.8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const Icon(Icons.wifi_off_rounded,
                        color: AppColors.primary, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      'Aplikasi Kasir Offline Mode',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : AppColors.textPrimary,
                      ),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  Text(
                    '• Semua data tersimpan di perangkat secara lokal — '
                    'tidak memerlukan koneksi internet untuk beroperasi.\n'
                    '• Data tidak dikirim ke server manapun, '
                    'privasi transaksi sepenuhnya terjaga.\n'
                    '• Gunakan fitur Backup Data secara rutin untuk '
                    'menghindari kehilangan data jika perangkat rusak atau hilang.\n'
                    '• Tidak ada sinkronisasi antar perangkat. '
                    'Data hanya ada di HP yang digunakan.',
                    style: TextStyle(
                      fontSize: 12,
                      color: subColor,
                      height: 1.6,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Info rows ───────────────────────────────────────────────────
            Container(
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: divColor, width: 0.5),
              ),
              child: Column(
                children: [
                  _AboutRow(
                    label: 'Versi',
                    value: _appVersion,
                    icon: Icons.tag_rounded,
                    isDark: isDark,
                  ),
                  Divider(height: 1, color: divColor),
                  _AboutRow(
                    label: 'Developer',
                    value: 'Artholic Studio',
                    icon: Icons.business_rounded,
                    isDark: isDark,
                  ),
                  Divider(height: 1, color: divColor),
                  _AboutRow(
                    label: 'Platform',
                    value: 'Android',
                    icon: Icons.phone_android_rounded,
                    isDark: isDark,
                  ),
                  Divider(height: 1, color: divColor),
                  _AboutRow(
                    label: 'Mode',
                    value: 'Offline',
                    icon: Icons.wifi_off_rounded,
                    isDark: isDark,
                  ),
                  Divider(height: 1, color: divColor),
                  _AboutRow(
                    label: 'Database',
                    value: 'SQLite (Lokal)',
                    icon: Icons.storage_rounded,
                    isDark: isDark,
                  ),
                  Divider(height: 1, color: divColor),
                  _AboutRow(
                    label: 'Dibuat dengan',
                    value: 'Flutter',
                    icon: Icons.flutter_dash_rounded,
                    isDark: isDark,
                  ),
                  Divider(height: 1, color: divColor),
                  _AboutRow(
                    label: 'Lisensi',
                    value: 'Proprietary',
                    icon: Icons.shield_outlined,
                    isDark: isDark,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ── Donasi / Kopi ────────────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFFFFF8E7),
                    const Color(0xFFFFF3CC),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: const Color(0xFFFFD666).withOpacity(0.6), width: 1),
              ),
              child: Column(
                children: [
                  // Icon kopi
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFD666).withOpacity(0.3),
                      shape: BoxShape.circle,
                    ),
                    child: const Text('☕',
                        style: TextStyle(fontSize: 24)),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Dukung Pengembangan',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF92400E),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'KasirkuPro dikembangkan dengan ❤️ untuk membantu UMKM Indonesia. '
                    'Jika aplikasi ini bermanfaat dan kamu ingin mendukung pengembangan, '
                    'secangkir kopi sangat berarti bagi saya ☕',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12.5,
                      color: Color(0xFF92400E),
                      height: 1.6,
                    ),
                  ),
                  const SizedBox(height: 14),
                  // Placeholder QR Code — ganti dengan Image.asset('assets/images/qris.png')
                  // setelah file QRIS ditambahkan ke assets
                  Container(
                    width: 180,
                    height: 180,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: const Color(0xFFFFD666), width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: Image.asset(
                        'assets/images/qris.png',
                        fit: BoxFit.cover,
                        width: 180,
                        height: 180,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFD666).withOpacity(0.4),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Scan QRIS untuk traktir kopi 😄',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF92400E),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),
            Text(
              '© 2026 Artholic Studio. All rights reserved.',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: subColor,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'KasirKu — Kasir offline untuk usahamu.',
              style: TextStyle(fontSize: 11, color: subColor),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Update Sheet ─────────────────────────────────────────────────────────────

class _UpdateSheet extends ConsumerWidget {
  const _UpdateSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state  = ref.watch(updateProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sheetBg    = isDark ? AppColors.darkSurface : Colors.white;
    final handleColor= isDark ? AppColors.darkBorder : Colors.grey.shade300;
    final textColor  = isDark ? Colors.white : AppColors.textPrimary;
    final subColor   = isDark ? const Color(0xFF94A3B8) : AppColors.textSecondary;

    return Container(
      decoration: BoxDecoration(
        color: sheetBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
          24, 12, 24, MediaQuery.of(context).viewInsets.bottom + 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            width: 40, height: 4,
            margin: const EdgeInsets.only(bottom: 24),
            decoration: BoxDecoration(
              color: handleColor,
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Icon
          Container(
            width: 64, height: 64,
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(Icons.system_update_rounded,
                color: AppColors.primary, size: 32),
          ),
          const SizedBox(height: 14),
          Text('Update Aplikasi',
              style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.w800, color: textColor)),
          const SizedBox(height: 24),

          // ── Konten berdasarkan status ──────────────────────────────────
          _buildUpdateContent(context, ref, state, textColor, subColor),

          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildUpdateContent(BuildContext context, WidgetRef ref,
      UpdateState state, Color textColor, Color subColor) {
    switch (state.status) {
      // Checking
      case UpdateStatus.checking:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(children: [
            const CircularProgressIndicator(color: AppColors.primary),
            const SizedBox(height: 16),
            Text('Memeriksa update...', style: TextStyle(color: subColor)),
          ]),
        );

      // Ada update
      case UpdateStatus.available:
        final info = state.info!;
        return Column(children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(Icons.new_releases_rounded,
                      color: AppColors.primary, size: 18),
                  const SizedBox(width: 8),
                  Text('Versi Baru Tersedia!',
                      style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700,
                        color: AppColors.primary)),
                ]),
                const SizedBox(height: 10),
                _versionRow('Versi terpasang', info.currentVersion, subColor),
                const SizedBox(height: 4),
                _versionRow('Versi terbaru', info.latestVersion, AppColors.primary,
                    bold: true),
              ],
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.download_rounded),
              label: const Text('Download & Install'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () =>
                  ref.read(updateProvider.notifier).downloadAndInstall(),
            ),
          ),
        ]);

      // Downloading
      case UpdateStatus.downloading:
        final pct = (state.downloadProgress * 100).toInt();
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(children: [
            Text('Mengunduh update... $pct%',
                style: TextStyle(
                    fontWeight: FontWeight.w600, color: textColor)),
            const SizedBox(height: 14),
            LinearProgressIndicator(
              value: state.downloadProgress,
              backgroundColor: AppColors.primaryLight,
              color: AppColors.primary,
              minHeight: 8,
              borderRadius: BorderRadius.circular(4),
            ),
            const SizedBox(height: 10),
            Text('Jangan tutup aplikasi saat proses download',
                style: TextStyle(fontSize: 12, color: subColor)),
          ]),
        );

      // Installing
      case UpdateStatus.installing:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(children: [
            const CircularProgressIndicator(color: AppColors.primary),
            const SizedBox(height: 16),
            Text('Membuka installer...',
                style: TextStyle(color: subColor)),
            const SizedBox(height: 8),
            Text('Ikuti instruksi instalasi yang muncul',
                style: TextStyle(fontSize: 12, color: subColor)),
          ]),
        );

      // Sudah up to date
      case UpdateStatus.upToDate:
        final info = state.info;
        return Column(children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.green.withOpacity(0.3)),
            ),
            child: Column(children: [
              const Icon(Icons.check_circle_rounded,
                  color: Colors.green, size: 40),
              const SizedBox(height: 10),
              Text('Aplikasi sudah versi terbaru!',
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700,
                      color: textColor)),
              if (info != null) ...[
                const SizedBox(height: 6),
                Text('Versi ${info.currentVersion}',
                    style: TextStyle(color: subColor, fontSize: 13)),
              ],
            ]),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () =>
                  ref.read(updateProvider.notifier).checkUpdate(),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Cek Ulang'),
            ),
          ),
        ]);

      // Perlu izin install dari Settings
      case UpdateStatus.needInstallPermission:
        return Column(children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.orange.withOpacity(0.4)),
            ),
            child: Column(children: [
              const Icon(Icons.security_rounded,
                  color: Colors.orange, size: 36),
              const SizedBox(height: 10),
              Text(
                state.errorMessage ??
                    'Izinkan "Install unknown apps" untuk aplikasi ini di Pengaturan, '
                    'lalu tekan tombol install lagi.',
                textAlign: TextAlign.center,
                style: TextStyle(color: subColor, fontSize: 13),
              ),
            ]),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.settings_rounded),
              label: const Text('Buka Pengaturan'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () =>
                  ref.read(updateProvider.notifier).retryInstall(),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () => ref.read(updateProvider.notifier).reset(),
              child: Text('Batal',
                  style: TextStyle(color: subColor)),
            ),
          ),
        ]);

      // Error
      case UpdateStatus.error:
        return Column(children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.danger.withOpacity(0.07),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.danger.withOpacity(0.3)),
            ),
            child: Column(children: [
              const Icon(Icons.error_outline_rounded,
                  color: AppColors.danger, size: 36),
              const SizedBox(height: 10),
              Text(state.errorMessage ?? 'Terjadi kesalahan',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: subColor, fontSize: 13)),
            ]),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Coba Lagi'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () =>
                  ref.read(updateProvider.notifier).checkUpdate(),
            ),
          ),
        ]);

      // Idle
      case UpdateStatus.idle:
      default:
        return Column(children: [
          Text('Tekan tombol di bawah untuk memeriksa versi terbaru.',
              textAlign: TextAlign.center,
              style: TextStyle(color: subColor, fontSize: 13)),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.search_rounded),
              label: const Text('Cek Update Sekarang'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () =>
                  ref.read(updateProvider.notifier).checkUpdate(),
            ),
          ),
        ]);
    }
  }

  Widget _versionRow(String label, String value, Color valueColor,
      {bool bold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
        Text(value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              color: valueColor,
            )),
      ],
    );
  }
}

// ─── About Row ────────────────────────────────────────────────────────────────

class _AboutRow extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final bool isDark;

  const _AboutRow({
    required this.label,
    required this.value,
    required this.icon,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final labelColor = isDark ? const Color(0xFF94A3B8) : AppColors.textSecondary;
    final valueColor = isDark ? Colors.white : AppColors.textPrimary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.primary),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(fontSize: 13, color: labelColor),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Receipt Preview Widget ───────────────────────────────────────────────────

class _ReceiptPreview extends StatelessWidget {
  final StoreSettings store;
  const _ReceiptPreview({required this.store});

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(fontFamily: 'Courier', fontSize: 11);
    const bold  = TextStyle(
        fontFamily: 'Courier', fontSize: 12, fontWeight: FontWeight.w700);
    final divider = Text('-' * 32,
        style: style.copyWith(color: Colors.grey));

    return DefaultTextStyle(
      style: style,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ── Logo ──────────────────────────────────────────────────────────
          if (store.showLogo) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: store.logoPath.isNotEmpty && File(store.logoPath).existsSync()
                  ? Image.file(
                      File(store.logoPath),
                      width: 56,
                      height: 56,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    )
                  : Image.asset(
                      'assets/images/app_icon.png',
                      width: 56,
                      height: 56,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
            ),
            const SizedBox(height: 6),
          ],
          // Header
          Text(store.storeName,
              style: bold.copyWith(fontSize: 14),
              textAlign: TextAlign.center),
          if (store.storeAddress.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(store.storeAddress,
                style: style.copyWith(fontSize: 10),
                textAlign: TextAlign.center),
          ],
          if (store.storePhone.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text('Telp: ${store.storePhone}',
                style: style.copyWith(fontSize: 10),
                textAlign: TextAlign.center),
          ],
          const SizedBox(height: 6),
          divider,
          const SizedBox(height: 4),
          Text('No: INV-20240101-001', style: style),
          Text('Kasir: Kasir Pagi',   style: style),
          Text('Tgl: 01/01/2024 08:00', style: style),
          const SizedBox(height: 4),
          divider,
          const SizedBox(height: 4),
          // Items
          _ReceiptItem('Aqua Botol 600ml', 2, 4000),
          _ReceiptItem('Indomie Goreng',   3, 3500),
          _ReceiptItem('Kopi Sachet',      1, 2000),
          const SizedBox(height: 4),
          divider,
          const SizedBox(height: 4),
          _ReceiptRow('Subtotal', 'Rp 19.500'),
          _ReceiptRow('Diskon',   '-Rp 0'),
          _ReceiptRow('Total',    'Rp 19.500', bold: true),
          _ReceiptRow('Bayar',    'Rp 20.000'),
          _ReceiptRow('Kembali',  'Rp 500',   bold: true),
          const SizedBox(height: 4),
          divider,
          const SizedBox(height: 6),
          Text(store.storeNote,
              style: style.copyWith(fontSize: 10),
              textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text('* * *',
              style: style.copyWith(
                  letterSpacing: 4, color: Colors.grey)),
        ],
      ),
    );
  }
}

class _ReceiptItem extends StatelessWidget {
  final String name;
  final int qty;
  final int price;
  const _ReceiptItem(this.name, this.qty, this.price);

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(fontFamily: 'Courier', fontSize: 11);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name, style: style),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('  $qty x ${CurrencyFormatter.format(price.toDouble())}',
                  style: style),
              Text(CurrencyFormatter.format((qty * price).toDouble()),
                  style: style),
            ],
          ),
        ],
      ),
    );
  }
}

class _ReceiptRow extends StatelessWidget {
  final String label, value;
  final bool bold;
  const _ReceiptRow(this.label, this.value, {this.bold = false});

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontFamily: 'Courier',
      fontSize: bold ? 12 : 11,
      fontWeight: bold ? FontWeight.w700 : FontWeight.normal,
    );
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: style),
        Text(value,  style: style),
      ],
    );
  }
}

// ─── Bluetooth Scan Sheet ─────────────────────────────────────────────────────

class _BluetoothScanSheet extends ConsumerStatefulWidget {
  @override
  ConsumerState<_BluetoothScanSheet> createState() =>
      _BluetoothScanSheetState();
}

class _BluetoothScanSheetState
    extends ConsumerState<_BluetoothScanSheet> {
  bool _scanning = false;
  List<dynamic> _devices = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _scanDevices();
  }

  Future<void> _scanDevices() async {
    setState(() { _scanning = true; _error = null; });
    try {
      final List<dynamic> paired =
          await PrintBluetoothThermal.pairedBluetooths;
      if (mounted) {
        setState(() {
          _devices = paired;
          _scanning = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Gagal memuat daftar printer: $e';
          _scanning = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Expanded(
              child: Text('Pilih Printer Bluetooth',
                  style: TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 16))),
            IconButton(
                icon: Icon(
                    _scanning ? Icons.stop : Icons.refresh,
                    color: AppColors.primary),
                onPressed: _scanning ? null : _scanDevices),
          ]),
          if (_scanning) ...[
            const SizedBox(height: 8),
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            Text('Mencari perangkat Bluetooth yang dipasangkan...',
                style: TextStyle(
                    color: Colors.grey.shade500, fontSize: 12)),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                style: const TextStyle(
                    color: AppColors.danger, fontSize: 12)),
          ],
          if (!_scanning && _devices.isEmpty && _error == null) ...[
            const SizedBox(height: 16),
            Center(
              child: Column(children: [
                Icon(Icons.bluetooth_disabled,
                    size: 40, color: Colors.grey.shade400),
                const SizedBox(height: 8),
                Text('Tidak ada printer Bluetooth yang dipasangkan',
                    style: TextStyle(
                        color: Colors.grey.shade500, fontSize: 13),
                    textAlign: TextAlign.center),
                const SizedBox(height: 4),
                Text('Pasangkan printer terlebih dahulu\ndi Pengaturan Bluetooth perangkat',
                    style: TextStyle(
                        color: Colors.grey.shade400, fontSize: 11),
                    textAlign: TextAlign.center),
              ]),
            ),
            const SizedBox(height: 16),
          ],
          if (_devices.isNotEmpty) ...[
            const SizedBox(height: 12),
            ..._devices.map((d) => ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.print_outlined,
                    color: AppColors.primary, size: 20),
              ),
              title: Text(d.name ?? 'Printer Bluetooth',
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(d.macAdress ?? '',
                  style: TextStyle(
                      fontSize: 11, color: Colors.grey.shade500)),
              trailing: ElevatedButton(
                onPressed: () async {
                  await ref.read(printerSettingsProvider.notifier)
                      .setPrinter(
                          d.name ?? 'Printer Bluetooth',
                          d.macAdress ?? '');
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                            '${d.name ?? 'Printer'} terhubung'),
                        backgroundColor: AppColors.success,
                      ),
                    );
                  }
                },
                style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 8)),
                child: const Text('Pilih',
                    style: TextStyle(fontSize: 13)),
              ),
            )),
          ],
          const SizedBox(height: 8),
          Center(
            child: TextButton.icon(
              icon: const Icon(Icons.info_outline, size: 14),
              label: const Text('Pastikan Bluetooth aktif & printer menyala',
                  style: TextStyle(fontSize: 12)),
              onPressed: null,
            ),
          ),
        ],
      ),
    );
  }
}

// ─── PIN Setup Sheet ──────────────────────────────────────────────────────────

class _PinSetupSheet extends ConsumerStatefulWidget {
  final bool isPinActive;
  const _PinSetupSheet({required this.isPinActive});

  @override
  ConsumerState<_PinSetupSheet> createState() => _PinSetupSheetState();
}

class _PinSetupSheetState extends ConsumerState<_PinSetupSheet> {
  final _pin1 = TextEditingController();
  final _pin2 = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _pin1.dispose();
    _pin2.dispose();
    super.dispose();
  }

  Future<void> _savePin() async {
    if (_pin1.text.length < 4) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PIN minimal 4 digit')));
      return;
    }
    if (_pin1.text != _pin2.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('PIN tidak cocok'),
          backgroundColor: AppColors.danger));
      return;
    }
    setState(() => _saving = true);
    final ok = await ref.read(pinProvider.notifier).setPin(_pin1.text);
    if (!mounted) return;
    setState(() => _saving = false);
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? '✅ PIN berhasil disimpan' : 'Gagal menyimpan PIN'),
        backgroundColor: ok ? AppColors.success : AppColors.danger));
  }

  Future<void> _clearPin() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Nonaktifkan PIN?',
            style: TextStyle(fontWeight: FontWeight.w700)),
        content: const Text(
            'Aplikasi tidak akan meminta PIN saat dibuka.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Batal')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.danger),
              child: const Text('Nonaktifkan')),
        ],
      ),
    );
    if (confirm == true) {
      await ref.read(pinProvider.notifier).clearPin();
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PIN dinonaktifkan')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        top: 20, left: 20, right: 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.isPinActive ? 'Ubah PIN Aplikasi' : 'Set PIN Aplikasi',
            style: const TextStyle(
                fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 6),
          Text('PIN digunakan untuk membuka aplikasi',
              style: TextStyle(
                  color: Colors.grey.shade500, fontSize: 12)),
          const SizedBox(height: 16),
          TextField(
            controller: _pin1,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            autofocus: true,
            decoration: InputDecoration(
              labelText: widget.isPinActive
                  ? 'PIN Baru (4-6 digit)'
                  : 'PIN Baru (4-6 digit)',
              prefixIcon: const Icon(Icons.lock_outline),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _pin2,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(
              labelText: 'Konfirmasi PIN',
              prefixIcon: Icon(Icons.lock_outline),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: _saving
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2))
                  : const Icon(Icons.save_outlined, size: 18),
              label: Text(_saving ? 'Menyimpan...' : 'Simpan PIN'),
              onPressed: _saving ? null : _savePin,
            ),
          ),
          if (widget.isPinActive) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                icon: const Icon(Icons.lock_open_outlined,
                    size: 18, color: AppColors.danger),
                label: const Text('Nonaktifkan PIN',
                    style: TextStyle(color: AppColors.danger)),
                onPressed: _clearPin,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Shared Widgets ───────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Section(this.title, this.children);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
          child: Text(title.toUpperCase(),
              style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary,
                  fontSize: 11,
                  letterSpacing: 0.8)),
        ),
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(children: children),
        ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final VoidCallback? onTap;
  final Color? color;
  const _Tile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = color ?? AppColors.primary;
    // FIX: title selalu w700 + ukuran 14, warna hanya untuk item berwarna
    // Item normal (tanpa color) tetap pakai warna teks utama agar konsisten
    final titleColor = color != null
        ? color!
        : (isDark ? Colors.white : AppColors.textPrimary);
    return ListTile(
      leading: _TileIcon(icon, c),
      title: Text(title,
          style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: titleColor)),
      subtitle: Text(subtitle,
          style: TextStyle(
              fontSize: 12,
              color: isDark ? const Color(0xFF94A3B8) : Colors.grey.shade500)),
      trailing: onTap != null
          ? Icon(Icons.chevron_right,
              color: isDark ? const Color(0xFF64748B) : Colors.grey,
              size: 20)
          : null,
      onTap: onTap,
    );
  }
}


class _SwitchTile extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final Color? color;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = color ?? AppColors.primary;
    // FIX: sama seperti _Tile — title w700 size 14, warna hanya jika ada color
    final titleColor = color != null
        ? color!
        : (isDark ? Colors.white : AppColors.textPrimary);
    return ListTile(
      leading: _TileIcon(icon, c),
      title: Text(title,
          style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              color: titleColor)),
      subtitle: Text(subtitle,
          style: TextStyle(
              fontSize: 12,
              color: isDark ? const Color(0xFF94A3B8) : Colors.grey.shade500)),
      trailing: Switch(
        value: value,
        onChanged: onChanged,
        activeColor: AppColors.primary,
      ),
    );
  }
}

class _TileIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  const _TileIcon(this.icon, this.color);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: color, size: 20),
    );
  }
}

// ─── Backup Tile ──────────────────────────────────────────────────────────────

class _BackupTile extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final backup = ref.watch(backupProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final months = ['Jan','Feb','Mar','Apr','Mei','Jun',
                    'Jul','Ags','Sep','Okt','Nov','Des'];
    String lastBackupStr = 'Belum pernah backup';
    if (backup.lastBackup != null) {
      final d = backup.lastBackup!;
      lastBackupStr =
          '${d.day} ${months[d.month - 1]} ${d.year}, ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkCard : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: isDark ? AppColors.darkBorder : AppColors.border,
            width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Status koneksi Google ──────────────────────────────────────────
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: (backup.isConnected
                        ? AppColors.success
                        : AppColors.textSecondary)
                    .withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.backup_rounded,
                color: backup.isConnected
                    ? AppColors.success
                    : AppColors.textSecondary,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    backup.isConnected ? 'Terhubung' : 'Belum Terhubung',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: backup.isConnected
                          ? AppColors.success
                          : AppColors.textSecondary,
                    ),
                  ),
                  Text(
                    backup.isConnected
                        ? backup.connectedEmail ?? ''
                        : 'Hubungkan Google Drive untuk backup otomatis',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          ]),

          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),

          // ── Info backup terakhir ───────────────────────────────────────────
          Row(children: [
            const Icon(Icons.history_rounded,
                size: 14, color: AppColors.textSecondary),
            const SizedBox(width: 6),
            Text(
              'Backup terakhir: $lastBackupStr',
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary),
            ),
          ]),

          const SizedBox(height: 12),

          // ── Pesan status ──────────────────────────────────────────────────
          if (backup.message != null) ...[
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: backup.status == BackupStatus.error
                    ? AppColors.danger.withOpacity(0.08)
                    : AppColors.success.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(children: [
                Icon(
                  backup.status == BackupStatus.error
                      ? Icons.error_outline
                      : Icons.check_circle_outline,
                  size: 14,
                  color: backup.status == BackupStatus.error
                      ? AppColors.danger
                      : AppColors.success,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    backup.message!,
                    style: TextStyle(
                      fontSize: 12,
                      color: backup.status == BackupStatus.error
                          ? AppColors.danger
                          : AppColors.success,
                    ),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 12),
          ],

          // ── Tombol aksi ───────────────────────────────────────────────────
          if (backup.status == BackupStatus.loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 16, height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2)),
                    SizedBox(width: 8),
                    Text('Memproses...',
                        style: TextStyle(
                            fontSize: 13, color: AppColors.textSecondary)),
                  ],
                ),
              ),
            )
          else if (!backup.isConnected)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.login_rounded, size: 18),
                label: const Text('Hubungkan Google Drive'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () =>
                    ref.read(backupProvider.notifier).connectGoogle(),
              ),
            )
          else
            Column(children: [
              Row(children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.cloud_upload_outlined, size: 16),
                    label: const Text('Backup Sekarang'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () =>
                        ref.read(backupProvider.notifier).backupNow(),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.cloud_download_outlined, size: 16),
                    label: const Text('Restore'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.info,
                      side: const BorderSide(color: AppColors.info),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () => _confirmRestore(context, ref),
                  ),
                ),
              ]),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: TextButton.icon(
                  icon: const Icon(Icons.logout_rounded,
                      size: 14, color: AppColors.danger),
                  label: const Text('Putuskan Google Drive',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.danger)),
                  onPressed: () =>
                      ref.read(backupProvider.notifier).disconnectGoogle(),
                ),
              ),
            ]),
        ],
      ),
    );
  }

  Future<void> _confirmRestore(BuildContext context, WidgetRef ref) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.warning_amber_rounded,
              color: AppColors.warning, size: 22),
          SizedBox(width: 8),
          Text('Restore Data?',
              style: TextStyle(fontWeight: FontWeight.w700)),
        ]),
        content: const Text(
          'Data saat ini akan diganti dengan data dari backup. '
          'Pastikan sudah backup data terbaru sebelum restore.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.warning,
                foregroundColor: Colors.white),
            child: const Text('Ya, Restore')),
        ],
      ),
    );
    if (confirm == true) {
      ref.read(backupProvider.notifier).restoreFromDrive();
    }
  }
}
