// lib/presentation/providers/kas_provider.dart
// ─────────────────────────────────────────────────────────────────────────────
// Provider untuk: Kas Masuk & Kas Keluar, Laporan Arus Kas, Laporan Laba Rugi
// Menggunakan tabel & DAO yang sudah ada (cash_flows, transactions,
// transaction_items, products). Tidak mengubah struktur database.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'database_provider.dart';

// ─── Model: Rentang Tanggal ───────────────────────────────────────────────────

class DateRange {
  final DateTime start;
  final DateTime end;
  const DateRange({required this.start, required this.end});

  @override
  bool operator ==(Object other) =>
      other is DateRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);
}

// ─── Model: Ringkasan Kas ─────────────────────────────────────────────────────

class KasSummary {
  final double totalIncome;
  final double totalExpense;
  final double saldo;

  const KasSummary({
    required this.totalIncome,
    required this.totalExpense,
    required this.saldo,
  });
}

// ─── Model: Laporan Laba Rugi ─────────────────────────────────────────────────

class LabaRugiData {
  /// Omzet penjualan (dari tabel transactions, status=completed)
  final double omzet;

  /// HPP = SUM(buy_price * quantity) dari transaction_items JOIN products
  final double hpp;

  /// Kas masuk selain kategori 'penjualan'
  final double kasIncomeNonSales;

  /// Kas keluar operasional (semua expense)
  final double kasExpense;

  /// Margin persen laba bersih
  final double marginPersen;

  /// Laba kotor = omzet - hpp
  double get labaKotor => omzet - hpp;

  /// Laba bersih = labaKotor + kasIncomeNonSales - kasExpense
  double get labaBersih => labaKotor + kasIncomeNonSales - kasExpense;

  const LabaRugiData({
    required this.omzet,
    required this.hpp,
    required this.kasIncomeNonSales,
    required this.kasExpense,
    required this.marginPersen,
  });

  factory LabaRugiData.fromMap(Map<String, double> m) {
    return LabaRugiData(
      omzet: m['omzet'] ?? 0,
      hpp: m['hpp'] ?? 0,
      kasIncomeNonSales: m['kas_income_non_sales'] ?? 0,
      kasExpense: m['kas_expense'] ?? 0,
      marginPersen: m['margin_persen'] ?? 0,
    );
  }
}

// ─── Model: Arus Kas Harian (untuk grafik) ───────────────────────────────────

class ArusKasHarian {
  final String tanggal;
  final double masuk;
  final double keluar;

  double get saldo => masuk - keluar;

  const ArusKasHarian({
    required this.tanggal,
    required this.masuk,
    required this.keluar,
  });
}

// ─── Model: Kas per Kategori (untuk pie chart / breakdown) ───────────────────

class KasKategori {
  final String kategori;
  final double total;
  final int jumlah;

  const KasKategori({
    required this.kategori,
    required this.total,
    required this.jumlah,
  });
}

// ─── Providers ────────────────────────────────────────────────────────────────

/// Ringkasan kas: total masuk, keluar, saldo dalam rentang tanggal
final kasSummaryProvider =
    FutureProvider.family<KasSummary, DateRange>((ref, range) async {
  final db = ref.watch(databaseProvider);
  final report = await db.reportsDao.getCashReport(range.start, range.end);
  return KasSummary(
    totalIncome: report['income'] ?? 0,
    totalExpense: report['expense'] ?? 0,
    saldo: report['saldo'] ?? 0,
  );
});

/// Laporan Laba Rugi lengkap (omzet, HPP, laba kotor, laba bersih, margin)
final labaRugiProvider =
    FutureProvider.family<LabaRugiData, DateRange>((ref, range) async {
  final db = ref.watch(databaseProvider);
  final result =
      await db.reportsDao.getLabaRugiReport(range.start, range.end);
  return LabaRugiData.fromMap(result);
});

/// Arus kas harian dalam rentang tanggal (untuk grafik batang)
final arusKasHarianProvider =
    FutureProvider.family<List<ArusKasHarian>, DateRange>((ref, range) async {
  final db = ref.watch(databaseProvider);
  final rows =
      await db.reportsDao.getDailyCashFlowChart(range.start, range.end);
  return rows.map((r) {
    return ArusKasHarian(
      tanggal: r['tanggal'] as String,
      masuk: (r['total_masuk'] as num).toDouble(),
      keluar: (r['total_keluar'] as num).toDouble(),
    );
  }).toList();
});

/// Breakdown kas masuk per kategori
final kasIncomeByKategoriProvider =
    FutureProvider.family<List<KasKategori>, DateRange>((ref, range) async {
  final db = ref.watch(databaseProvider);
  final rows = await db.reportsDao
      .getCashFlowByCategory(range.start, range.end, 'income');
  return rows.map((r) {
    return KasKategori(
      kategori: r['category'] as String,
      total: (r['total'] as num).toDouble(),
      jumlah: (r['jumlah'] as num).toInt(),
    );
  }).toList();
});

/// Breakdown kas keluar per kategori
final kasExpenseByKategoriProvider =
    FutureProvider.family<List<KasKategori>, DateRange>((ref, range) async {
  final db = ref.watch(databaseProvider);
  final rows = await db.reportsDao
      .getCashFlowByCategory(range.start, range.end, 'expense');
  return rows.map((r) {
    return KasKategori(
      kategori: r['category'] as String,
      total: (r['total'] as num).toDouble(),
      jumlah: (r['jumlah'] as num).toInt(),
    );
  }).toList();
});

/// Ringkasan kas hari ini (untuk widget dashboard)
final kasHariIniProvider = FutureProvider<KasSummary>((ref) async {
  final now = DateTime.now();
  final start = DateTime(now.year, now.month, now.day);
  final end = start.add(const Duration(days: 1));
  return ref
      .watch(kasSummaryProvider(DateRange(start: start, end: end)).future);
});

/// Laba rugi hari ini (untuk widget dashboard)
final labaRugiHariIniProvider = FutureProvider<LabaRugiData>((ref) async {
  final now = DateTime.now();
  final start = DateTime(now.year, now.month, now.day);
  final end = start.add(const Duration(days: 1));
  return ref
      .watch(labaRugiProvider(DateRange(start: start, end: end)).future);
});

// ─── Helper: label kategori kas ───────────────────────────────────────────────

String labelKategoriKas(String cat) {
  const labels = {
    'penjualan': 'Penjualan',
    'Penjualan': 'Penjualan',
    'pelunasan_hutang': 'Pelunasan Hutang',
    'modal': 'Tambah Modal',
    'Modal Awal': 'Modal Awal',
    'Pinjaman': 'Pinjaman',
    'lain': 'Lain-lain',
    'Lainnya': 'Lain-lain',
    'operasional': 'Biaya Operasional',
    'Biaya Operasional': 'Biaya Operasional',
    'pembelian_stok': 'Pembelian Stok',
    'Pembelian Stok': 'Pembelian Stok',
    'gaji': 'Gaji Karyawan',
    'Gaji': 'Gaji Karyawan',
    'sewa': 'Biaya Sewa',
    'listrik_air': 'Listrik & Air',
    'Utilitas': 'Utilitas',
  };
  return labels[cat] ?? cat;
}
