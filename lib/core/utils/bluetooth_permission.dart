import 'package:permission_handler/permission_handler.dart';

/// Minta izin runtime Bluetooth (Connect & Scan) yang WAJIB diminta secara
/// eksplisit di Android 12+ (API 31+) sebelum memanggil
/// `PrintBluetoothThermal.pairedBluetooths` / `.connect` / dsb.
///
/// Deklarasi di AndroidManifest.xml saja TIDAK CUKUP untuk API 31+ — tanpa
/// permintaan izin runtime ini, daftar printer akan selalu kosong/macet
/// tanpa error yang jelas ke user.
///
/// Aman dipanggil di semua versi Android: di Android <12, permission ini
/// otomatis granted begitu ada di Manifest, jadi request ini langsung
/// selesai tanpa dialog.
Future<bool> ensureBluetoothPermission() async {
  final statuses = await [
    Permission.bluetoothConnect,
    Permission.bluetoothScan,
  ].request();
  return statuses.values.every((s) => s.isGranted);
}
