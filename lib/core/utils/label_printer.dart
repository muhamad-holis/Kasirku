import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'currency.dart';
import 'receipt_text_wrap.dart';

/// Satu baris label yang mau dicetak: nama barang (dari Stok Kasirku),
/// satuan, harga, dan berapa lembar yang mau dicetak.
class LabelItem {
  final String productName;
  final String unit;
  final double price;
  final int quantity;

  const LabelItem({
    required this.productName,
    required this.unit,
    required this.price,
    required this.quantity,
  });
}

/// Cetak label harga barang (menu "Cetak Label") — logika & format sama
/// seperti aplikasi Label Harga terpisah sebelumnya, dipindah ke sini supaya
/// bisa memakai data produk yang sama dengan Stok/Kasir (satu sumber data).
class LabelPrinter {
  static Future<List<int>> buildBytes({
    required List<LabelItem> items,
    required PaperSize paperSize,
  }) async {
    final profile = await CapabilityProfile.load();
    final generator = Generator(paperSize, profile);
    var bytes = <int>[];
    for (final item in items) {
      for (var i = 0; i < item.quantity; i++) {
        bytes += _buildSingleLabel(generator, item, paperSize);
      }
    }
    return bytes;
  }

  static Future<bool> print({
    required List<LabelItem> items,
    required PaperSize paperSize,
  }) async {
    final connected = await PrintBluetoothThermal.connectionStatus;
    if (!connected) throw Exception('Printer belum terhubung.');
    final bytes = await buildBytes(items: items, paperSize: paperSize);
    if (bytes.isEmpty) return false;
    return PrintBluetoothThermal.writeBytes(bytes);
  }

  /// Format satu label: nama barang (bold) + satuan (kecil) + harga
  /// (besar, tengah) + garis gunting.
  static List<int> _buildSingleLabel(
      Generator generator, LabelItem item, PaperSize paperSize) {
    var bytes = <int>[];

    for (final line in wrapReceiptText(item.productName, paperSize: paperSize)) {
      bytes += generator.text(line,
          styles: const PosStyles(align: PosAlign.center, bold: true));
    }

    bytes += generator.text('/ ${item.unit}',
        styles: const PosStyles(align: PosAlign.center));

    bytes += generator.text(CurrencyFormatter.format(item.price),
        styles: const PosStyles(
          align: PosAlign.center,
          bold: true,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
        ));

    bytes += generator.hr(ch: '-');
    bytes += generator.text('- - - - gunting di sini - - - -',
        styles: const PosStyles(align: PosAlign.center));
    bytes += generator.feed(1);

    return bytes;
  }
}
