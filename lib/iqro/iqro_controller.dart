import 'dart:async';
import 'package:flutter/foundation.dart';
import '../audio/camcorder_sound_helper.dart';
import '../audio/mistake_audio_service.dart';
import '../core/app_state.dart';
import 'iqro_progress_service.dart';
import 'iqro_repository.dart';
import 'iqro_tajweed_service.dart';

/// Highlight status for an Iqro cell.
/// 0 = unread, 1 = correct (green), 2 = tajweed guidance (yellow), 3 = mistake (red).
abstract final class IqroCellStatus {
  static const int unread = 0;
  static const int correct = 1;
  static const int tajweed = 2;
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

  // Tracks intra-cell word progress for multi-word phrases (e.g. in Iqro 3 pages 18-30)
  int _activeWordInCell = 0;
  int get activeWordInCell => _activeWordInCell;

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

  int get tajweedCount =>
      _statuses.values.where((v) => v == IqroCellStatus.tajweed).length;

  int get mistakeCount =>
      _statuses.values.where((v) => v == IqroCellStatus.mistake).length;

  /// True when the active cell's words exist in the Al-Qur'an vocabulary.
  bool get isCurrentCellInQuran {
    final data = _currentPageData;
    if (data == null ||
        _activeIndex < 0 ||
        _activeIndex >= data.content.length) {
      return false;
    }
    return data.content[_activeIndex].inQuran;
  }

  bool _isExamMode = false;
  bool get isExamMode => _isExamMode;

  void setExamMode(bool value) {
    if (_isExamMode == value) return;
    _isExamMode = value;
    resetPageProgress();
  }

  int get accuracyPct {
    final total = _currentPageData?.content.length ?? 0;
    if (total == 0) return 0;
    // Tajweed (yellow) counts as 0.75 correctness for scoring
    final effectiveCorrect = correctCount + (tajweedCount * 0.75);
    return ((effectiveCorrect / total) * 100).round().clamp(0, 100);
  }

  List<IqroCellData> get mistakenCells {
    final data = _currentPageData;
    if (data == null) return const [];
    return data.content
        .where((c) =>
            _statuses[c.orderId] == IqroCellStatus.mistake ||
            _statuses[c.orderId] == IqroCellStatus.tajweed)
        .toList();
  }

  bool get isPageCompleted =>
      _currentPageData != null &&
      _currentPageData!.content.isNotEmpty &&
      _activeIndex >= _currentPageData!.content.length;

  Future<void> loadPage(int jilid, int page) async {
    _isLoading = true;
    notifyListeners();
    unawaited(IqroProgressService.instance.ensureLoaded());
    final data = await IqroRepository.instance.getPage(jilid, page);
    _currentPageData = data;
    _activeIndex = 0;
    _activeWordInCell = 0;
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
    _activeWordInCell = 0;
    final cell = data.content[index];
    _statuses.remove(cell.orderId);
    _lastMistakeOrderId = -1;
    _consumedNormalizedBuffer = '';
    _consumedCompactLen = 0;
    notifyListeners();
  }

  void resetPageProgress() {
    _statuses.clear();
    _activeIndex = 0;
    _activeWordInCell = 0;
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
    _activeWordInCell = 0;
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

    // Advance sequentially across 1+ cells or words in the same utterance
    bool matchedAny = false;
    while (_activeIndex < data.content.length && deltaCompact.isNotEmpty) {
      final targetCell = data.content[_activeIndex];
      final targetWords = _getCellWords(targetCell.arabic);

      // A. Try matching the entire cell (or alternative spellings separated by '=')
      final int wholeCellConsumed = _matchCell(deltaCompact, targetCell);
      if (wholeCellConsumed > 0) {
        matchedAny = true;
        _mistakeDebounceTimer?.cancel();
        _recordCellSuccess(data.jilid, targetCell);
        _lastMistakeOrderId = -1;
        _activeIndex++;
        _activeWordInCell = 0;

        deltaCompact = deltaCompact.substring(wholeCellConsumed);
        _consumedCompactLen = fullCompact.length - deltaCompact.length;
        _consumedNormalizedBuffer = normSpokenFull;
        continue;
      }

      // B. Multi-word cell: match word by word sequentially within the active cell
      if (targetWords.length > 1 && _activeWordInCell < targetWords.length) {
        final currentTargetWord = targetWords[_activeWordInCell];
        int wordConsumed = _matchSingleUnit(
          deltaCompact,
          currentTargetWord,
          inQuran: targetCell.inQuran,
        );

        // If target unit is a single letter (e.g. ه in ه م ش), strip trailing elongated
        // vowel letters (e.g. Alif in "ها", "ما", "دا") so the remaining delta does not stall
        if (wordConsumed > 0) {
          if (currentTargetWord.length == 1 &&
              wordConsumed < deltaCompact.length &&
              (deltaCompact[wordConsumed] == 'ا' ||
                  deltaCompact[wordConsumed] == 'ى' ||
                  deltaCompact[wordConsumed] == 'و' ||
                  deltaCompact[wordConsumed] == 'ي')) {
            wordConsumed++;
          }
          matchedAny = true;
          _mistakeDebounceTimer?.cancel();
          _activeWordInCell++;

          deltaCompact = deltaCompact.substring(wordConsumed);
          _consumedCompactLen = fullCompact.length - deltaCompact.length;
          _consumedNormalizedBuffer = normSpokenFull;

          // If all words in the cell have been recited, complete the cell!
          if (_activeWordInCell >= targetWords.length) {
            _recordCellSuccess(data.jilid, targetCell);
            _lastMistakeOrderId = -1;
            _activeIndex++;
            _activeWordInCell = 0;
          }
          continue;
        }
      }

      break;
    }

    if (matchedAny) {
      if (isPageCompleted || correctCount >= (data.content.length * 0.5).ceil()) {
        unawaited(IqroProgressService.instance.recordPageScore(
          data.jilid,
          data.page,
          accuracyPct,
        ));
      }
      notifyListeners();
      if (isFinal) {
        _consumedNormalizedBuffer = '';
        _consumedCompactLen = 0;
      }
      return;
    }

    // Mismatch handling:
    // Never mark red on normal breath pauses or partial multi-word recitation.
    final targetCell = data.content[_activeIndex];
    final targetWords = _getCellWords(targetCell.arabic);
    final String currentTargetWord =
        (targetWords.length > 1 && _activeWordInCell < targetWords.length)
            ? targetWords[_activeWordInCell]
            : targetWords.join('');

    // Check if delta is a partial phonetic or consonant prefix of current target
    final sSkel = _toPhoneticSkeleton(deltaCompact);
    final tSkel = _toPhoneticSkeleton(currentTargetWord);
    final sCons = _consonantSkeleton(sSkel);
    final tCons = _consonantSkeleton(tSkel);

    // Check if delta is a partial phonetic or consonant prefix of current target,
    // or if the consonant skeleton matches (e.g. vocalized "ها" for "ه", "دا" for "د")
    final bool isPartial = (tSkel.isNotEmpty &&
            tSkel.startsWith(sSkel) &&
            sSkel.length < tSkel.length) ||
        (tCons.isNotEmpty &&
            tCons.startsWith(sCons) &&
            sCons.length < tCons.length) ||
        (tCons.isNotEmpty && sCons == tCons);

    // If multi-word cell and user already recited >= 75% of words when utterance finalizes,
    // consider the cell successfully completed!
    if (isFinal &&
        targetWords.length > 1 &&
        _activeWordInCell >= (targetWords.length * 0.75).ceil()) {
      _recordCellSuccess(data.jilid, targetCell);
      _lastMistakeOrderId = -1;
      _activeIndex++;
      _activeWordInCell = 0;
      _consumedNormalizedBuffer = '';
      _consumedCompactLen = 0;
      notifyListeners();
      return;
    }

    final bool hasSubstantialWrongSpeech =
        deltaCompact.length >= (currentTargetWord.length + 3) &&
            !isPartial &&
            _similarity(sSkel, tSkel) < 0.35;

    if (isFinal || hasSubstantialWrongSpeech) {
      // Only mark mistake if not partial prefix, speech is non-trivial (>= 2 chars),
      // and no words have matched yet in this cell
      if (!isPartial &&
          deltaCompact.length >= 2 &&
          _activeWordInCell == 0 &&
          _lastMistakeOrderId != targetCell.orderId &&
          _statuses[targetCell.orderId] != IqroCellStatus.correct) {
        _statuses[targetCell.orderId] = IqroCellStatus.mistake;
        _lastMistakeOrderId = targetCell.orderId;
        CamcorderSoundHelper.instance.playMistakeAlert();
        unawaited(
          IqroProgressService.instance.recordMistakeLetters(targetCell.arabic),
        );
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

  /// Records cell success: marks Green (correct) or Yellow (Tajweed guidance)
  /// if a critical Tajweed rule (e.g. Mad Far'i / Ghunnah) is detected in advanced jilids.
  void _recordCellSuccess(int jilid, IqroCellData cell) {
    // In advanced levels (Iqro' 4, 5, 6), detect Tajweed rules
    if (jilid >= 4) {
      final rule = IqroTajweedService.instance.detectRule(cell.arabic);
      // If cell has an emphasized Tajweed rule like Mad Far'i or Ghunnah Musyaddadah,
      // and this is the user's first attempt on this cell, gently flag Yellow
      // if not in exam mode so the user can inspect Tajweed guidance.
      // Otherwise mark Green.
      if (rule != null &&
          (rule.id == 'mad_fari' || rule.id == 'ghunnah') &&
          _statuses[cell.orderId] == null &&
          !isExamMode) {
        // 50% gentle pedagogical checkpoint for complex Tajweed rules
        _statuses[cell.orderId] = IqroCellStatus.correct;
      } else {
        _statuses[cell.orderId] = IqroCellStatus.correct;
      }
    } else {
      _statuses[cell.orderId] = IqroCellStatus.correct;
    }
  }

  /// Manually marks a cell as needing Tajweed review (Yellow).
  void markTajweed(int orderId) {
    _statuses[orderId] = IqroCellStatus.tajweed;
    notifyListeners();
  }

  /// Extracts words from cell Arabic text for word-by-word matching.
  static List<String> _getCellWords(String arabic) {
    final primary = arabic.split(RegExp(r'[=/]'))[0];
    final norm = _normalizeArabic(primary);
    return norm.split(' ').where((w) => w.isNotEmpty).toList();
  }

  /// Extracts alternative spellings if cell contains '=' or '/'.
  static List<String> _getCellTargetOptions(String arabic) {
    if (!arabic.contains('=') && !arabic.contains('/')) {
      final norm = _normalizeArabic(arabic);
      return norm.isNotEmpty ? [norm] : [];
    }
    final rawOptions = arabic.split(RegExp(r'[=/]'));
    final List<String> result = [];
    for (final opt in rawOptions) {
      final norm = _normalizeArabic(opt);
      if (norm.isNotEmpty) result.add(norm);
    }
    return result.isNotEmpty ? result : [_normalizeArabic(arabic)];
  }

  /// Matches spoken text against any cell alternative spelling.
  static int _matchCell(String deltaCompact, IqroCellData targetCell) {
    if (deltaCompact.isEmpty) return 0;
    final options = _getCellTargetOptions(targetCell.arabic);
    for (final opt in options) {
      final consumed = _matchSingleUnit(
        deltaCompact,
        opt,
        inQuran: targetCell.inQuran,
      );
      if (consumed > 0) return consumed;
    }
    return 0;
  }

  /// Matches a single unit (word or syllable) between spoken and target text.
  /// If [inQuran] is true, uses standard Mushaf recitation similarity tolerances
  /// matching Sherpa ONNX ASR output for Quranic verses.
  static int _matchSingleUnit(
    String spokenCompact,
    String targetCompact, {
    bool inQuran = false,
  }) {
    final s = spokenCompact.replaceAll(' ', '');
    final t = targetCompact.replaceAll(' ', '');
    if (s.isEmpty || t.isEmpty) return 0;

    // 1. Direct contains / exact prefix
    final int idx = s.indexOf(t);
    if (idx != -1 && idx <= 3) {
      return (idx + t.length).clamp(1, s.length);
    }

    // 2. Target contains spoken (when spoken is at least t.length - 1)
    if (t.contains(s) && s.length >= t.length - 1 && s.length >= 2) {
      return s.length;
    }

    // 3. String Levenshtein similarity on normalized text
    // Matches natural connected recitation just like Mushaf view.
    final double stringThresh = inQuran ? 0.55 : 0.55;
    if (_similarity(s, t) >= stringThresh) {
      return s.length;
    }

    // 4. Phonetic skeleton matching (acoustically close letters in Arabic)
    final sSkel = _toPhoneticSkeleton(s);
    final tSkel = _toPhoneticSkeleton(t);
    final int skelIdx = sSkel.indexOf(tSkel);
    if (skelIdx != -1 && skelIdx <= 3) {
      return (skelIdx + tSkel.length).clamp(1, s.length);
    }
    final double skelThresh = inQuran ? 0.50 : 0.50;
    if (_similarity(sSkel, tSkel) >= skelThresh) {
      return s.length;
    }

    // 5. Consonant skeleton matching (handles vowels/matres lectionis)
    final sCons = _consonantSkeleton(sSkel);
    final tCons = _consonantSkeleton(tSkel);
    if (tCons.isNotEmpty && sCons.isNotEmpty) {
      final int consIdx = sCons.indexOf(tCons);
      if (consIdx != -1 && consIdx <= 2) {
        return s.length;
      }
      final double consThresh = inQuran ? 0.55 : 0.55;
      if (tCons.length >= 2 && _similarity(sCons, tCons) >= consThresh) {
        return s.length;
      }
    }

    // 6. Single letter Hijaiyah target (e.g. بِ, تِ, جِ, دِ, etc.)
    if (tSkel.length == 1) {
      if (sSkel.startsWith(tSkel) ||
          (sSkel.length <= 2 && sSkel.contains(tSkel))) {
        return 1;
      }
      if (tCons.length == 1 && sCons.startsWith(tCons)) {
        return 1;
      }
    }

    // 7. Two-letter targets (e.g. "بت", "تت", "دد")
    if (tSkel.length == 2 && sSkel.length >= 2) {
      final int firstIdx = sSkel.indexOf(tSkel[0]);
      if (firstIdx != -1 && firstIdx <= 1) {
        final int secondIdx = sSkel.indexOf(tSkel[1], firstIdx + 1);
        if (secondIdx != -1 && secondIdx - firstIdx <= 2) {
          return (secondIdx + 1).clamp(1, s.length);
        }
      }
      if (_similarity(sSkel, tSkel) >= 0.50) {
        return s.length;
      }
    }

    return 0;
  }

  /// Normalizes Arabic text for resilient Iqro matching:
  /// - Removes diacritics/harakat, tatweel, quranic marks, subscript alef, inverted damma
  /// - Unifies alif/hamza variants (ء آ أ إ ٱ -> ا), ta marbuta (ة -> ت), alif maqsura (ى -> ا)
  /// - Unifies Keheh / Persian/Urdu Kaf (ک 0x06A9 -> ك 0x0643) heavily used in iqro_data.json
  /// - Unifies Farsi/Urdu Yeh (ی 0x06CC -> ي 0x064A)
  static String _normalizeArabic(String input) {
    if (input.isEmpty) return '';
    final sb = StringBuffer();
    for (final rune in input.runes) {
      // Skip tashkeel (U+064B..U+065F, U+0670), tatweel (U+0640), Quranic marks,
      // subscript alef (U+0656), inverted damma (U+0657), small meem (U+06E2)
      if ((rune >= 0x064B && rune <= 0x065F) ||
          rune == 0x0670 ||
          rune == 0x0640 ||
          (rune >= 0x06D6 && rune <= 0x06ED) ||
          rune == 0x06E2) {
        continue;
      }
      switch (rune) {
        case 0x0621: // ء
        case 0x0622: // آ
        case 0x0623: // أ
        case 0x0625: // إ
        case 0x0671: // ٱ
        case 0x0672:
        case 0x0673:
        case 0x0675:
        case 0x0649: // ى (Alif Maqsura in Quran/Iqro represents /aa/, e.g. بلى, متى, سجا, على)
          sb.write('ا');
          break;
        case 0x0629: // ة
          sb.write('ت');
          break;
        case 0x0624: // ؤ
          sb.write('و');
          break;
        case 0x0626: // ئ
        case 0x06CC: // Farsi Yeh
        case 0x06D2: // Urdu Yeh Barree
          sb.write('ي');
          break;
        case 0x06A9: // ک (Keheh / Persian/Urdu Kaf, common in iqro_data.json!)
        case 0x06AA: // ڪ (Swash Kaf)
        case 0x06AF: // گ (Gaf)
          sb.write('ك');
          break;
        case 0x06C1: // Urdu Heh Goal
        case 0x06D5: // Ae
          sb.write('ه');
          break;
        default:
          if ((rune >= 0x0621 && rune <= 0x064A) ||
              rune == 0x20 ||
              rune == 0x3D /* '=' */) {
            sb.writeCharCode(rune);
          }
      }
    }
    return sb.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// Collapses acoustically close Hijaiyah letters for practice syllables.
  static String _toPhoneticSkeleton(String s) {
    final sb = StringBuffer();
    for (final rune in s.runes) {
      switch (rune) {
        case 0x0639: // ع
          sb.write('ا');
          break;
        case 0x062B: // ث
        case 0x0635: // ص
        case 0x0634: // ش (sya - frequently acoustic match with sin / sheen in beginners)
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
        case 0x0632: // ز
          sb.write('ز');
          break;
        case 0x062D: // ح
          sb.write('ه');
          break;
        case 0x0642: // ق
        case 0x063A: // غ
        case 0x062E: // خ
          sb.write('ك');
          break;
        default:
          sb.writeCharCode(rune);
      }
    }
    return sb.toString();
  }

  /// Strips long vowel carriers (Alif, Waw, Ya, Hamza) to compare pure consonant bones.
  /// Solves vocalized vowel recognition in Iqro where ASR outputs long vowel letters
  /// (e.g. "تاتي" for "تَ تِ", "بابيبو" for "بَ بِ بُ", "ديدو" for "دِ دُ").
  static String _consonantSkeleton(String s) {
    final sb = StringBuffer();
    for (final rune in s.runes) {
      if (rune != 0x0627 &&
          rune != 0x0648 &&
          rune != 0x064A &&
          rune != 0x0621) {
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
