import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

/// Repeating attention beep for an incoming ride request — same approach
/// Microlab's driver_request_screen.dart uses: no bundled sound asset, the
/// tone is synthesized at runtime as raw PCM and played from bytes, so
/// there's nothing to add to pubspec assets or keep in sync per-platform.
///
/// One instance per request screen. Call [start] when the request appears
/// and [stop] the moment it's resolved (accepted/declined/timed out/
/// revoked) — [dispose] on top of that when the widget itself goes away.
class RequestBeepPlayer {
  final _player = AudioPlayer();
  Timer? _timer;

  /// Plays immediately, then repeats every [interval] until [stop].
  void start({Duration interval = const Duration(seconds: 2)}) {
    _playOnce();
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => _playOnce());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _player.stop();
  }

  void dispose() {
    _timer?.cancel();
    _player.dispose();
  }

  Future<void> _playOnce() async {
    try {
      await _player.play(BytesSource(_generateBeepWav()));
    } catch (_) {
      // Best-effort — a missing/broken audio backend should never take the
      // request screen down with it (haptics still fire independently).
    }
  }

  /// 880 Hz sine tone, 200 ms, linear fade-out — a plain 16-bit PCM mono WAV
  /// built by hand (44-byte header + samples), identical shape to Microlab's
  /// generator.
  static Uint8List _generateBeepWav() {
    const sampleRate = 44100;
    const frequency = 880.0;
    const durationSec = 0.2;
    final numSamples = (sampleRate * durationSec).round();
    final samples = Int16List(numSamples);
    for (int i = 0; i < numSamples; i++) {
      final t = i / sampleRate;
      final fade = 1.0 - (t / durationSec);
      samples[i] = (32767 * fade * math.sin(2 * math.pi * frequency * t)).round();
    }

    final bd = ByteData(44 + numSamples * 2);
    void writeStr(int offset, String s) {
      for (int i = 0; i < s.length; i++) {
        bd.setUint8(offset + i, s.codeUnitAt(i));
      }
    }

    writeStr(0, 'RIFF');
    bd.setUint32(4, 36 + numSamples * 2, Endian.little);
    writeStr(8, 'WAVE');
    writeStr(12, 'fmt ');
    bd.setUint32(16, 16, Endian.little);
    bd.setUint16(20, 1, Endian.little); // PCM
    bd.setUint16(22, 1, Endian.little); // mono
    bd.setUint32(24, sampleRate, Endian.little);
    bd.setUint32(28, sampleRate * 2, Endian.little); // byte rate
    bd.setUint16(32, 2, Endian.little); // block align
    bd.setUint16(34, 16, Endian.little); // bits per sample
    writeStr(36, 'data');
    bd.setUint32(40, numSamples * 2, Endian.little);
    for (int i = 0; i < numSamples; i++) {
      bd.setInt16(44 + i * 2, samples[i], Endian.little);
    }
    return bd.buffer.asUint8List();
  }
}
