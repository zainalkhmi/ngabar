import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

/// CamcorderSoundHelper
///
/// Generates and plays the iconic retro handycam/camcorder "cling/beep" sound
/// when recording starts or stops.
///
/// Synthesized dynamically using pure PCM 16-bit stereo WAV so:
/// 1. Zero external assets required (zero APK size increase).
/// 2. Works offline, on Android, iOS, Windows, and Web.
/// 3. Zero latency instant playback via an optimized in-memory [AudioPlayer].
class CamcorderSoundHelper {
  CamcorderSoundHelper._();
  static final CamcorderSoundHelper instance = CamcorderSoundHelper._();

  AudioPlayer? _player;
  Uint8List? _startChimeWav;
  Uint8List? _stopChimeWav;

  Future<void> init() async {
    try {
      _startChimeWav ??= _synthesizeCamcorderChime(isStart: true);
      _stopChimeWav ??= _synthesizeCamcorderChime(isStart: false);
      _player ??= AudioPlayer();
    } catch (_) {}
  }

  /// Plays the iconic camcorder recording "cling" sound.
  Future<void> playRecordChime({required bool isStart}) async {
    try {
      // Haptic feedback first for instant tactile sensation
      if (isStart) {
        HapticFeedback.mediumImpact();
      } else {
        HapticFeedback.lightImpact();
      }

      // Also trigger system click sound
      SystemSound.play(SystemSoundType.click);

      _startChimeWav ??= _synthesizeCamcorderChime(isStart: true);
      _stopChimeWav ??= _synthesizeCamcorderChime(isStart: false);

      final bytes = isStart ? _startChimeWav! : _stopChimeWav!;
      _player ??= AudioPlayer();

      await _player!.setAudioSource(_InMemoryAudioSource(bytes));
      await _player!.play();
    } catch (_) {
      // Graceful fallback to SystemSound if hardware audio engine is busy
      SystemSound.play(SystemSoundType.click);
    }
  }

  /// Synthesizes a crisp, glassy 2-tone "cling" beep (e.g. 1760Hz -> 2637Hz / A6 -> E7).
  /// For start: Low -> High crisp bell tone.
  /// For stop: High -> Low crisp tone.
  static Uint8List _synthesizeCamcorderChime({required bool isStart}) {
    const int sampleRate = 44100;
    final double tone1Freq = isStart ? 1760.0 : 2637.0; // A6 or E7
    final double tone2Freq = isStart ? 2637.0 : 1760.0; // E7 or A6
    const double toneDuration = 0.045; // 45ms per tone
    final int samplesPerTone = (sampleRate * toneDuration).toInt();
    final int totalSamples = samplesPerTone * 2;

    final Int16List pcmSamples = Int16List(totalSamples);

    for (int i = 0; i < samplesPerTone; i++) {
      final double t = i / sampleRate;
      // Exponential decay envelope for crisp bell/metallic hit
      final double env = math.exp(-i / (samplesPerTone * 0.45));
      final double sample = math.sin(2 * math.pi * tone1Freq * t) * env;
      pcmSamples[i] = (sample * 24000).clamp(-32768, 32767).toInt();
    }

    for (int i = 0; i < samplesPerTone; i++) {
      final double t = i / sampleRate;
      final double env = math.exp(-i / (samplesPerTone * 0.55));
      final double sample = math.sin(2 * math.pi * tone2Freq * t) * env;
      pcmSamples[samplesPerTone + i] = (sample * 28000).clamp(-32768, 32767).toInt();
    }

    return _createWavContainer(pcmSamples, sampleRate);
  }

  static Uint8List _createWavContainer(Int16List pcmData, int sampleRate) {
    final int numChannels = 1;
    final int bitsPerSample = 16;
    final int byteRate = sampleRate * numChannels * (bitsPerSample ~/ 8);
    final int blockAlign = numChannels * (bitsPerSample ~/ 8);
    final int dataSize = pcmData.lengthInBytes;
    final int chunkSize = 36 + dataSize;

    final ByteData header = ByteData(44);

    // RIFF chunk descriptor
    header.setUint8(0, 0x52); // 'R'
    header.setUint8(1, 0x49); // 'I'
    header.setUint8(2, 0x46); // 'F'
    header.setUint8(3, 0x46); // 'F'
    header.setUint32(4, chunkSize, Endian.little);
    header.setUint8(8, 0x57);  // 'W'
    header.setUint8(9, 0x41);  // 'A'
    header.setUint8(10, 0x56); // 'V'
    header.setUint8(11, 0x45); // 'E'

    // fmt sub-chunk
    header.setUint8(12, 0x66); // 'f'
    header.setUint8(13, 0x6D); // 'm'
    header.setUint8(14, 0x74); // 't'
    header.setUint8(15, 0x20); // ' '
    header.setUint32(16, 16, Endian.little); // Subchunk1Size (16 for PCM)
    header.setUint16(20, 1, Endian.little);  // AudioFormat (1 for PCM)
    header.setUint16(22, numChannels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, blockAlign, Endian.little);
    header.setUint16(34, bitsPerSample, Endian.little);

    // data sub-chunk
    header.setUint8(36, 0x64); // 'd'
    header.setUint8(37, 0x61); // 'a'
    header.setUint8(38, 0x74); // 't'
    header.setUint8(39, 0x61); // 'a'
    header.setUint32(40, dataSize, Endian.little);

    final Uint8List wavBytes = Uint8List(44 + dataSize);
    wavBytes.setRange(0, 44, header.buffer.asUint8List());
    wavBytes.setRange(44, 44 + dataSize, pcmData.buffer.asUint8List());

    return wavBytes;
  }
}

class _InMemoryAudioSource extends StreamAudioSource {
  final Uint8List _buffer;

  _InMemoryAudioSource(this._buffer) : super(tag: 'camcorder_chime');

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    start ??= 0;
    end ??= _buffer.length;
    return StreamAudioResponse(
      sourceLength: _buffer.length,
      contentLength: end - start,
      offset: start,
      stream: Stream.value(_buffer.sublist(start, end)),
      contentType: 'audio/wav',
    );
  }
}
