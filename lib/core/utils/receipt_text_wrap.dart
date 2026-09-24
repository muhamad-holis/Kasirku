import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';

/// Word-wrap teks untuk printer thermal ESC/POS.
///
/// `generator.text()` dari esc_pos_utils_plus akan wrap teks yang lebih
/// panjang dari lebar kertas, TAPI wrap-nya asal potong per-karakter tanpa
/// mikirin batas kata — hasilnya kata bisa kepotong di tengah (mis. "Toko
/// Subur Makmur" jadi "...Makmu" + "r" sendirian di baris baru).
///
/// Fungsi ini pecah teks jadi beberapa baris SEBELUM dikirim ke
/// `generator.text()`, dengan wrap di antara kata (bukan di tengah kata),
/// supaya hasil cetak rapi.
List<String> wrapReceiptText(String text, {
  required PaperSize paperSize,
  bool doubleWidth = false,
}) {
  final maxChars = _maxCharsPerLine(paperSize, doubleWidth);
  final words = text.trim().split(RegExp(r'\s+'));
  final lines = <String>[];
  var current = '';

  for (final word in words) {
    if (word.isEmpty) continue;
    final candidate = current.isEmpty ? word : '$current $word';
    if (candidate.length <= maxChars) {
      current = candidate;
    } else {
      if (current.isNotEmpty) lines.add(current);
      // Kata tunggal yang lebih panjang dari lebar kertas (jarang terjadi,
      // mis. nomor invoice/URL panjang) — potong paksa per-chunk supaya
      // tidak bikin printer error, daripada dibiarkan meluber.
      if (word.length > maxChars) {
        for (var i = 0; i < word.length; i += maxChars) {
          final end = (i + maxChars < word.length) ? i + maxChars : word.length;
          lines.add(word.substring(i, end));
        }
        current = '';
      } else {
        current = word;
      }
    }
  }
  if (current.isNotEmpty) lines.add(current);
  return lines.isEmpty ? [''] : lines;
}

int _maxCharsPerLine(PaperSize paperSize, bool doubleWidth) {
  final normal = paperSize == PaperSize.mm80 ? 48 : 32;
  return doubleWidth ? (normal ~/ 2) : normal;
}
