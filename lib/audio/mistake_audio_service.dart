import 'dart:async';
import 'dart:io' as io;
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import '../core/highlighting_controller.dart';
import 'quran_audio_service.dart';

/// Metadata and audio reference for a captured recitation mistake snippet.
class MistakeAudioClip {
  final int key;
  final int surah;
  final int ayah;
  final int wordIndex;
  final String wordText;
  final DateTime timestamp;
  final int durationMs;
  final String? filePath;
  final Uint8List? wavBytes;

  const MistakeAudioClip({
    required this.key,
    required this.surah,
    required this.ayah,
    required this.wordIndex,
    required this.wordText,
    required this.timestamp,
    required this.durationMs,
    this.filePath,
    this.wavBytes,
  });
}

/// MistakeAudioService
///
/// Passively maintains a tiny pre-allocated circular PCM buffer (~192 KB in RAM)
/// fed from the existing 16kHz microphone stream without opening a second mic or
/// adding any processing overhead to the Sherpa-ONNX AI Isolate.
///
/// Only when [HighlightStore.onMistakeDetected] fires does it snapshot the last
/// ~4 seconds around the mispronounced word and save a lightweight `.wav` clip
/// so the user can compare their own voice directly against Al-Husary's audio.
class MistakeAudioService {
  MistakeAudioService._();
  static final MistakeAudioService instance = MistakeAudioService._();

  static const int sampleRate = 16000;
  static const int maxBufferSeconds = 6;
  static const int maxBufferSamples = sampleRate * maxBufferSeconds; // 96,000 (~192 KB)
  static const int captureWindowSamples = sampleRate * 4; // 4.0s clip (~128 KB)
  static const int maxSavedClips = 30;
  static const Duration _postTriggerDelay = Duration(milliseconds: 450);

  // Pre-allocated fixed-size circular ring buffer (zero per-chunk allocations)
  final Int16List _ring = Int16List(maxBufferSamples);
  int _writeHead = 0;
  int _filledSamples = 0;

  // Clip storage
  final Map<int, MistakeAudioClip> _clipsByKey = {};
  final List<MistakeAudioClip> _orderedClips = [];
  final Map<int, Timer> _pendingTimers = {};
  final Map<int, ({int surah, int ayah, int wordIndex, String wordText})>
      _pendingMeta = {};
  int _clipSeq = 0;

  // Reactive UI notifiers
  final ValueNotifier<int> revision = ValueNotifier<int>(0);
  final ValueNotifier<int> clipCountNotifier = ValueNotifier<int>(0);
  final ValueNotifier<bool> isPlayingNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<int?> playingClipKeyNotifier = ValueNotifier<int?>(null);
  final ValueNotifier<Duration> positionNotifier =
      ValueNotifier<Duration>(Duration.zero);
  final ValueNotifier<Duration> durationNotifier =
      ValueNotifier<Duration>(Duration.zero);

  // Dedicated playback instance
  AudioPlayer? _player;
  StreamSubscription<PlayerState>? _playerStateSub;
  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration?>? _durationSub;
  int _playSessionId = 0;

  bool get isPlaying => isPlayingNotifier.value;
  List<MistakeAudioClip> get clips => List.unmodifiable(_orderedClips);

  MistakeAudioClip? getClip(int surah, int ayah, int wordIndex) =>
      _clipsByKey[QuranCoordinate.packWordKey(surah, ayah, wordIndex)];

  bool hasClip(int surah, int ayah, int wordIndex) =>
      _clipsByKey.containsKey(QuranCoordinate.packWordKey(surah, ayah, wordIndex));

  /// Appends a 16kHz Float32 PCM chunk into the circular ring buffer.
  /// Runs in microseconds with zero heap allocations.
  void appendFloat32Chunk(Float32List chunk) {
    if (chunk.isEmpty) return;
    final int len = chunk.length;
    for (int i = 0; i < len; i++) {
      final double v = chunk[i] * 32767.0;
      int s = v.round();
      if (s > 32767) {
        s = 32767;
      } else if (s < -32768) {
        s = -32768;
      }
      _ring[_writeHead] = s;
      _writeHead++;
      if (_writeHead >= maxBufferSamples) {
        _writeHead = 0;
      }
    }
    _filledSamples = math.min(maxBufferSamples, _filledSamples + len);
  }

  /// Schedules a non-blocking snapshot ~450ms after a red-word verdict fires
  /// so the tail of the spoken word is included in the clip.
  void scheduleMistakeCapture({
    required int surah,
    required int ayah,
    required int wordIndex,
    required String wordText,
  }) {
    if (_filledSamples < sampleRate ~/ 4) {
      // Less than 250ms of audio recorded so far; skip empty captures.
      return;
    }

    final int key = QuranCoordinate.packWordKey(surah, ayah, wordIndex);
    _pendingTimers[key]?.cancel();
    _pendingMeta[key] = (
      surah: surah,
      ayah: ayah,
      wordIndex: wordIndex,
      wordText: wordText,
    );

    _pendingTimers[key] = Timer(_postTriggerDelay, () {
      _pendingTimers.remove(key);
      final meta = _pendingMeta.remove(key);
      if (meta == null) return;
      _commitCapture(
        surah: meta.surah,
        ayah: meta.ayah,
        wordIndex: meta.wordIndex,
        wordText: meta.wordText,
      );
    });
  }

  /// Flushes any pending mistake snapshots immediately and resets the ring buffer
  /// (called when recording stops or audio resets).
  void flushPendingAndResetRing() {
    if (_pendingTimers.isNotEmpty) {
      final keys = _pendingTimers.keys.toList();
      for (final key in keys) {
        _pendingTimers.remove(key)?.cancel();
        final meta = _pendingMeta.remove(key);
        if (meta != null) {
          _commitCapture(
            surah: meta.surah,
            ayah: meta.ayah,
            wordIndex: meta.wordIndex,
            wordText: meta.wordText,
          );
        }
      }
    }
    resetRingBuffer();
  }

  void resetRingBuffer() {
    for (final timer in _pendingTimers.values) {
      timer.cancel();
    }
    _pendingTimers.clear();
    _pendingMeta.clear();
    _writeHead = 0;
    _filledSamples = 0;
  }

  void _commitCapture({
    required int surah,
    required int ayah,
    required int wordIndex,
    required String wordText,
  }) {
    if (_filledSamples <= 0) return;

    final int count = math.min(_filledSamples, captureWindowSamples);
    final Int16List linearPcm = Int16List(count);

    // Copy oldest-to-newest out of the circular ring buffer
    int startIdx = _writeHead - count;
    if (startIdx < 0) startIdx += maxBufferSamples;

    final int firstPart = math.min(count, maxBufferSamples - startIdx);
    linearPcm.setRange(0, firstPart, _ring, startIdx);
    if (firstPart < count) {
      linearPcm.setRange(firstPart, count, _ring, 0);
    }

    final Uint8List wavBytes = _encodeWav16kMono(linearPcm);
    final int durationMs = (count * 1000) ~/ sampleRate;
    final int key = QuranCoordinate.packWordKey(surah, ayah, wordIndex);
    final int seq = ++_clipSeq;
    final DateTime now = DateTime.now();

    if (kIsWeb) {
      _upsertClip(
        MistakeAudioClip(
          key: key,
          surah: surah,
          ayah: ayah,
          wordIndex: wordIndex,
          wordText: wordText,
          timestamp: now,
          durationMs: durationMs,
          wavBytes: wavBytes,
        ),
      );
      return;
    }

    // Write WAV asynchronously off the ASR/UI hot path
    unawaited(_writeClipToDisk(
      key: key,
      surah: surah,
      ayah: ayah,
      wordIndex: wordIndex,
      wordText: wordText,
      timestamp: now,
      durationMs: durationMs,
      seq: seq,
      wavBytes: wavBytes,
    ));
  }

  Future<void> _writeClipToDisk({
    required int key,
    required int surah,
    required int ayah,
    required int wordIndex,
    required String wordText,
    required DateTime timestamp,
    required int durationMs,
    required int seq,
    required Uint8List wavBytes,
  }) async {
    try {
      final tempDir = await getTemporaryDirectory();
      final dir = io.Directory('${tempDir.path}/mistake_clips');
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      final filePath =
          '${dir.path}/m_${surah}_${ayah}_${wordIndex}_$seq.wav';
      await io.File(filePath).writeAsBytes(wavBytes, flush: false);

      _upsertClip(
        MistakeAudioClip(
          key: key,
          surah: surah,
          ayah: ayah,
          wordIndex: wordIndex,
          wordText: wordText,
          timestamp: timestamp,
          durationMs: durationMs,
          filePath: filePath,
        ),
      );
    } catch (e) {
      debugPrint('[MistakeAudioService] Failed to write clip: $e');
    }
  }

  void _upsertClip(MistakeAudioClip clip) {
    final existing = _clipsByKey[clip.key];
    if (existing != null) {
      _orderedClips.removeWhere((c) => c.key == clip.key);
      _deleteFileIfAny(existing.filePath);
    }

    _clipsByKey[clip.key] = clip;
    _orderedClips.add(clip);

    // Keep storage bounded
    while (_orderedClips.length > maxSavedClips) {
      final evicted = _orderedClips.removeAt(0);
      _clipsByKey.remove(evicted.key);
      if (playingClipKeyNotifier.value == evicted.key) {
        unawaited(stopPlayback());
      }
      _deleteFileIfAny(evicted.filePath);
    }

    clipCountNotifier.value = _orderedClips.length;
    revision.value++;
  }

  /// Clears saved mistake clips from [surah, startAyah] onwards (matching highlight clearing).
  void clearFrom(int surah, int startAyah) {
    bool removedAny = false;
    _orderedClips.removeWhere((clip) {
      final bool shouldRemove =
          clip.surah > surah || (clip.surah == surah && clip.ayah >= startAyah);
      if (shouldRemove) {
        removedAny = true;
        _clipsByKey.remove(clip.key);
        if (playingClipKeyNotifier.value == clip.key) {
          unawaited(stopPlayback());
        }
        _deleteFileIfAny(clip.filePath);
      }
      return shouldRemove;
    });
    if (removedAny) {
      clipCountNotifier.value = _orderedClips.length;
      revision.value++;
    }
  }

  /// Clears all recorded mistake clips and temporary files.
  void clearAll() {
    unawaited(stopPlayback());
    for (final clip in _orderedClips) {
      _deleteFileIfAny(clip.filePath);
    }
    _orderedClips.clear();
    _clipsByKey.clear();
    clipCountNotifier.value = 0;
    revision.value++;
  }

  void _deleteFileIfAny(String? path) {
    if (path == null || kIsWeb) return;
    unawaited(io.File(path).delete().catchError((_) => io.File(path)));
  }

  Future<AudioPlayer> _ensurePlayer() async {
    if (_player != null) return _player!;
    final p = AudioPlayer();
    _player = p;

    _playerStateSub = p.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        _resetPlaybackState();
      } else {
        isPlayingNotifier.value = state.playing;
      }
    });

    _positionSub = p.positionStream.listen((pos) {
      positionNotifier.value = pos;
    });

    _durationSub = p.durationStream.listen((dur) {
      if (dur != null) {
        durationNotifier.value = dur;
      }
    });

    return p;
  }

  void _resetPlaybackState() {
    isPlayingNotifier.value = false;
    playingClipKeyNotifier.value = null;
    positionNotifier.value = Duration.zero;
  }

  /// Plays (or toggles stop if already playing) the user's recorded mistake clip.
  Future<void> playClip(MistakeAudioClip clip) async {
    if (isPlayingNotifier.value && playingClipKeyNotifier.value == clip.key) {
      await stopPlayback();
      return;
    }

    final int session = ++_playSessionId;

    // Ensure Qari audio stops so both streams never collide
    if (QuranAudioService.instance.isPlaying ||
        QuranAudioService.instance.isBuffering) {
      await QuranAudioService.instance.stop();
    }

    try {
      final player = await _ensurePlayer();
      if (session != _playSessionId) return;

      await player.stop();
      if (session != _playSessionId) return;

      playingClipKeyNotifier.value = clip.key;
      positionNotifier.value = Duration.zero;
      durationNotifier.value = Duration(milliseconds: clip.durationMs);

      if (kIsWeb) {
        if (clip.wavBytes == null) {
          _resetPlaybackState();
          return;
        }
        await player.setAudioSource(_InMemoryWavAudioSource(clip.wavBytes!));
      } else {
        if (clip.filePath == null || !await io.File(clip.filePath!).exists()) {
          _resetPlaybackState();
          return;
        }
        await player.setFilePath(clip.filePath!);
      }

      if (session != _playSessionId) return;
      isPlayingNotifier.value = true;
      await player.setVolume(1.0);
      await player.play();
    } catch (e) {
      debugPrint('[MistakeAudioService] Playback error: $e');
      _resetPlaybackState();
    }
  }

  Future<void> stopPlayback() async {
    _playSessionId++;
    try {
      await _player?.stop();
    } catch (_) {}
    _resetPlaybackState();
  }

  Future<void> dispose() async {
    await stopPlayback();
    await _playerStateSub?.cancel();
    await _positionSub?.cancel();
    await _durationSub?.cancel();
    await _player?.dispose();
    _player = null;
    clearAll();
  }

  /// Builds a standard 44-byte RIFF/WAVE PCM16 mono 16kHz container.
  static Uint8List _encodeWav16kMono(Int16List pcmData) {
    const int numChannels = 1;
    const int bitsPerSample = 16;
    const int byteRate = sampleRate * numChannels * (bitsPerSample ~/ 8);
    const int blockAlign = numChannels * (bitsPerSample ~/ 8);
    final int dataSize = pcmData.lengthInBytes;
    final int chunkSize = 36 + dataSize;

    final ByteData header = ByteData(44);
    header.setUint8(0, 0x52); // R
    header.setUint8(1, 0x49); // I
    header.setUint8(2, 0x46); // F
    header.setUint8(3, 0x46); // F
    header.setUint32(4, chunkSize, Endian.little);
    header.setUint8(8, 0x57); // W
    header.setUint8(9, 0x41); // A
    header.setUint8(10, 0x56); // V
    header.setUint8(11, 0x45); // E
    header.setUint8(12, 0x66); // f
    header.setUint8(13, 0x6D); // m
    header.setUint8(14, 0x74); // t
    header.setUint8(15, 0x20); // ' '
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little); // PCM
    header.setUint16(22, numChannels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, blockAlign, Endian.little);
    header.setUint16(34, bitsPerSample, Endian.little);
    header.setUint8(36, 0x64); // d
    header.setUint8(37, 0x61); // a
    header.setUint8(38, 0x74); // t
    header.setUint8(39, 0x61); // a
    header.setUint32(40, dataSize, Endian.little);

    final Uint8List wavBytes = Uint8List(44 + dataSize);
    wavBytes.setRange(0, 44, header.buffer.asUint8List());
    wavBytes.setRange(44, 44 + dataSize, pcmData.buffer.asUint8List());
    return wavBytes;
  }
}

// ignore: experimental_member_use
class _InMemoryWavAudioSource extends StreamAudioSource {
  final Uint8List _buffer;
  _InMemoryWavAudioSource(this._buffer) : super(tag: 'mistake_clip');

  @override
  // ignore: experimental_member_use
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    start ??= 0;
    end ??= _buffer.length;
    // ignore: experimental_member_use
    return StreamAudioResponse(
      sourceLength: _buffer.length,
      contentLength: end - start,
      offset: start,
      stream: Stream.value(_buffer.sublist(start, end)),
      contentType: 'audio/wav',
    );
  }
}
