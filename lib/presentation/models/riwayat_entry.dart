import 'dart:async';
import '../../data/database/app_database.dart';

/// Jenis entri riwayat — transaksi Kasir Otomatis (tabel `transactions`)
/// atau Nota Manual (tabel `manual_notas`). Dipakai bersama oleh Dashboard
/// ("Transaksi Terakhir") dan layar Riwayat Transaksi supaya keduanya
/// menampilkan gabungan data yang sama & konsisten.
enum RiwayatKind { transaksi, manual }

/// Wrapper supaya Transaction & ManualNota bisa digabung dalam satu daftar
/// terurut waktu tanpa mengubah dua model Drift tersebut.
class RiwayatEntry {
  final RiwayatKind kind;
  final DateTime createdAt;
  final String invoiceNumber;
  final double total;
  final Transaction? tx;
  final ManualNota? nota;

  RiwayatEntry.transaksi(Transaction t)
      : kind = RiwayatKind.transaksi,
        createdAt = t.createdAt,
        invoiceNumber = t.invoiceNumber,
        total = t.total,
        tx = t,
        nota = null;

  RiwayatEntry.manual(ManualNota n)
      : kind = RiwayatKind.manual,
        createdAt = n.createdAt,
        invoiceNumber = n.invoiceNumber,
        total = n.total,
        tx = null,
        nota = n;
}

/// Gabungkan stream transaksi otomatis + nota manual jadi SATU stream
/// daftar `RiwayatEntry` yang ter-urut waktu & ter-update otomatis setiap
/// salah satu sumber berubah (tanpa perlu dependency rxdart).
///
/// Menunggu kedua stream sumber mengeluarkan data pertamanya dulu sebelum
/// emit gabungan pertama — setelah itu, setiap kali salah satu stream
/// emit lagi, hasil gabungan langsung di-emit ulang pakai data terbaru
/// dari kedua sumber.
Stream<List<RiwayatEntry>> combineRiwayat(
  Stream<List<Transaction>> txStream,
  Stream<List<ManualNota>> notaStream,
) {
  List<Transaction> lastTx = const [];
  List<ManualNota> lastNota = const [];
  bool hasTx = false, hasNota = false;
  StreamSubscription<List<Transaction>>? sub1;
  StreamSubscription<List<ManualNota>>? sub2;
  late StreamController<List<RiwayatEntry>> controller;

  void emit() {
    if (!hasTx || !hasNota) return;
    final entries = <RiwayatEntry>[
      ...lastTx.map((t) => RiwayatEntry.transaksi(t)),
      ...lastNota.map((n) => RiwayatEntry.manual(n)),
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    controller.add(entries);
  }

  controller = StreamController<List<RiwayatEntry>>(
    onListen: () {
      sub1 = txStream.listen((v) {
        lastTx = v; hasTx = true; emit();
      }, onError: controller.addError);
      sub2 = notaStream.listen((v) {
        lastNota = v; hasNota = true; emit();
      }, onError: controller.addError);
    },
    onCancel: () async {
      await sub1?.cancel();
      await sub2?.cancel();
    },
  );
  return controller.stream;
}
