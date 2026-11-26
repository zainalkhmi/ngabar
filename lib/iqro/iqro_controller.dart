import 'dart:async';
import 'package:flutter/foundation.dart';
import '../audio/camcorder_sound_helper.dart';
import '../audio/mistake_audio_service.dart';
import '../core/app_state.dart';
import 'iqro_repository.dart';

/// Highlight status for an Iqro cell.
/// 0 = unread, 1 = correct (green), 3 = mistake (red).
abstract final class IqroCellStatus {
  static const int unread = 0;
  static const int correct = 1;
  static const int mistake = 3;
}

/// Standalone voice-matching controller for Iqro mode.
/// Completely decoupled from Quran HighlightingController so it adds
/// zero overhead to Mushaf recitation tracking.
class IqroController extends ChangeNotifier {
  IqroController._();
  static final IqroController instance = IqroController._();

  IqroPageData? _currentPageData;
  IqroPageData? get currentPageData => _currentPageData;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  int _activeIndex = 0;
  int get activeIndex => _activeIndex;

  // orderId -> IqroCellStatus (1 = green, 3 = red)
  final Map<int, int> _statuses = {};
  String _lastHeardText = '';
  String get lastHeardText => _lastHeardText;

  // Tracks ASR text already consumed for previous cells in the same utterance
  String _consumedNormalizedBuffer = '';
  int _consumedCompactLen = 0;
  int _lastMistakeOrderId = -1;
  Timer? _mistakeDebounceTimer;

  int statusFor(int orderId) => _statuses[orderId] ?? IqroCellStatus.unread;

  int get correctCount =>
      _statuses.values.where((v) => v == IqroCellStatus.correct).length;

  int get mistakeCount =>
      _statuses.values.where((v) => v == IqroCellStatus.mistake).length;

  /// True when the active cell's words exist in the Al-Qur'an vocabulary,
  /// selecting strict Quran-ASR matching; false selects phonetic practice matching.
  bool get isCurrentCellInQuran {
    final data = _currentPageData;
    if (data == null ||
        _activeIndex < 0 ||
        _activeIndex >= data.content.length) {
      return false;
    }
    return data.content[_activeIndex].inQuran;
  }

  bool get isPageCompleted =>
      _currentPageData != null &&
      _currentPageData!.content.isNotEmpty &&
      _activeIndex >= _currentPageData!.content.length;

  Future<void> loadPage(int jilid, int page) async {
    _isLoading = true;
    notifyListeners();
    final data = await IqroRepository.instance.getPage(jilid, page);
    _currentPageData = data;
    _activeIndex = 0;
    _statuses.clear();
    _lastHeardText = '';
    _consumedNormalizedBuffer = '';
    _consumedCompactLen = 0;
    _lastMistakeOrderId = -1;
    _isLoading = false;
    notifyListeners();
  }

  void selectCell(int index) {
    final data = _currentPageData;
    if (data == null || index < 0 || index >= data.content.length) return;
    _activeIndex = index;
    final cell = data.content[index];
    _statuses.remove(cell.orderId);
    _lastMistakeOrderId = -1;
    notifyListeners();
  }

  void resetPageProgress() {
    _statuses.clear();
    _activeIndex = 0;
    _lastHeardText = '';
    _consumedNormalizedBuffer = '';
    _consumedCompactLen = 0;
    _lastMistakeOrderId = -1;
    notifyListeners();
  }

  void resetSessionBuffer() {
    _lastHeardText = '';
    _consumedNormalizedBuffer = '';
    _consumedCompactLen = 0;
    _mistakeDebounceTimer?.cancel();
  }

  /// Processes real-time Arabic transcription from SherpaEngine while in Iqro mode.
  void onTranscription(String rawText, {required bool isFinal}) {
    final data = _currentPageData;
    if (data == null || data.content.isEmpty) return;
    if (_activeIndex >= data.content.length) {
      if (isFinal) {
        _consumedNormalizedBuffer = '';
        _consumedCompactLen = 0;
      }
      return;
    }

    final trimmed = rawText.trim();
    if (trimmed.isNotEmpty) {
      _lastHeardText = trimmed;
    }

    final normSpokenFull = _normalizeArabic(trimmed);
    if (normSpokenFull.isEmpty) {
      if (isFinal) {
        _consumedNormalizedBuffer = '';
        _consumedCompactLen = 0;
      }
      notifyListeners();
      return;
    }

    final fullCompact = normSpokenFull.replaceAll(' ', '');

    // Extract only the newly spoken portion after what already matched earlier cells,
    // staying resilient even if streaming ASR alters spaces in partial transcripts.
    String deltaCompact = fullCompact;
    if (_consumedNormalizedBuffer.isNotEmpty &&
        normSpokenFull.startsWith(_consumedNormalizedBuffer)) {
      deltaCompact = normSpokenFull
          .substring(_consumedNormalizedBuffer.length)
          .replaceAll(' ', '');
    } else if (_consumedCompactLen > 0 &&
        _consumedCompactLen <= fullCompact.length) {
      deltaCompact = fullCompact.substring(_consumedCompactLen);
    }

    if (deltaCompact.isEmpty) {
      if (isFinal) {
        _consumedNormalizedBuffer = '';
        _consumedCompactLen = 0;
      }
      notifyListeners();
      return;
    }

    // Advance sequentially across 1+ cells if the user recited multiple syllables
    // in a single breath/chunk.
    bool matchedAny = false;
    while (_activeIndex < data.content.length && deltaCompact.isNotEmpty) {
      final targetCell = data.content[_activeIndex];
      final targetCompact =
          _normalizeArabic(targetCell.arabic).replaceAll(' ', '');
      if (targetCompact.isEmpty) {
        _activeIndex++;
        continue;
      }

      final int consumedChars = _matchPrefixLen(
        deltaCompact,
        targetCompact,
        inQuran: targetCell.inQuran,
      );
      if (consumedChars <= 0) break;

      matchedAny = true;
      _mistakeDebounceTimer?.cancel();
      _statuses[targetCell.orderId] = IqroCellStatus.correct;
      _lastMistakeOrderId = -1;
      _activeIndex++;

      deltaCompact = deltaCompact.substring(consumedChars);
      _consumedCompactLen = fullCompact.length - deltaCompact.length;
      _consumedNormalizedBuffer = normSpokenFull;
    }

    if (matchedAny) {
      notifyListeners();
      if (isFinal) {
        _consumedNormalizedBuffer = '';
        _consumedCompactLen = 0;
      }
      return;
    }

    // Mismatch handling:
    // Mark red only when utterance finalizes (VAD) OR when clearly different
    // multi-letter speech was heard for this cell.
    final targetCell = data.content[_activeIndex];
    final targetCompact =
        _normalizeArabic(targetCell.arabic).replaceAll(' ', '');
    final bool hasSubstantialWrongSpeech =
        deltaCompact.length >= (targetCompact.length + 2);

    if (isFinal || hasSubstantialWrongSpeech) {
      if (_lastMistakeOrderId != targetCell.orderId &&
          _statuses[targetCell.orderId] != IqroCellStatus.correct) {
        _statuses[targetCell.orderId] = IqroCellStatus.mistake;
        _lastMistakeOrderId = targetCell.orderId;
        CamcorderSoundHelper.instance.playMistakeAlert();
        MistakeAudioService.instance.scheduleMistakeCapture(
          surah: 200 + data.jilid,
          ayah: data.page,
          wordIndex: targetCell.orderId.clamp(0, 255),
          wordText: targetCell.arabic,
        );
      }
      if (isFinal) {
        _consumedNormalizedBuffer = '';
        _consumedCompactLen = 0;
      }
    }

    notifyListeners();
  }

  /// Normalizes Arabic text for resilient Iqro matching:
  /// - Removes diacritics/harakat, tatweel, punctuation, '='
  /// - Unifies alif/hamza variants (ء آ أ إ ٱ -> ا), ta marbuta (ة -> ت), alif maqsura (ى -> ي)
  static String _normalizeArabic(String input) {
    if (input.isEmpty) return '';
    final sb = StringBuffer();
    for (final rune in input.runes) {
      // Skip tashkeel (U+064B..U+065F, U+0670), tatweel (U+0640), Quranic marks
      if ((rune >= 0x064B && rune <= 0x065F) ||
          rune == 0x0670 ||
          rune == 0x0640 ||
          (rune >= 0x06D6 && rune <= 0x06ED)) {
        continue;
      }
      switch (rune) {
        case 0x0621: // ء
        case 0x0622: // آ
        case 0x0623: // أ
        case 0x0625: // إ
        case 0x0671: // ٱ
          sb.write('ا');
          break;
        case 0x0649: // ى
          sb.write('ي');
          break;
        case 0x0629: // ة
          sb.write('ت');
          break;
        case 0x0624: // ؤ
          sb.write('و');
          break;
        case 0x0626: // ئ
          sb.write('ي');
          break;
        default:
          if ((rune >= 0x0621 && rune <= 0x064A) || rune == 0x20) {
            sb.writeCharCode(rune);
          } else if (rune == 0x3D /* '=' */) {
            sb.write(' ');
          }
      }
    }
    return sb.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Returns how many characters of [sCompact] were consumed if [sCompact] matches
  /// [tCompact], or 0 if not matched. Supports multi-syllable utterances (e.g. "ابت" -> consumes "ا").
  static int _matchPrefixLen(
    String sCompact,
    String tCompact, {
    required bool inQuran,
  }) {
    if (tCompact.isEmpty || sCompact.isEmpty) return 0;

    // 1. Direct prefix/contains match: consume up to end of target match so remaining speech advances next cell
    final int idx = sCompact.indexOf(tCompact);
    if (idx != -1) {
      // Allow at most 1-2 stray leading chars (e.g. elongation 'ا' from previous syllable)
      if (idx <= 2) {
        return idx + tCompact.length;
      }
    }

    // For words that exist in Al-Qur'an, keep strict Quran-ASR word matching.
    if (inQuran) {
      if (sCompact.length >= 3 &&
          tCompact.contains(sCompact) &&
          sCompact.length >= tCompact.length - 1) {
        return sCompact.length;
      }
      if (_similarity(sCompact, tCompact) >= 0.68) {
        return sCompact.length;
      }
      return 0;
    }

    // 2. Non-Quran practice syllables: also check phonetic skeleton
    final sSkel = _toPhoneticSkeleton(sCompact);
    final tSkel = _toPhoneticSkeleton(tCompact);
    final int skelIdx = sSkel.indexOf(tSkel);
    if (skelIdx != -1 && skelIdx <= 2) {
      return (skelIdx + tSkel.length).clamp(1, sCompact.length);
    }

    // 3. Single-letter Hijaiyah tolerance (e.g. ASR hears "با" for "ب")
    if (tSkel.length == 1) {
      final String ch = tSkel[0];
      if (sSkel.startsWith(ch)) return 1;
      if (sSkel.length <= 2 && sSkel.contains(ch)) return sCompact.length;
      return 0;
    }

    // 4. Two-letter cells (e.g. "بت"): require strong overlap, not just 1 letter
    if (tSkel.length == 2) {
      if (sSkel.length >= 2) {
        final int firstIdx = sSkel.indexOf(tSkel[0]);
        if (firstIdx != -1 && firstIdx <= 1) {
          final int secondIdx = sSkel.indexOf(tSkel[1], firstIdx + 1);
          if (secondIdx != -1 && secondIdx - firstIdx <= 2) {
            return (secondIdx + 1).clamp(1, sCompact.length);
          }
        }
        if (_similarity(sSkel, tSkel) >= 0.5) {
          return sCompact.length;
        }
      }
      return 0;
    }

    // 5. Multi-letter non-Quran practice words
    if (sSkel.length >= 2 &&
        tSkel.contains(sSkel) &&
        sSkel.length >= tSkel.length - 1) {
      return sCompact.length;
    }
    if (_similarity(sSkel, tSkel) >= 0.58) {
      return sCompact.length;
    }
    return 0;
  }

  /// Collapses acoustically close Hijaiyah letters for non-Quran practice syllables.
  static String _toPhoneticSkeleton(String s) {
    final sb = StringBuffer();
    for (final rune in s.runes) {
      switch (rune) {
        case 0x0639: // ع
          sb.write('ا');
          break;
        case 0x062B: // ث
        case 0x0635: // ص
          sb.write('س');
          break;
        case 0x0637: // ط
          sb.write('ت');
          break;
        case 0x0636: // ض
          sb.write('د');
          break;
        case 0x0630: // ذ
        case 0x0638: // ظ
          sb.write('ز');
          break;
        case 0x062D: // ح
          sb.write('ه');
          break;
        case 0x0642: // ق
          sb.write('ك');
          break;
        default:
          sb.writeCharCode(rune);
      }
    }
    return sb.toString();
  }

  static double _similarity(String a, String b) {
    if (a == b) return 1.0;
    final maxLen = a.length > b.length ? a.length : b.length;
    if (maxLen == 0) return 1.0;
    final dist = _levenshtein(a, b);
    return 1.0 - (dist / maxLen);
  }

  static int _levenshtein(String s, String t) {
    final n = s.length;
    final m = t.length;
    if (n == 0) return m;
    if (m == 0) return n;
    var prev = List<int>.generate(m + 1, (i) => i);
    var curr = List<int>.filled(m + 1, 0);
    for (int i = 1; i <= n; i++) {
      curr[0] = i;
      for (int j = 1; j <= m; j++) {
        final cost = s.codeUnitAt(i - 1) == t.codeUnitAt(j - 1) ? 0 : 1;
        final del = prev[j] + 1;
        final ins = curr[j - 1] + 1;
        final sub = prev[j - 1] + cost;
        curr[j] = del < ins ? (del < sub ? del : sub) : (ins < sub ? ins : sub);
      }
      final tmp = prev;
      prev = curr;
      curr = tmp;
    }
    return prev[m];
  }

  Future<void> goToPage(int jilid, int page) async {
    await AppState.instance.setIqroPosition(jilid, page);
    final pos = AppState.instance.iqroPositionNotifier.value;
    await loadPage(pos.jilid, pos.page);
  }
}
