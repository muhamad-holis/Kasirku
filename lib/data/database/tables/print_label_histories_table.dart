part of '../app_database.dart';

/// Riwayat cetak label harga (menu "Cetak Label") — snapshot tiap kali
/// label dicetak, memakai nama+harga dari tabel Products (Stok) yang sama
/// dengan yang dipakai Kasir & Nota Manual.
class PrintLabelHistories extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get productName => text()();
  TextColumn get unit => text()();
  RealColumn get price => real()();
  IntColumn get quantity => integer()();
  DateTimeColumn get printedAt => dateTime().withDefault(currentDateAndTime)();
}
