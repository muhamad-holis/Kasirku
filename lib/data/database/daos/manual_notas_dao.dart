part of '../app_database.dart';

@DriftAccessor(tables: [ManualNotas])
class ManualNotasDao extends DatabaseAccessor<AppDatabase>
    with _$ManualNotasDaoMixin {
  ManualNotasDao(super.db);

  Future<List<ManualNota>> getAll({int limit = 100}) => (select(manualNotas)
        ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
        ..limit(limit))
      .get();

  Stream<List<ManualNota>> watchAll({int limit = 100}) => (select(manualNotas)
        ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
        ..limit(limit))
      .watch();

  Future<List<ManualNota>> getBetween(DateTime start, DateTime end) =>
      (select(manualNotas)
            ..where((t) => t.createdAt.isBiggerOrEqualValue(start) &
                t.createdAt.isSmallerThanValue(end))
            ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
          .get();

  Future<ManualNota?> getById(int id) =>
      (select(manualNotas)..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<int> insertNota(ManualNotasCompanion nota) =>
      into(manualNotas).insert(nota);

  /// Versi reaktif dari [getBetween] — dipakai di Riwayat Transaksi supaya
  /// nota manual baru langsung muncul tanpa perlu keluar-masuk tab lagi.
  Stream<List<ManualNota>> watchBetween(DateTime start, DateTime end) =>
      (select(manualNotas)
        ..where((t) => t.createdAt.isBetweenValues(start, end))
        ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
          .watch();

  /// Versi reaktif "hari ini" untuk Dashboard — pola sama seperti
  /// TransactionsDao.watchTodayTransactions (loop ulang tiap tengah malam).
  Stream<List<ManualNota>> watchToday() async* {
    while (true) {
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day);
      final end = start.add(const Duration(days: 1));
      final secondsUntilMidnight = end.difference(now).inSeconds + 1;

      bool timedOut = false;
      await for (final notaList in (select(manualNotas)
            ..where((t) => t.createdAt.isBetweenValues(start, end))
            ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
          .watch()
          .timeout(
            Duration(seconds: secondsUntilMidnight),
            onTimeout: (sink) {
              timedOut = true;
              sink.close();
            },
          )) {
        yield notaList;
      }
      if (!timedOut) break;
    }
  }

  Future<void> deleteNota(int id) =>
      (delete(manualNotas)..where((t) => t.id.equals(id))).go();

  /// Update sebagian kolom nota manual yang sudah ada (dipakai saat Edit dari
  /// Riwayat Transaksi). invoiceNumber & createdAt sengaja TIDAK ikut diubah
  /// di sini — pemanggil cukup kirim kolom yang berubah lewat [nota].
  Future<int> updateNota(int id, ManualNotasCompanion nota) =>
      (update(manualNotas)..where((t) => t.id.equals(id))).write(nota);

  /// Nomor nota manual berikutnya, format NM000001, disimpan lewat
  /// SettingsDao (key-value) agar tidak perlu tabel/kolom counter terpisah.
  Future<String> nextInvoiceNumber() async {
    const key = 'manual_nota_last_number';
    final current =
        int.tryParse(await attachedDatabase.settingsDao.getSetting(key) ?? '0') ?? 0;
    final next = current + 1;
    await attachedDatabase.settingsDao.setSetting(key, next.toString());
    return 'NM${next.toString().padLeft(6, '0')}';
  }
}
