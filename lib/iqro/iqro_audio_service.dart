import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'iqro_repository.dart';
import 'iqro_tajweed_service.dart';
import 'iqro_tts_stub.dart'
    if (dart.library.js_interop) 'iqro_tts_web.dart';

/// Tap-to-speak audio service for Iqro' cells.
///
/// Matches the reference dyazincahya/iqro-json behavior by speaking the
/// Indonesian Latin transliteration (`id-ID` TTS at `0.8` rate, so connected
/// words, `=` comparisons, Mad elongations, Sukun, and Tasydid sound natural),
/// and automatically falls back to bundled offline Hijaiyah MP3 assets when
/// `id-ID` TTS is unavailable on the device.
class IqroAudioService {
  IqroAudioService._() {
    _ttsChannel.setMethodCallHandler(_handleTtsMethodCall);
  }

  static final IqroAudioService instance = IqroAudioService._();

  static const MethodChannel _ttsChannel =
      MethodChannel('com.ngabar.app/iqro_tts');
  static const double _ttsSpeechRate = 0.8;

  AudioPlayer? _player;
  int _playGeneration = 0;
  Completer<void>? _activeTtsCompleter;
  String? _activeUtteranceId;

  /// Notifies listeners (e.g., Android mic lifecycle & play button) while
  /// Iqro cell audio is actively playing.
  final ValueNotifier<bool> isPlayingNotifier = ValueNotifier<bool>(false);
  bool get isPlaying => isPlayingNotifier.value;

  /// Playback tempo multiplier: 1.0 (normal) or 0.75 (slow for beginners).
  final ValueNotifier<double> tempoNotifier = ValueNotifier<double>(1.0);
  double get tempo => tempoNotifier.value;

  /// Auto-play "Dengar & Ikuti" state for sequential page playback.
  final ValueNotifier<bool> isAutoPlayingNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<int?> autoPlayOrderIdNotifier = ValueNotifier<int?>(null);
  int _autoPlaySeq = 0;

  void toggleTempo() {
    tempoNotifier.value = tempoNotifier.value == 1.0 ? 0.75 : 1.0;
  }

  Future<void> stopAutoPlay() async {
    _autoPlaySeq++;
    isAutoPlayingNotifier.value = false;
    autoPlayOrderIdNotifier.value = null;
    await stop();
  }

  Future<void> startAutoPlayPage(
    List<IqroCellData> cells, {
    int startIndex = 0,
    void Function(int flatIndex)? onCellActive,
  }) async {
    if (cells.isEmpty) return;
    final int seq = ++_autoPlaySeq;
    isAutoPlayingNotifier.value = true;

    final int begin = startIndex.clamp(0, cells.length - 1);
    for (int i = begin; i < cells.length; i++) {
      if (seq != _autoPlaySeq) break;
      final cell = cells[i];
      autoPlayOrderIdNotifier.value = cell.orderId;
      onCellActive?.call(i);
      await speakArabic(
        cell.arabic,
        latinText: cell.latin,
        inQuran: cell.inQuran,
      );
      if (seq != _autoPlaySeq) break;
      if (i + 1 < cells.length) {
        await Future<void>.delayed(
          Duration(milliseconds: tempoNotifier.value < 1.0 ? 480 : 300),
        );
      }
    }

    if (seq == _autoPlaySeq) {
      isAutoPlayingNotifier.value = false;
      autoPlayOrderIdNotifier.value = null;
    }
  }

  static const Set<int> _supportedLetters = {
    0x0627, 0x0628, 0x062A, 0x062B, 0x062C, 0x062D, 0x062E, 0x062F,
    0x0630, 0x0631, 0x0632, 0x0633, 0x0634, 0x0635, 0x0636, 0x0637,
    0x0638, 0x0639, 0x063A, 0x0641, 0x0642, 0x0643, 0x0644, 0x0645,
    0x0646, 0x0647, 0x0648, 0x064A,
  };

  Future<void> _handleTtsMethodCall(MethodCall call) async {
    if (call.method == 'onTtsFinished') {
      final args = call.arguments as Map<dynamic, dynamic>?;
      final finishedId = args?['utteranceId'] as String?;
      if (finishedId == null ||
          finishedId.isEmpty ||
          finishedId == _activeUtteranceId) {
        _completeActiveTts();
      }
    }
  }

  void _completeActiveTts() {
    _activeUtteranceId = null;
    final c = _activeTtsCompleter;
    _activeTtsCompleter = null;
    if (c != null && !c.isCompleted) {
      c.complete();
    }
  }

  AudioPlayer _ensurePlayer() {
    return _player ??= AudioPlayer();
  }

  /// Stops any currently playing Iqro cell audio.
  Future<void> stop() async {
    _playGeneration++;
    _completeActiveTts();
    isPlayingNotifier.value = false;
    if (kIsWeb) {
      stopWebLatinTts();
    } else if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        await _ttsChannel.invokeMethod('stop');
      } catch (_) {}
    }
    try {
      await _player?.stop();
    } catch (_) {}
  }

  /// Speaks an Iqro' cell.
  /// If [inQuran] is true, attempts to play authentic Qari audio from
  /// QuranCDN / Tarteel QUL wbw files first. Otherwise or on failure, falls back to
  /// `id-ID` TTS on [latinText] (matching the dyazincahya/iqro-json reference)
  /// and bundled offline Hijaiyah syllable MP3s.
  Future<void> speakArabic(
    String arabicText, {
    String? latinText,
    bool inQuran = false,
  }) async {
    final int gen = ++_playGeneration;
    _completeActiveTts();
    HapticFeedback.selectionClick();

    // Stop any previous playback cleanly before starting new utterance.
    if (kIsWeb) {
      stopWebLatinTts();
    } else if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        await _ttsChannel.invokeMethod('stop');
      } catch (_) {}
    }
    try {
      await _player?.stop();
    } catch (_) {}

    if (gen != _playGeneration) return;

    // 1. If marked as inQuran, try authentic Qari audio from QuranCDN / QUL
    if (inQuran) {
      final quranAudio =
          await IqroTajweedService.instance.resolveQuranWordAudio(arabicText);
      if (gen != _playGeneration) return;

      if (quranAudio != null && quranAudio.isNotEmpty) {
        isPlayingNotifier.value = true;
        final player = _ensurePlayer();
        try {
          if (quranAudio.startsWith('http')) {
            await player.setUrl(quranAudio);
          } else {
            await player.setFilePath(quranAudio);
          }
          await player.setSpeed(tempoNotifier.value);
          if (gen != _playGeneration) return;
          await player.play();
          return;
        } catch (e) {
          debugPrint('[IqroAudioService] Qari audio error, falling back: $e');
        } finally {
          if (gen == _playGeneration) {
            isPlayingNotifier.value = false;
          }
        }
      }
    }

    if (gen != _playGeneration) return;

    final cleanLatin = _normalizeLatinForTts(latinText ?? '');
    if (cleanLatin.isNotEmpty) {
      final spokeTts = await _trySpeakTts(cleanLatin, gen);
      if (spokeTts) return;
      if (gen != _playGeneration) return;
    }

    // Fallback: bundled offline Hijaiyah syllable MP3s
    final assets = _resolveAssetSequence(arabicText);
    if (assets.isEmpty) {
      if (gen == _playGeneration) {
        isPlayingNotifier.value = false;
      }
      return;
    }

    isPlayingNotifier.value = true;
    final player = _ensurePlayer();
    try {
      await player.setAudioSources([
        for (final asset in assets) AudioSource.asset(asset),
      ]);
      await player.setSpeed(tempoNotifier.value);
      if (gen != _playGeneration) return;
      await player.play();
    } catch (e) {
      debugPrint('[IqroAudioService] playback error: $e');
    } finally {
      if (gen == _playGeneration) {
        isPlayingNotifier.value = false;
      }
    }
  }

  Future<bool> _trySpeakTts(String cleanLatin, int gen) async {
    if (kIsWeb) {
      final completer = Completer<void>();
      _activeTtsCompleter = completer;
      isPlayingNotifier.value = true;

      final ok = await speakWebLatinTts(
        text: cleanLatin,
        rate: _ttsSpeechRate * tempoNotifier.value,
        onComplete: () {
          if (gen == _playGeneration) {
            _completeActiveTts();
          }
        },
      );
      if (!ok) {
        _completeActiveTts();
        if (gen == _playGeneration) {
          isPlayingNotifier.value = false;
        }
        return false;
      }

      try {
        await completer.future.timeout(const Duration(seconds: 8));
      } catch (_) {
        _completeActiveTts();
      } finally {
        if (gen == _playGeneration) {
          isPlayingNotifier.value = false;
        }
      }
      return true;
    }

    if (defaultTargetPlatform == TargetPlatform.android) {
      final utteranceId = 'iqro_$gen';
      final completer = Completer<void>();
      _activeUtteranceId = utteranceId;
      _activeTtsCompleter = completer;
      isPlayingNotifier.value = true;

      try {
        final bool started = await _ttsChannel.invokeMethod<bool>('speak', {
              'text': cleanLatin,
              'utteranceId': utteranceId,
              'rate': _ttsSpeechRate,
            }) ??
            false;

        if (!started || gen != _playGeneration) {
          if (_activeUtteranceId == utteranceId) {
            _completeActiveTts();
          }
          if (gen == _playGeneration) {
            isPlayingNotifier.value = false;
          }
          return false;
        }

        // Wait for UtteranceProgressListener.onDone (bounded so mic never stays paused forever)
        final maxWaitMs = (cleanLatin.length * 180).clamp(2500, 12000);
        try {
          await completer.future.timeout(Duration(milliseconds: maxWaitMs));
        } catch (_) {
          if (_activeUtteranceId == utteranceId) {
            _completeActiveTts();
          }
        } finally {
          if (gen == _playGeneration) {
            isPlayingNotifier.value = false;
          }
        }
        return true;
      } catch (e) {
        debugPrint('[IqroAudioService] Android TTS error: $e');
        if (_activeUtteranceId == utteranceId) {
          _completeActiveTts();
        }
        if (gen == _playGeneration) {
          isPlayingNotifier.value = false;
        }
        return false;
      }
    }

    return false;
  }

  /// Normalizes Iqro `latin` text to match dyazincahya/iqro-json's `speakLatin`:
  /// - Repairs wrapped lines (`SIRAAJA\nN` -> `SIRAAJAN`)
  /// - Converts `=` into a brief pause `, ` and `-` into spaces
  /// - Strips decorative circle markers (`○`, `•`, `۝`)
  /// - Lowercases so Android TTS pronounces syllables naturally instead of spelling uppercase letters
  static String _normalizeLatinForTts(String raw) {
    if (raw.trim().isEmpty) return '';
    var s = raw
        .replaceAll(RegExp(r'(\S)\r?\n(\S)'), r'$1$2')
        .replaceAll(RegExp(r'\r?\n'), ' ')
        .replaceAll(RegExp(r'[○●◯۝]'), ' ')
        .replaceAll('=', ', ')
        .replaceAll('-', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim()
        .toLowerCase();
    // Clean up stray space before comma from " = " -> " , "
    s = s.replaceAll(' ,', ',');
    return s;
  }

  List<String> _resolveAssetSequence(String text) {
    final runes = text.runes.toList();
    final List<String> assets = [];
    int i = 0;

    while (i < runes.length && assets.length < 24) {
      int code = _mapLetterCode(runes[i]);
      if (!_supportedLetters.contains(code)) {
        i++;
        continue;
      }

      String vowel = 'a';
      int j = i + 1;
      bool hasExplicitVowel = false;
      bool isSukun = false;
      while (j < runes.length && _isDiacritic(runes[j])) {
        final d = runes[j];
        if (d == 0x064E) {
          vowel = 'a';
          hasExplicitVowel = true;
        } else if (d == 0x064B) {
          vowel = 'an';
          hasExplicitVowel = true;
        } else if (d == 0x0650) {
          vowel = 'i';
          hasExplicitVowel = true;
        } else if (d == 0x064D) {
          vowel = 'in';
          hasExplicitVowel = true;
        } else if (d == 0x064F) {
          vowel = 'u';
          hasExplicitVowel = true;
        } else if (d == 0x064C) {
          vowel = 'un';
          hasExplicitVowel = true;
        } else if (d == 0x0652) {
          isSukun = true;
        }
        j++;
      }

      // Sukun letters have no vowel; skip emitting a false '-a' syllable
      if (isSukun && !hasExplicitVowel) {
        i = j;
        continue;
      }

      // Skip bare elongation alif/waw/ya when preceded by a vowel without its own harakat
      if (!hasExplicitVowel &&
          assets.isNotEmpty &&
          (code == 0x0627 || code == 0x0648 || code == 0x064A)) {
        i = j;
        continue;
      }

      final hex = code.toRadixString(16).padLeft(4, '0');
      assets.add('assets/iqro/audio/${hex}_$vowel.mp3');
      i = j;
    }

    return assets;
  }

  static int _mapLetterCode(int rune) {
    switch (rune) {
      case 0x0621: // ء
      case 0x0622: // آ
      case 0x0623: // أ
      case 0x0625: // إ
      case 0x0671: // ٱ
        return 0x0627;
      case 0x0629: // ة
        return 0x062A;
      case 0x0649: // ى
      case 0x0626: // ئ
        return 0x064A;
      case 0x0624: // ؤ
        return 0x0648;
      default:
        return rune;
    }
  }

  static bool _isDiacritic(int rune) {
    return (rune >= 0x064B && rune <= 0x065F) ||
        rune == 0x0670 ||
        rune == 0x0640;
  }
}
