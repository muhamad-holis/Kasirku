
// lib/core/utils/receipt_pdf_builder.dart

import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'currency.dart';

class ReceiptPdfItem {
  final String name;
  final int quantity;
  final double price;
  final double subtotal;

  const ReceiptPdfItem({
    required this.name,
    required this.quantity,
    required this.price,
    required this.subtotal,
  });
}

class ReceiptPdfBuilder {
  ReceiptPdfBuilder._();

  static const double _fontSize   = 8;
  static const double _fontSizeSm = 7;
  static const double _fontSizeLg = 10;
  // Perubahan: diperkecil dari 16 ke 13 agar tidak terlalu besar
  static const double _fontSizeXl = 13;

  static const String _divider = '================================================';

  static Future<Uint8List> build({
    required String storeName,
    required String storeAddress,
    required String storePhone,
    required String storeNote,
    required String invoiceNumber,
    required DateTime date,
    required String paymentMethodLabel,
    String? kasirName,
    String? customerName,
    required List<ReceiptPdfItem> items,
    double discount = 0,
    double discountPercent = 0,
    double tax = 0,
    double taxPercent = 0,
    required double total,
    double? amountPaid,
    double? change,
    String receiptSize = '58mm',
    pw.MemoryImage? logoImage,
    pw.MemoryImage? footerLogoImage,
  }) async {
    final doc = pw.Document();
    final dateStr =
        '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

    final pageFormat = receiptSize == '80mm' ? PdfPageFormat.roll80 : PdfPageFormat.roll57;
    final totalQty  = items.fold<int>(0, (s, it) => s + it.quantity);
    final subtotal  = total + discount - tax;

    doc.addPage(pw.Page(
      pageFormat: pageFormat,
      margin: const pw.EdgeInsets.only(left: 6, right: 6, top: 6, bottom: 12),
      build: (pw.Context ctx) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            if (logoImage != null) ...[
              pw.Center(child: pw.Image(logoImage, width: 110, height: 110, fit: pw.BoxFit.contain)),
              pw.SizedBox(height: 4),
            ],
            pw.Text(storeName, style: pw.TextStyle(fontSize: _fontSizeLg + 2, fontWeight: pw.FontWeight.bold, color: PdfColors.black), textAlign: pw.TextAlign.center),
            if (storeAddress.isNotEmpty) ...[pw.SizedBox(height: 2), pw.Text(storeAddress, style: const pw.TextStyle(fontSize: _fontSizeSm, color: PdfColors.black), textAlign: pw.TextAlign.center)],
            if (storePhone.isNotEmpty) ...[pw.SizedBox(height: 1), pw.Text('Telp. $storePhone', style: const pw.TextStyle(fontSize: _fontSizeSm, color: PdfColors.black), textAlign: pw.TextAlign.center)],
            pw.SizedBox(height: 3),
            _hr(),
            _infoRow('No Invoice', invoiceNumber),
            _infoRow('Tanggal', dateStr),
            _infoRow('Metode', paymentMethodLabel),
            if (kasirName != null && kasirName.isNotEmpty) _infoRow('Kasir', kasirName),
            _infoRow('Pelanggan', (customerName != null && customerName.isNotEmpty) ? customerName : 'Umum'),
            pw.SizedBox(height: 2),
            _hr(),
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 4),
              child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                pw.SizedBox(width: 14, child: pw.Text('No.', style: pw.TextStyle(fontSize: _fontSizeSm, fontWeight: pw.FontWeight.bold, color: PdfColors.black))),
                pw.Expanded(child: pw.Text('Nama Barang', style: pw.TextStyle(fontSize: _fontSizeSm, fontWeight: pw.FontWeight.bold, color: PdfColors.black))),
                pw.SizedBox(width: 16, child: pw.Text('Qty', textAlign: pw.TextAlign.center, style: pw.TextStyle(fontSize: _fontSizeSm, fontWeight: pw.FontWeight.bold, color: PdfColors.black))),
                pw.SizedBox(width: 32, child: pw.Text('Harga', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: _fontSizeSm, fontWeight: pw.FontWeight.bold, color: PdfColors.black))),
                pw.SizedBox(width: 36, child: pw.Text('Total', textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: _fontSizeSm, fontWeight: pw.FontWeight.bold, color: PdfColors.black))),
              ]),
            ),
            _hr(),
            pw.SizedBox(height: 2),
            ...items.asMap().entries.map((entry) {
              final number = entry.key + 1;
              final item   = entry.value;
              return pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 4),
                child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.SizedBox(width: 14, child: pw.Text('$number.', style: const pw.TextStyle(fontSize: _fontSizeSm, color: PdfColors.black))),
                  pw.Expanded(child: pw.Text(item.name, style: const pw.TextStyle(fontSize: _fontSizeSm, color: PdfColors.black))),
                  pw.SizedBox(width: 16, child: pw.Text('${item.quantity}', textAlign: pw.TextAlign.center, style: const pw.TextStyle(fontSize: _fontSizeSm, color: PdfColors.black))),
                  pw.SizedBox(width: 32, child: pw.Text(CurrencyFormatter.format(item.price).replaceAll('Rp', '').trim(), textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: _fontSizeSm, color: PdfColors.black))),
                  pw.SizedBox(width: 36, child: pw.Text(CurrencyFormatter.format(item.subtotal).replaceAll('Rp', '').trim(), textAlign: pw.TextAlign.right, style: const pw.TextStyle(fontSize: _fontSizeSm, color: PdfColors.black))),
                ]),
              );
            }),
            _hr(),
            pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
              pw.Row(children: [pw.SizedBox(width: 55, child: pw.Text('Total Item', style: const pw.TextStyle(fontSize: _fontSize, color: PdfColors.black))), pw.Text(': ${items.length}', style: const pw.TextStyle(fontSize: _fontSize, color: PdfColors.black))]),
              pw.SizedBox(height: 2),
              pw.Row(children: [pw.SizedBox(width: 55, child: pw.Text('Total Qty', style: const pw.TextStyle(fontSize: _fontSize, color: PdfColors.black))), pw.Text(': $totalQty', style: const pw.TextStyle(fontSize: _fontSize, color: PdfColors.black))]),
            ]),
            pw.SizedBox(height: 2),
            _hr(),
            _infoRow('Subtotal', CurrencyFormatter.format(subtotal)),
            if (discount > 0) _infoRow(
              discountPercent > 0
                  ? 'Diskon ${discountPercent.toStringAsFixed(0)}%'
                  : 'Diskon',
              CurrencyFormatter.format(discount)),
            if (tax > 0) _infoRow('Pajak ${taxPercent.toStringAsFixed(0)}%', CurrencyFormatter.format(tax)),
            pw.SizedBox(height: 2),
            _hr(),
            pw.Row(mainAxisAlignment: pw.MainAxisAlignment.spaceBetween, children: [
              pw.Text('TOTAL', style: pw.TextStyle(fontSize: _fontSizeXl, fontWeight: pw.FontWeight.normal, color: PdfColors.black)),
              pw.Text(CurrencyFormatter.format(total), style: pw.TextStyle(fontSize: _fontSizeXl, fontWeight: pw.FontWeight.normal, color: PdfColors.black)),
            ]),
            pw.SizedBox(height: 2),
            _hr(),
            if (amountPaid != null) _infoRow('Dibayar', CurrencyFormatter.format(amountPaid)),
            if (change != null && change > 0) _infoRow('KEMBALI', CurrencyFormatter.format(change), boldValue: true),
            pw.SizedBox(height: 2),
            _hr(),
            pw.SizedBox(height: 2),
            pw.Text(storeNote.isNotEmpty ? storeNote : 'Terima kasih telah berbelanja', style: pw.TextStyle(fontSize: _fontSize, fontWeight: pw.FontWeight.bold, color: PdfColors.black), textAlign: pw.TextAlign.center),
            pw.SizedBox(height: 2),
            pw.Text('Simpan struk ini sebagai bukti pembelian', style: const pw.TextStyle(fontSize: _fontSizeSm, color: PdfColors.black), textAlign: pw.TextAlign.center),
            pw.SizedBox(height: 6),
            if (footerLogoImage != null) ...[
              pw.Center(child: pw.Image(footerLogoImage, width: 60, fit: pw.BoxFit.contain)),
              pw.SizedBox(height: 3),
            ],
            pw.Text('Link Kritik dan Saran', style: const pw.TextStyle(fontSize: _fontSizeSm, color: PdfColors.black), textAlign: pw.TextAlign.center),
            pw.Text('https://KasirkuPro.shop/reports', style: pw.TextStyle(fontSize: _fontSizeSm, fontWeight: pw.FontWeight.bold, color: PdfColors.black), textAlign: pw.TextAlign.center),
            pw.SizedBox(height: 4),
            _hr(),
          ],
        );
      },
    ));
    return doc.save();
  }

  static pw.Widget _hr() => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 3),
        child: pw.Text(_divider, textAlign: pw.TextAlign.center, maxLines: 1, overflow: pw.TextOverflow.clip, style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.black)),
      );

  static pw.Widget _infoRow(String label, String value, {bool boldValue = false}) => pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 2),
        child: pw.Row(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.SizedBox(width: 62, child: pw.Text(label, style: const pw.TextStyle(fontSize: _fontSize, color: PdfColors.black))),
          pw.Text(': ', style: const pw.TextStyle(fontSize: _fontSize, color: PdfColors.black)),
          pw.Expanded(child: pw.Text(value, textAlign: pw.TextAlign.right, style: pw.TextStyle(fontSize: _fontSize, fontWeight: boldValue ? pw.FontWeight.bold : pw.FontWeight.normal, color: PdfColors.black))),
        ]),
      );
}
