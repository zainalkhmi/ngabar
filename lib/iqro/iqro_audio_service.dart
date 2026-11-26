import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';

/// Offline tap-to-speak audio service for Iqro' cells.
/// Plays bundled Hijaiyah syllable MP3 assets from assets/iqro/audio/
/// with zero network downloads and zero impact on Sherpa ASR.
class IqroAudioService {
  IqroAudioService._();
  static final IqroAudioService instance = IqroAudioService._();

  AudioPlayer? _player;
  int _playGeneration = 0;

  static const Set<int> _supportedLetters = {
    0x0627, 0x0628, 0x062A, 0x062B, 0x062C, 0x062D, 0x062E, 0x062F,
    0x0630, 0x0631, 0x0632, 0x0633, 0x0634, 0x0635, 0x0636, 0x0637,
    0x0638, 0x0639, 0x063A, 0x0641, 0x0642, 0x0643, 0x0644, 0x0645,
    0x0646, 0x0647, 0x0648, 0x064A,
  };

  AudioPlayer _ensurePlayer() {
    return _player ??= AudioPlayer();
  }

  /// Stops any currently playing Iqro cell audio.
  Future<void> stop() async {
    _playGeneration++;
    try {
      await _player?.stop();
    } catch (_) {}
  }

  /// Speaks the Arabic cell text using bundled offline Hijaiyah assets.
  Future<void> speakArabic(String arabicText) async {
    final int gen = ++_playGeneration;
    HapticFeedback.selectionClick();
    SystemSound.play(SystemSoundType.click);

    final assets = _resolveAssetSequence(arabicText);
    if (assets.isEmpty) return;

    final player = _ensurePlayer();
    try {
      await player.stop();
      for (int i = 0; i < assets.length; i++) {
        if (gen != _playGeneration) return;
        await player.setAsset(assets[i]);
        if (gen != _playGeneration) return;
        await player.play();
        // Wait briefly for short syllable completion before next letter
        if (i + 1 < assets.length) {
          await Future<void>.delayed(const Duration(milliseconds: 90));
        }
      }
    } catch (e) {
      debugPrint('[IqroAudioService] playback error: $e');
    }
  }

  List<String> _resolveAssetSequence(String text) {
    final runes = text.runes.toList();
    final List<String> assets = [];
    int i = 0;

    while (i < runes.length && assets.length < 6) {
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
        if (d == 0x064E || d == 0x064B) {
          vowel = 'a';
          hasExplicitVowel = true;
        } else if (d == 0x0650 || d == 0x064D) {
          vowel = 'i';
          hasExplicitVowel = true;
        } else if (d == 0x064F || d == 0x064C) {
          vowel = 'u';
          hasExplicitVowel = true;
        } else if (d == 0x0652) {
          isSukun = true;
        }
        j++;
      }

      // Skip bare elongation alif/waw/ya when preceded by a vowel without its own harakat
      if (!hasExplicitVowel &&
          !isSukun &&
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
