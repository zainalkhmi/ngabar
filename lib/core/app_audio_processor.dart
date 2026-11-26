import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:record/record.dart';
import 'package:recite_quran/recite_quran.dart' as rq;
import '../maglis/maglis_controller.dart';
import '../maglis/maglis_core.dart';

/// AppAudioProcessor
///
/// Delivers 16kHz Float32 PCM chunks to the Sherpa ASR engine.
/// - On Native IO (`!kIsWeb`): Streams directly in 160ms chunks (2,560 samples,
///   an exact 2x multiple of Zipformer's 80ms frame stride — 3x lower latency
///   than the package's 480ms Dart buffer) with gentle adaptive gain conditioning
///   for quiet/distant voices while keeping loud speech unclipped and room silence untouched.
/// - In Maglis Mode: Harmonizes with active WebRTC room using [AndroidAudioSource.mic]
///   and [AudioManagerMode.modeInCommunication] without hardware AEC ([echoCancel: false]).
/// - On Web (`kIsWeb`): Delegates to [rq.AudioProcessor] (already non-buffered) with
///   soft gain conditioning on emitted chunks.
class AppAudioProcessor {
  static const int recordSampleRate = 16000;
  static const int numChannels = 1;
  static const int bytesPerSample = 2; // 16-bit PCM

  /// 160ms = 2,560 samples = 5,120 bytes at 16kHz mono 16-bit PCM.
  /// Matches 2x Sherpa Zipformer 80ms frame blocks for responsive real-time decoding.
  static const int chunkMs = 160;
  static const int recordChunkBytes =
      (recordSampleRate * numChannels * bytesPerSample * chunkMs) ~/ 1000;

  // Soft adaptive gain boundaries (never boosts room floor < 0.006 or loud speech >= 0.16)
  static const double _noiseFloorPeak = 0.006;
  static const double _comfortableSpeechPeak = 0.16;
  static const double _targetQuietPeak = 0.20;
  static const double _maxAdaptiveGain = 3.2;

  final rq.AudioProcessor _soloAudio = rq.AudioProcessor();

  // Native streaming recorder state (used for both Solo and Maglis on !kIsWeb)
  AudioRecorder? _recorder;
  StreamSubscription<Uint8List>? _subscription;
  Uint8List _frameBuffer = Uint8List(0);
  bool _isRecording = false;
  double _adaptiveGain = 1.0;
  Future<void>? _activeOp;

  Future<bool> hasPermission() async {
    return _soloAudio.hasPermission();
  }

  Future<void> start({
    required void Function(Float32List chunk, bool isFinal) onChunk,
  }) async {
    while (_activeOp != null) {
      await _activeOp;
    }
    final completer = Completer<void>();
    _activeOp = completer.future;

    try {
      await _stopInternal();
      _adaptiveGain = 1.0;

      final bool inMaglis = MaglisController.instance.inSession;

      if (kIsWeb) {
        // Web AudioProcessor streams browser frames immediately without 480ms buffering
        await _soloAudio.start(
          onChunk: (chunk, isFinal) {
            onChunk(_applyAdaptiveSoftGain(chunk), isFinal);
          },
        );
        return;
      }

      final RecordConfig config = inMaglis
          ? const RecordConfig(
              encoder: AudioEncoder.pcm16bits,
              sampleRate: recordSampleRate,
              numChannels: numChannels,
              autoGain: false,
              echoCancel: false,
              noiseSuppress: false,
              audioInterruption: AudioInterruptionMode.none,
              androidConfig: AndroidRecordConfig(
                audioSource: AndroidAudioSource.mic,
                audioManagerMode: AudioManagerMode.modeInCommunication,
                manageBluetooth: false,
              ),
              iosConfig: IosRecordConfig(
                categoryOptions: [
                  IosAudioCategoryOption.defaultToSpeaker,
                  IosAudioCategoryOption.allowBluetooth,
                  IosAudioCategoryOption.allowBluetoothA2DP,
                  IosAudioCategoryOption.allowAirPlay,
                ],
              ),
            )
          : const RecordConfig(
              encoder: AudioEncoder.pcm16bits,
              sampleRate: recordSampleRate,
              numChannels: numChannels,
              autoGain: false,
              echoCancel: false,
              noiseSuppress: false,
            );

      _recorder = AudioRecorder();
      final recordStream = await _recorder!.startStream(config);
      _isRecording = true;

      _subscription = recordStream.listen(
        (Uint8List rawData) {
          if (!_isRecording || rawData.isEmpty) return;

          if (rawData.offsetInBytes % 2 != 0) {
            rawData = Uint8List.fromList(rawData);
          }

          Uint8List allBytes;
          if (_frameBuffer.isEmpty) {
            allBytes = rawData;
          } else {
            allBytes = Uint8List(_frameBuffer.length + rawData.length);
            allBytes.setAll(0, _frameBuffer);
            allBytes.setAll(_frameBuffer.length, rawData);
          }

          int offset = 0;
          while (allBytes.length - offset >= recordChunkBytes) {
            final byteView = Uint8List.view(
              allBytes.buffer,
              allBytes.offsetInBytes + offset,
              recordChunkBytes,
            );
            offset += recordChunkBytes;

            final int16samples = Int16List.view(
              byteView.buffer,
              byteView.offsetInBytes,
              recordChunkBytes ~/ bytesPerSample,
            );

            final float32Samples = Float32List(int16samples.length);
            for (int i = 0; i < int16samples.length; i++) {
              float32Samples[i] = int16samples[i] / 32768.0;
            }

            onChunk(_applyAdaptiveSoftGain(float32Samples), false);
          }

          if (offset < allBytes.length) {
            _frameBuffer = Uint8List.fromList(
              Uint8List.view(allBytes.buffer, allBytes.offsetInBytes + offset),
            );
          } else {
            _frameBuffer = Uint8List(0);
          }
        },
        onError: (err) {
          _isRecording = false;
        },
        onDone: () {
          _isRecording = false;
        },
        cancelOnError: true,
      );
    } finally {
      completer.complete();
      _activeOp = null;
    }
  }

  /// Gently boosts quiet/distant voice (0.006 <= peak < 0.16) up to 3.2x so
  /// breathy letters (هـ, ح, ف, ث, ذ) and soft endings survive Zipformer CTC
  /// without clipping loud audio or amplifying ambient room hiss.
  Float32List _applyAdaptiveSoftGain(Float32List samples) {
    if (samples.isEmpty) return samples;
    double peak = 0.0;
    for (int i = 0; i < samples.length; i++) {
      final double v = samples[i].abs();
      if (v > peak) peak = v;
    }

    final double targetGain;
    if (peak < _noiseFloorPeak) {
      // Room silence: relax gain slowly toward 1.0, never boost hiss
      targetGain = 1.0;
    } else if (peak >= _comfortableSpeechPeak) {
      // Normal/loud voice: keep raw unadulterated signal
      targetGain = 1.0;
    } else {
      targetGain = (_targetQuietPeak / peak).clamp(1.0, _maxAdaptiveGain);
    }

    // Fast attack down when voice gets louder, smooth release up when quiet
    final double alpha = targetGain < _adaptiveGain ? 0.55 : 0.30;
    _adaptiveGain = _adaptiveGain * (1.0 - alpha) + targetGain * alpha;

    final double maxSafeGain = peak > 0.001 ? (0.92 / peak) : 1.0;
    final double effectiveGain = math.min(_adaptiveGain, maxSafeGain);

    if ((effectiveGain - 1.0).abs() < 0.04) {
      return samples;
    }

    for (int i = 0; i < samples.length; i++) {
      samples[i] = (samples[i] * effectiveGain).clamp(-0.95, 0.95);
    }
    return samples;
  }

  void clearBuffer() {
    _soloAudio.clearBuffer();
    _frameBuffer = Uint8List(0);
    _adaptiveGain = 1.0;
  }

  Future<void> stop() async {
    while (_activeOp != null) {
      await _activeOp;
    }
    final completer = Completer<void>();
    _activeOp = completer.future;

    try {
      await _stopInternal();
    } finally {
      completer.complete();
      _activeOp = null;
    }
  }

  Future<void> _stopInternal() async {
    // 1. Stop Web solo audio processor if active
    try {
      await _soloAudio.stop();
    } catch (_) {}

    // 2. Stop native stream recorder if active
    await _subscription?.cancel();
    _subscription = null;

    if (_isRecording) {
      _isRecording = false;
      try {
        await _recorder?.stop();
      } catch (_) {}
    } else {
      try {
        if (_recorder != null && await _recorder!.isRecording()) {
          await _recorder!.stop();
        }
      } catch (_) {}
    }

    try {
      await _recorder?.dispose();
    } catch (_) {}
    _recorder = null;
    _frameBuffer = Uint8List(0);
    _adaptiveGain = 1.0;

    // If still in active Maglis session (and not tearing down), preserve WebRTC call speakerphone
    if (MaglisController.instance.inSession &&
        !MaglisController.instance.isLeaving) {
      MaglisPlatform.setSpeaker(true);
      unawaited(MaglisPlatform.startBackgroundCallService());
    }
  }

  Future<void> dispose() async {
    await stop();
  }
}
