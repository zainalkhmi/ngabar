import 'dart:async';
import 'package:flutter/foundation.dart';
import '../audio/camcorder_sound_helper.dart';
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

  // Tracks what ASR text was already consumed for previous cells in the same utterance
  String _consumedNormalizedBuffer = '';
  int _lastMistakeOrderId = -1;
  Timer? _mistakeDebounceTimer;

  int statusFor(int orderId) => _statuses[orderId] ?? IqroCellStatus.unread;

  int get correctCount =>
      _statuses.values.where((v) => v == IqroCellStatus.correct).length;

  int get mistakeCount =>
      _statuses.values.where((v) => v == IqroCellStatus.mistake).length;

  Future<void> loadPage(int jilid, int page) async {
    _isLoading = true;
    notifyListeners();
    final data = await IqroRepository.instance.getPage(jilid, page);
    _currentPageData = data;
    _activeIndex = 0;
    _statuses.clear();
    _lastHeardText = '';
    _consumedNormalizedBuffer = '';
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
    _lastMistakeOrderId = -1;
    notifyListeners();
  }

  void resetSessionBuffer() {
    _lastHeardText = '';
    _consumedNormalizedBuffer = '';
    _mistakeDebounceTimer?.cancel();
  }

  /// Processes real-time Arabic transcription from SherpaEngine while in Iqro mode.
  void onTranscription(String rawText, {required bool isFinal}) {
    final data = _currentPageData;
    if (data == null || data.content.isEmpty) return;
    if (_activeIndex >= data.content.length) return;

    final trimmed = rawText.trim();
    if (trimmed.isNotEmpty) {
      _lastHeardText = trimmed;
    }

    final normSpokenFull = _normalizeArabic(trimmed);
    if (normSpokenFull.isEmpty) {
      if (isFinal) _consumedNormalizedBuffer = '';
      notifyListeners();
      return;
    }

    // Extract only the newly spoken portion after what already matched earlier cells
    String normDelta = normSpokenFull;
    if (_consumedNormalizedBuffer.isNotEmpty &&
        normSpokenFull.startsWith(_consumedNormalizedBuffer)) {
      normDelta = normSpokenFull.substring(_consumedNormalizedBuffer.length).trim();
    }

    if (normDelta.isEmpty) {
      if (isFinal) _consumedNormalizedBuffer = '';
      notifyListeners();
      return;
    }

    final targetCell = data.content[_activeIndex];
    final normTarget = _normalizeArabic(targetCell.arabic);

    if (_isMatch(normDelta, normTarget)) {
      _mistakeDebounceTimer?.cancel();
      _statuses[targetCell.orderId] = IqroCellStatus.correct;
      _consumedNormalizedBuffer = normSpokenFull;
      _lastMistakeOrderId = -1;
      if (_activeIndex + 1 < data.content.length) {
        _activeIndex++;
      }
      notifyListeners();
      if (isFinal) {
        _consumedNormalizedBuffer = '';
      }
      return;
    }

    // Mismatch handling:
    // Mark red only when utterance finalizes (VAD) OR when clearly different
    // multi-letter speech was heard for this cell.
    final bool hasSubstantialWrongSpeech =
        normDelta.replaceAll(' ', '').length >=
            (normTarget.replaceAll(' ', '').length + 2);

    if (isFinal || hasSubstantialWrongSpeech) {
      if (_lastMistakeOrderId != targetCell.orderId) {
        _statuses[targetCell.orderId] = IqroCellStatus.mistake;
        _lastMistakeOrderId = targetCell.orderId;
        CamcorderSoundHelper.instance.playMistakeAlert();
      }
      if (isFinal) {
        _consumedNormalizedBuffer = '';
      }
    }

    notifyListeners();
  }

  /// Normalizes Arabic text for resilient Iqro matching:
  /// - Removes diacritics/harakat, tatweel, punctuation, '='
  /// - Unifies alif variants (أ إ آ ٱ -> ا), ta marbuta (ة -> ه/ت), alif maqsura (ى -> ي)
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

  static bool _isMatch(String spoken, String target) {
    if (target.isEmpty || spoken.isEmpty) return false;
    final sCompact = spoken.replaceAll(' ', '');
    final tCompact = target.replaceAll(' ', '');
    if (sCompact.isEmpty || tCompact.isEmpty) return false;

    // Exact or substring match
    if (sCompact.contains(tCompact) ||
        (sCompact.length >= 2 && tCompact.contains(sCompact))) {
      return true;
    }

    // Phonetic / near-homophone tolerance for short Hijaiyah / Quran ASR output
    final sSim = _similarity(sCompact, tCompact);
    if (tCompact.length <= 2) {
      // Single/double-letter Iqro 1-2: match if first/any base letter matches
      for (int i = 0; i < tCompact.length; i++) {
        if (sCompact.contains(tCompact[i])) return true;
      }
      return sSim >= 0.5;
    }
    return sSim >= 0.65;
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
