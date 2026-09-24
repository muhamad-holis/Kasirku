import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart' show rootBundle;
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:image/image.dart' as img;
import 'package:intl/intl.dart';
import '../../data/database/app_database.dart';
import '../../presentation/providers/manual_nota_provider.dart';
import '../../presentation/providers/settings_provider.dart';
import 'currency.dart';

/// Builder struk untuk Nota Manual — memakai library ESC/POS yang sama
/// (esc_pos_utils_plus + print_bluetooth_thermal) dengan Kasir Otomatis,
/// supaya perilaku printer (paper size, koneksi, dsb) konsisten di kedua mode.
class ManualNotaPrinter {
  static Future<img.Image?> _loadLogo(StoreSettings settings, int maxWidth) async {
    try {
      img.Image? original;
      if (settings.logoPath.isNotEmpty && File(settings.logoPath).existsSync()) {
        final bytes = await File(settings.logoPath).readAsBytes();
        original = img.decodeImage(bytes);
      } else {
        final ByteData data = await rootBundle.load('assets/logo/header.png');
        final Uint8List bytes = data.buffer.asUint8List();
        original = img.decodeImage(bytes);
      }
      if (original == null) return null;
      original = img.trim(original, mode: img.TrimMode.transparent);
      if (original.width > maxWidth) {
        original = img.copyResize(original, width: maxWidth);
      }
      return img.grayscale(original);
    } catch (_) {
      return null;
    }
  }

  /// Bangun byte ESC/POS untuk satu nota manual. Dipisah dari [print] supaya
  /// bisa dites/dipakai ulang (mis. untuk preview) tanpa harus konek printer.
  static Future<List<int>> buildBytes({
    required ManualNota nota,
    required List<ManualNotaItem> items,
    required StoreSettings settings,
  }) async {
    final paperSize =
        settings.receiptSize == '80mm' ? PaperSize.mm80 : PaperSize.mm58;
    final logoMaxWidth = settings.receiptSize == '80mm' ? 300 : 200;

    final profile = await CapabilityProfile.load();
    final generator = Generator(paperSize, profile);
    var bytes = <int>[];

    final dateStr = DateFormat('dd/MM/yyyy HH:mm').format(nota.createdAt);
    final storeName = settings.storeName.isEmpty ? 'KasirKu' : settings.storeName;

    if (settings.showLogo) {
      final logoImg = await _loadLogo(settings, logoMaxWidth);
      if (logoImg != null) {
        bytes += generator.image(logoImg);
        bytes += generator.feed(1);
      }
    }

    bytes += generator.text(storeName,
        styles: const PosStyles(
          align: PosAlign.center,
          bold: true,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
        ));
    if (settings.storeAddress.isNotEmpty) {
      bytes += generator.text(settings.storeAddress,
          styles: const PosStyles(align: PosAlign.center));
    }
    if (settings.storePhone.isNotEmpty) {
      bytes += generator.text('Telp: ${settings.storePhone}',
          styles: const PosStyles(align: PosAlign.center));
    }
    bytes += generator.hr();
    bytes += generator.text('NOTA MANUAL',
        styles: const PosStyles(align: PosAlign.center, bold: true));
    bytes += generator.text('No: ${nota.invoiceNumber}',
        styles: const PosStyles(align: PosAlign.center));
    bytes += generator.text(dateStr, styles: const PosStyles(align: PosAlign.center));
    if ((nota.customerName ?? '').isNotEmpty) {
      bytes += generator.text('Pelanggan: ${nota.customerName}',
          styles: const PosStyles(align: PosAlign.center));
    }
    bytes += generator.hr();

    for (final item in items) {
      bytes += generator.text(item.name, styles: const PosStyles(bold: true));
      bytes += generator.row([
        PosColumn(
          text: '  ${item.qty} x ${CurrencyFormatter.format(item.price)}',
          width: 8,
          styles: const PosStyles(align: PosAlign.left),
        ),
        PosColumn(
          text: CurrencyFormatter.format(item.total),
          width: 4,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]);
    }
    bytes += generator.hr();

    bytes += generator.row([
      PosColumn(text: 'TOTAL', width: 6, styles: const PosStyles(bold: true, align: PosAlign.left)),
      PosColumn(
        text: CurrencyFormatter.format(nota.total),
        width: 6,
        styles: const PosStyles(bold: true, align: PosAlign.right),
      ),
    ]);

    if (nota.amountPaid != null && nota.amountPaid! > 0) {
      bytes += generator.row([
        PosColumn(text: 'Bayar', width: 6, styles: const PosStyles(align: PosAlign.left)),
        PosColumn(
          text: CurrencyFormatter.format(nota.amountPaid!),
          width: 6,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]);
      final kembali = nota.amountPaid! - nota.total;
      if (kembali > 0) {
        bytes += generator.row([
          PosColumn(text: 'Kembali', width: 6, styles: const PosStyles(align: PosAlign.left)),
          PosColumn(
            text: CurrencyFormatter.format(kembali),
            width: 6,
            styles: const PosStyles(align: PosAlign.right),
          ),
        ]);
      }
    }
    bytes += generator.hr();

    if (settings.storeNote.isNotEmpty) {
      bytes += generator.text(settings.storeNote,
          styles: const PosStyles(align: PosAlign.center, bold: true));
    }
    bytes += generator.feed(3);
    bytes += generator.cut();
    return bytes;
  }

  /// Cetak langsung ke printer yang sudah terhubung. Lempar [Exception]
  /// kalau belum ada printer yang connect — pemanggil bertanggung jawab
  /// menampilkan dialog pilih printer terlebih dulu (sama seperti alur
  /// _showBluetoothPrinterDialog di kasir_screen.dart).
  static Future<void> print({
    required ManualNota nota,
    required List<ManualNotaItem> items,
    required StoreSettings settings,
  }) async {
    final connected = await PrintBluetoothThermal.connectionStatus;
    if (!connected) {
      throw Exception('Printer belum terhubung.');
    }
    final bytes = await buildBytes(nota: nota, items: items, settings: settings);
    await PrintBluetoothThermal.writeBytes(bytes);
  }
}
