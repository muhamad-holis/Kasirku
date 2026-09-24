import 'dart:typed_data';
import 'dart:math' as math;
import 'package:audioplayers/audioplayers.dart';

/// Service suara beep untuk scanner & notifikasi.
/// WAV di-generate langsung di memory — tidak butuh file aset.
class SoundService {
  SoundService._();
  static final SoundService instance = SoundService._();

  AudioPlayer? _player;

  Future<void> _play(Uint8List wavBytes) async {
    try {
      _player ??= AudioPlayer();
      await _player!.stop();
      await _player!.play(BytesSource(wavBytes));
    } catch (_) {}
  }

  /// Beep sukses — scan barcode ditemukan (1200 Hz, 120 ms)
  Future<void> beepScan() => _play(_buildBeep(1200, 0.12));

  /// Beep error — barcode tidak ditemukan (400 Hz, 280 ms)
  Future<void> beepError() => _play(_buildBeep(400, 0.28));

  /// Ding notifikasi — bell ringan (880 Hz → 660 Hz, 180 ms)
  Future<void> beepNotif() => _play(_buildBeep(880, 0.18));

  void dispose() {
    _player?.dispose();
    _player = null;
  }

  // ── WAV generator (PCM 16-bit mono 44100 Hz) ──────────────────────────────
  static Uint8List _buildBeep(int freqHz, double durSec) {
    const sr = 44100;
    final n = (sr * durSec).toInt();
    final dataBytes = n * 2;

    final buf = ByteData(44 + dataBytes);
    int o = 0;

    // RIFF header
    buf.buffer.asUint8List().setRange(0, 4, 'RIFF'.codeUnits); o = 4;
    buf.setUint32(o, 36 + dataBytes, Endian.little); o += 4;
    buf.buffer.asUint8List().setRange(o, o + 4, 'WAVE'.codeUnits); o += 4;
    buf.buffer.asUint8List().setRange(o, o + 4, 'fmt '.codeUnits); o += 4;
    buf.setUint32(o, 16, Endian.little); o += 4;   // chunk size
    buf.setUint16(o, 1,  Endian.little); o += 2;   // PCM
    buf.setUint16(o, 1,  Endian.little); o += 2;   // mono
    buf.setUint32(o, sr, Endian.little); o += 4;   // sample rate
    buf.setUint32(o, sr * 2, Endian.little); o += 4; // byte rate
    buf.setUint16(o, 2,  Endian.little); o += 2;   // block align
    buf.setUint16(o, 16, Endian.little); o += 2;   // bits/sample
    buf.buffer.asUint8List().setRange(o, o + 4, 'data'.codeUnits); o += 4;
    buf.setUint32(o, dataBytes, Endian.little); o += 4;

    // PCM samples — sine dengan fade-out eksponensial
    for (int i = 0; i < n; i++) {
      final t = i / sr;
      final fade = math.exp(-4.0 * i / n);          // smooth fade out
      final v = (32767 * 0.7 * fade *
              math.sin(2 * math.pi * freqHz * t))
          .toInt()
          .clamp(-32768, 32767);
      buf.setInt16(o, v, Endian.little);
      o += 2;
    }

    return buf.buffer.asUint8List();
  }
}
