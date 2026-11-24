import 'dart:async';
import 'dart:io' as io;
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';

import '../core/app_state.dart';

/// CamcorderSoundHelper
///
/// Generates and plays:
/// 1. The iconic retro handycam/camcorder "cling/beep" sound when recording starts or stops.
/// 2. Haptic and acoustic warning feedback (sound + vibration) when a recitation error is detected.
///
/// Synthesized dynamically using pure PCM 16-bit WAV so:
/// - Zero external assets required (zero APK size increase).
/// - Works offline, on Android, iOS, Windows, and Web.
/// - Instant zero-latency playback via pre-loaded and sonification-configured [AudioPlayer] instances.
class CamcorderSoundHelper {
  CamcorderSoundHelper._();
  static final CamcorderSoundHelper instance = CamcorderSoundHelper._();

  AudioPlayer? _startPlayer;
  AudioPlayer? _stopPlayer;
  AudioPlayer? _mistakePlayer;

  Uint8List? _startChimeWav;
  Uint8List? _stopChimeWav;
  Uint8List? _mistakeAlertWav;

  bool _initialized = false;
  int _lastMistakeAlertTime = 0;

  /// Preloads audio players and pre-synthesizes all audio buffers.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    try {
      _startChimeWav = _synthesizeCamcorderChime(isStart: true);
      _stopChimeWav = _synthesizeCamcorderChime(isStart: false);
      _mistakeAlertWav = _synthesizeMistakeAlert();

      _startPlayer = AudioPlayer();
      _stopPlayer = AudioPlayer();
      _mistakePlayer = AudioPlayer();

      if (!kIsWeb) {
        final tempDir = await getTemporaryDirectory();
        final startPath = '${tempDir.path}/camcorder_start_v3.wav';
        final stopPath = '${tempDir.path}/camcorder_stop_v3.wav';
        final mistakePath = '${tempDir.path}/mistake_alert_v3.wav';

        await io.File(startPath).writeAsBytes(_startChimeWav!, flush: true);
        await io.File(stopPath).writeAsBytes(_stopChimeWav!, flush: true);
        await io.File(mistakePath).writeAsBytes(_mistakeAlertWav!, flush: true);

        await _startPlayer!.setFilePath(startPath);
        await _stopPlayer!.setFilePath(stopPath);
        await _mistakePlayer!.setFilePath(mistakePath);
      } else {
        await _startPlayer!.setAudioSource(_InMemoryAudioSource(_startChimeWav!));
        await _stopPlayer!.setAudioSource(_InMemoryAudioSource(_stopChimeWav!));
        await _mistakePlayer!.setAudioSource(_InMemoryAudioSource(_mistakeAlertWav!));
      }

      await _startPlayer!.setVolume(1.0);
      await _stopPlayer!.setVolume(1.0);
      await _mistakePlayer!.setVolume(1.0);
    } catch (e) {
      debugPrint('[CamcorderSoundHelper] init error: $e');
    }
  }

  /// Plays the iconic camcorder recording "cling" sound with tactile feedback.
  Future<void> playRecordChime({required bool isStart}) async {
    try {
      // 1. Tactile haptic feedback
      if (isStart) {
        HapticFeedback.mediumImpact();
      } else {
        HapticFeedback.lightImpact();
      }

      // Also trigger system click sound as backup
      SystemSound.play(SystemSoundType.click);

      if (!_initialized) {
        await init();
      }

      final player = isStart ? _startPlayer : _stopPlayer;
      if (player != null) {
        await player.seek(Duration.zero);
        await player.play();
      }
    } catch (_) {
      SystemSound.play(SystemSoundType.click);
    }
  }

  /// Plays mistake alert (sound + vibration) when an error (red word) is detected.
  Future<void> playMistakeAlert() async {
    if (!AppState.instance.mistakeAlertEnabled) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    // Cooldown: at most once every 650ms to prevent rapid stuttering
    if (now - _lastMistakeAlertTime < 650) return;
    _lastMistakeAlertTime = now;

    try {
      // 1. Physical tactile vibration
      HapticFeedback.heavyImpact();
      HapticFeedback.vibrate();

      if (!_initialized) {
        await init();
      }

      if (_mistakePlayer != null) {
        await _mistakePlayer!.seek(Duration.zero);
        await _mistakePlayer!.play();
      }
    } catch (_) {
      HapticFeedback.vibrate();
    }
  }

  /// Synthesizes a crisp, glassy 2-tone "cling" beep (e.g. 1760Hz -> 2637Hz / A6 -> E7).
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
      final double env = math.exp(-i / (samplesPerTone * 0.45));
      final double sample = math.sin(2 * math.pi * tone1Freq * t) * env;
      pcmSamples[i] = (sample * 24000).clamp(-32768, 32767).toInt();
    }

    for (int i = 0; i < samplesPerTone; i++) {
      final double t = i / sampleRate;
      final double env = math.exp(-i / (samplesPerTone * 0.55));
      final double sample = math.sin(2 * math.pi * tone2Freq * t) * env;
      pcmSamples[samplesPerTone + i] =
          (sample * 28000).clamp(-32768, 32767).toInt();
    }

    return _createWavContainer(pcmSamples, sampleRate);
  }

  /// Synthesizes a gentle, distinct 2-pulse warning tone for recitation errors (392Hz -> 294Hz).
  static Uint8List _synthesizeMistakeAlert() {
    const int sampleRate = 44100;
    const double tone1Freq = 392.0; // G4 - gentle low warning
    const double tone2Freq = 293.66; // D4 - resolving low warning
    const double tone1Duration = 0.055; // 55ms
    const double tone2Duration = 0.075; // 75ms
    final int samplesTone1 = (sampleRate * tone1Duration).toInt();
    final int samplesTone2 = (sampleRate * tone2Duration).toInt();
    final int totalSamples = samplesTone1 + samplesTone2;

    final Int16List pcmSamples = Int16List(totalSamples);

    for (int i = 0; i < samplesTone1; i++) {
      final double t = i / sampleRate;
      final double env = math.exp(-i / (samplesTone1 * 0.65));
      final double sample = math.sin(2 * math.pi * tone1Freq * t) * env;
      pcmSamples[i] = (sample * 24000).clamp(-32768, 32767).toInt();
    }

    for (int i = 0; i < samplesTone2; i++) {
      final double t = i / sampleRate;
      final double env = math.exp(-i / (samplesTone2 * 0.75));
      final double sample = math.sin(2 * math.pi * tone2Freq * t) * env;
      pcmSamples[samplesTone1 + i] =
          (sample * 26000).clamp(-32768, 32767).toInt();
    }

    return _createWavContainer(pcmSamples, sampleRate);
  }

  static Uint8List _createWavContainer(Int16List pcmData, int sampleRate) {
    const int numChannels = 1;
    const int bitsPerSample = 16;
    final int byteRate = sampleRate * numChannels * (bitsPerSample ~/ 8);
    const int blockAlign = numChannels * (bitsPerSample ~/ 8);
    final int dataSize = pcmData.lengthInBytes;
    final int chunkSize = 36 + dataSize;

    final ByteData header = ByteData(44);

    // RIFF chunk descriptor
    header.setUint8(0, 0x52); // 'R'
    header.setUint8(1, 0x49); // 'I'
    header.setUint8(2, 0x46); // 'F'
    header.setUint8(3, 0x46); // 'F'
    header.setUint32(4, chunkSize, Endian.little);
    header.setUint8(8, 0x57); // 'W'
    header.setUint8(9, 0x41); // 'A'
    header.setUint8(10, 0x56); // 'V'
    header.setUint8(11, 0x45); // 'E'

    // fmt sub-chunk
    header.setUint8(12, 0x66); // 'f'
    header.setUint8(13, 0x6D); // 'm'
    header.setUint8(14, 0x74); // 't'
    header.setUint8(15, 0x20); // ' '
    header.setUint32(16, 16, Endian.little); // Subchunk1Size (16 for PCM)
    header.setUint16(20, 1, Endian.little); // AudioFormat (1 for PCM)
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

  _InMemoryAudioSource(this._buffer) : super(tag: 'sound_fx');

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
