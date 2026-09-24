// lib/core/utils/pin_hasher.dart
//
// SECURITY PATCH: Ganti SHA-256 tanpa salt → PBKDF2-SHA256 dengan salt acak.
//
// Mengapa PBKDF2?
// - SHA-256(pin) sangat cepat → brute-force/rainbow table trivial.
// - PBKDF2 + salt: setiap hash unik, 100.000 iterasi membuat brute-force
//   jutaan kali lebih lambat tanpa hardware GPU khusus.
// - Tersedia via package `pointycastle` tanpa dependensi native.
//
// Format penyimpanan di DB:
//   "$pbkdf2$<iterations>$<salt_hex>$<hash_hex>"
// Contoh:
//   "$pbkdf2$100000$a3f9b1c2...$d8e7f6a5..."
//
// MIGRASI dari SHA-256 lama:
//   - Deteksi: jika stored hash TIDAK diawali "$pbkdf2$", anggap SHA-256 lama.
//   - Saat login berhasil (cocok SHA-256): re-hash dengan PBKDF2, simpan ulang.
//   - Setelah semua user login setidaknya sekali, tidak ada lagi hash lama.

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart';

class PinHasher {
  static const _prefix = r'$pbkdf2$';
  static const _iterations = 100000;
  static const _keyLength = 32; // 256-bit output
  static const _saltLength = 16; // 128-bit salt

  /// Hash PIN baru dengan PBKDF2 + salt acak.
  /// Selalu gunakan ini saat membuat atau mengganti PIN.
  static String hashPin(String pin) {
    final salt = _generateSalt();
    final hash = _pbkdf2(utf8.encode(pin), salt, _iterations, _keyLength);
    return '$_prefix$_iterations\$${_hex(salt)}\$${_hex(hash)}';
  }

  /// Verifikasi PIN terhadap stored hash.
  /// Mendukung format lama (SHA-256) dan format baru (PBKDF2).
  ///
  /// Return [VerifyResult] yang juga menyertakan apakah hash perlu di-upgrade.
  static VerifyResult verifyPin(String pin, String storedHash) {
    if (storedHash.startsWith(_prefix)) {
      return _verifyPbkdf2(pin, storedHash);
    } else {
      // Legacy: SHA-256 tanpa salt
      return _verifyLegacySha256(pin, storedHash);
    }
  }

  // ── Internal ────────────────────────────────────────────────────────────────

  static VerifyResult _verifyPbkdf2(String pin, String stored) {
    try {
      final parts = stored.split(r'$');
      // Format: ['', 'pbkdf2', iterations, salt_hex, hash_hex]
      if (parts.length != 5) return const VerifyResult(match: false);
      final iter = int.tryParse(parts[2]);
      if (iter == null) return const VerifyResult(match: false);
      final salt = _fromHex(parts[3]);
      final expected = _fromHex(parts[4]);
      final actual = _pbkdf2(utf8.encode(pin), salt, iter, _keyLength);
      final match = _constantTimeEqual(actual, expected);
      // Re-hash jika iterasi lama (upgrade keamanan otomatis)
      final needsUpgrade = match && iter < _iterations;
      return VerifyResult(match: match, needsUpgrade: needsUpgrade);
    } catch (_) {
      return const VerifyResult(match: false);
    }
  }

  static VerifyResult _verifyLegacySha256(String pin, String stored) {
    final hashed = sha256.convert(utf8.encode(pin)).toString();
    final match = hashed == stored;
    // Jika cocok dengan SHA-256 lama → perlu upgrade ke PBKDF2
    return VerifyResult(match: match, needsUpgrade: match);
  }

  static Uint8List _generateSalt() {
    final rng = Random.secure();
    return Uint8List.fromList(
        List.generate(_saltLength, (_) => rng.nextInt(256)));
  }

  static Uint8List _pbkdf2(
    List<int> password,
    Uint8List salt,
    int iterations,
    int keyLength,
  ) {
    final params = Pbkdf2Parameters(salt, iterations, keyLength);
    final prf = Mac('SHA-256/HMAC');
    final kdf = PBKDF2KeyDerivator(prf);
    kdf.init(params);
    return kdf.process(Uint8List.fromList(password));
  }

  /// Perbandingan constant-time untuk mencegah timing attack
  static bool _constantTimeEqual(Uint8List a, Uint8List b) {
    if (a.length != b.length) return false;
    var result = 0;
    for (var i = 0; i < a.length; i++) {
      result |= a[i] ^ b[i];
    }
    return result == 0;
  }

  static String _hex(Uint8List bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

  static Uint8List _fromHex(String hex) {
    final length = hex.length;
    final result = Uint8List(length ~/ 2);
    for (var i = 0; i < length; i += 2) {
      result[i ~/ 2] = int.parse(hex.substring(i, i + 2), radix: 16);
    }
    return result;
  }
}

/// Hasil verifikasi PIN
class VerifyResult {
  final bool match;
  /// true jika hash perlu di-upgrade (dari SHA-256 ke PBKDF2, atau iterasi lama)
  final bool needsUpgrade;

  const VerifyResult({required this.match, this.needsUpgrade = false});
}

// ─── Helper untuk dijalankan di isolate terpisah via compute() ────────────────
//
// PBKDF2 100.000 iterasi (pure-Dart, via pointycastle) cukup berat secara CPU
// dan jika dijalankan langsung di main thread akan membuat UI freeze sesaat
// (terasa seperti "buffering") saat user menekan tombol Masuk / Simpan PIN.
// Dengan compute(), komputasi ini dipindah ke isolate terpisah sehingga UI
// tetap responsif (misal menampilkan loading indicator).

/// Argumen untuk verifikasi PIN di isolate terpisah.
class PinVerifyArgs {
  final String pin;
  final String storedHash;
  const PinVerifyArgs(this.pin, this.storedHash);
}

/// Top-level function — wajib top-level/static agar bisa dipakai dengan compute().
/// Panggil dengan: `await compute(verifyPinIsolate, PinVerifyArgs(pin, storedHash))`
VerifyResult verifyPinIsolate(PinVerifyArgs args) =>
    PinHasher.verifyPin(args.pin, args.storedHash);

/// Argumen untuk hashing PIN baru di isolate terpisah.
class PinHashArgs {
  final String pin;
  const PinHashArgs(this.pin);
}

/// Panggil dengan: `await compute(hashPinIsolate, PinHashArgs(pin))`
String hashPinIsolate(PinHashArgs args) => PinHasher.hashPin(args.pin);
