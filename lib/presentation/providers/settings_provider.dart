import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'database_provider.dart';

// ─── Theme ────────────────────────────────────────────────────────────────────

final themeModeProvider =
    StateNotifierProvider<ThemeModeNotifier, bool>(
        (ref) => ThemeModeNotifier());

class ThemeModeNotifier extends StateNotifier<bool> {
  ThemeModeNotifier() : super(false) { _load(); }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    // Guard: notifier mungkin sudah di-dispose sebelum async selesai
    if (!mounted) return;
    state = prefs.getBool('dark_mode') ?? false;
  }

  Future<void> toggle() async {
    if (!mounted) return;
    final newVal = !state;
    state = newVal;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('dark_mode', newVal);
  }
}

// ─── Store Settings ───────────────────────────────────────────────────────────

// ─── Model Rekening Bank ─────────────────────────────────────────────────────

class BankAccount {
  final String id;         // uuid unik
  final String bankName;   // nama bank / e-wallet
  final String accountNumber;
  final String accountHolder;

  const BankAccount({
    required this.id,
    required this.bankName,
    required this.accountNumber,
    required this.accountHolder,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'bankName': bankName,
    'accountNumber': accountNumber,
    'accountHolder': accountHolder,
  };

  factory BankAccount.fromJson(Map<String, dynamic> j) => BankAccount(
    id:            j['id'] as String,
    bankName:      j['bankName'] as String,
    accountNumber: j['accountNumber'] as String,
    accountHolder: j['accountHolder'] as String,
  );
}

// ─── Store Settings ───────────────────────────────────────────────────────────

class StoreSettings {
  final String storeName;
  final String storeAddress;
  final String storePhone;
  final String storeNote;
  final String receiptSize;   // '58mm' | '80mm'
  final String currency;
  final bool showLogo;
  final bool printAfterTransaction;
  final String logoPath;
  final String qrisImagePath;        // path gambar QR code toko
  final List<BankAccount> bankAccounts; // daftar rekening transfer

  const StoreSettings({
    this.storeName            = 'KasirKu',
    this.storeAddress         = '',
    this.storePhone           = '',
    this.storeNote            = 'Terima kasih telah berbelanja!',
    this.receiptSize          = '58mm',
    this.currency             = 'Rp',
    this.showLogo             = true,
    this.printAfterTransaction = false,
    this.logoPath             = '',
    this.qrisImagePath        = '',
    this.bankAccounts         = const [],
  });

  StoreSettings copyWith({
    String? storeName,
    String? storeAddress,
    String? storePhone,
    String? storeNote,
    String? receiptSize,
    String? currency,
    bool? showLogo,
    bool? printAfterTransaction,
    String? logoPath,
    String? qrisImagePath,
    List<BankAccount>? bankAccounts,
  }) => StoreSettings(
    storeName:             storeName             ?? this.storeName,
    storeAddress:          storeAddress          ?? this.storeAddress,
    storePhone:            storePhone            ?? this.storePhone,
    storeNote:             storeNote             ?? this.storeNote,
    receiptSize:           receiptSize           ?? this.receiptSize,
    currency:              currency              ?? this.currency,
    showLogo:              showLogo              ?? this.showLogo,
    printAfterTransaction: printAfterTransaction ?? this.printAfterTransaction,
    logoPath:              logoPath              ?? this.logoPath,
    qrisImagePath:         qrisImagePath         ?? this.qrisImagePath,
    bankAccounts:          bankAccounts          ?? this.bankAccounts,
  );
}

class StoreSettingsNotifier extends StateNotifier<StoreSettings> {
  StoreSettingsNotifier(this._ref) : super(const StoreSettings()) {
    _load();
  }

  final Ref _ref;

  Future<void> _load() async {
    final db = _ref.read(databaseProvider);
    final all = await db.settingsDao.getAllSettings();
    final map = {for (final s in all) s.key: s.value ?? ''};
    // Parse daftar rekening dari JSON
    List<BankAccount> accounts = [];
    try {
      final raw = map['bank_accounts'] ?? '';
      if (raw.isNotEmpty) {
        final list = jsonDecode(raw) as List<dynamic>;
        accounts = list
            .map((e) => BankAccount.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}

    state = StoreSettings(
      storeName:             map['toko_nama']            ?? 'KasirKu',
      storeAddress:          map['toko_alamat']          ?? '',
      storePhone:            map['toko_telepon']         ?? '',
      storeNote:             map['struk_catatan']        ?? 'Terima kasih telah berbelanja!',
      receiptSize:           map['struk_ukuran']         ?? '58mm',
      currency:              map['mata_uang']            ?? 'Rp',
      showLogo:              map['struk_logo']           != 'false',
      printAfterTransaction: map['cetak_otomatis']       == 'true',
      logoPath:              map['logo_path']            ?? '',
      qrisImagePath:         map['qris_image_path']      ?? '',
      bankAccounts:          accounts,
    );
  }

  Future<void> save(StoreSettings s) async {
    state = s;
    final db = _ref.read(databaseProvider);
    final entries = {
      'toko_nama':       s.storeName,
      'toko_alamat':     s.storeAddress,
      'toko_telepon':    s.storePhone,
      'struk_catatan':   s.storeNote,
      'struk_ukuran':    s.receiptSize,
      'mata_uang':       s.currency,
      'struk_logo':      s.showLogo.toString(),
      'cetak_otomatis':  s.printAfterTransaction.toString(),
      'logo_path':       s.logoPath,
      'qris_image_path': s.qrisImagePath,
      'bank_accounts':   jsonEncode(s.bankAccounts.map((e) => e.toJson()).toList()),
    };
    for (final e in entries.entries) {
      await db.settingsDao.setSetting(e.key, e.value);
    }
  }

  Future<void> update(StoreSettings Function(StoreSettings) fn) =>
      save(fn(state));
}

final storeSettingsProvider =
    StateNotifierProvider<StoreSettingsNotifier, StoreSettings>(
        (ref) => StoreSettingsNotifier(ref));

// ─── Printer Settings ─────────────────────────────────────────────────────────

class PrinterSettings {
  final String? deviceName;
  final String? deviceAddress;
  final bool isConnected;

  const PrinterSettings({
    this.deviceName,
    this.deviceAddress,
    this.isConnected = false,
  });

  PrinterSettings copyWith({
    String? deviceName,
    String? deviceAddress,
    bool? isConnected,
  }) => PrinterSettings(
    deviceName:    deviceName    ?? this.deviceName,
    deviceAddress: deviceAddress ?? this.deviceAddress,
    isConnected:   isConnected   ?? this.isConnected,
  );
}

class PrinterSettingsNotifier extends StateNotifier<PrinterSettings> {
  PrinterSettingsNotifier() : super(const PrinterSettings()) { _load(); }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = PrinterSettings(
      deviceName:    prefs.getString('printer_name'),
      deviceAddress: prefs.getString('printer_address'),
      isConnected:   false,
    );
  }

  Future<void> setPrinter(String name, String address) async {
    state = state.copyWith(
        deviceName: name, deviceAddress: address);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('printer_name', name);
    await prefs.setString('printer_address', address);
  }

  Future<void> clearPrinter() async {
    state = const PrinterSettings();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('printer_name');
    await prefs.remove('printer_address');
  }
}

final printerSettingsProvider =
    StateNotifierProvider<PrinterSettingsNotifier, PrinterSettings>(
        (ref) => PrinterSettingsNotifier());

// ─── PIN Settings ─────────────────────────────────────────────────────────────

const _kPinKey = 'app_pin';

class PinNotifier extends StateNotifier<String?> {
  PinNotifier() : super(null) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getString(_kPinKey);
  }

  /// Simpan PIN baru. Mengembalikan true jika berhasil.
  Future<bool> setPin(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    final ok = await prefs.setString(_kPinKey, pin);
    if (ok) state = pin;
    return ok;
  }

  /// Hapus PIN (nonaktifkan keamanan PIN).
  Future<void> clearPin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPinKey);
    state = null;
  }

  /// Cek apakah PIN yang dimasukkan cocok.
  bool verify(String input) => state != null && input == state;

  bool get isActive => state != null && state!.isNotEmpty;
}

final pinProvider = StateNotifierProvider<PinNotifier, String?>(
  (ref) => PinNotifier(),
);

// ─── Biometric Settings ───────────────────────────────────────────────────────

const _kBiometricKey = 'biometric_enabled';

class BiometricNotifier extends StateNotifier<bool> {
  BiometricNotifier() : super(false) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    state = prefs.getBool(_kBiometricKey) ?? false;
  }

  Future<void> setEnabled(bool value) async {
    if (!mounted) return;
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kBiometricKey, value);
  }

  Future<void> disable() async {
    if (!mounted) return;
    state = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kBiometricKey);
  }
}

final biometricProvider = StateNotifierProvider<BiometricNotifier, bool>(
  (ref) => BiometricNotifier(),
);
