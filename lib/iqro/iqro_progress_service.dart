import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class WeakLetterStat {
  final String letter;
  final int mistakes;
  const WeakLetterStat({required this.letter, required this.mistakes});
}

/// Tracks per-page Iqro' mastery scores (0-100%) and per-letter mistake counts
/// in SharedPreferences with zero impact on AI performance.
class IqroProgressService extends ChangeNotifier {
  IqroProgressService._();
  static final IqroProgressService instance = IqroProgressService._();

  static const int passThresholdPct = 80;

  // "jilid-page" -> best accuracy percentage (0..100)
  final Map<String, int> _bestScores = {};
  // single Arabic base letter -> mistake count
  final Map<String, int> _letterMistakes = {};
  bool _loaded = false;

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawScores = prefs.getString('iqro_best_scores');
      if (rawScores != null && rawScores.isNotEmpty) {
        final decoded = json.decode(rawScores) as Map<String, dynamic>;
        decoded.forEach((k, v) {
          if (v is num) _bestScores[k] = v.toInt();
        });
      }
      final rawMistakes = prefs.getString('iqro_letter_mistakes');
      if (rawMistakes != null && rawMistakes.isNotEmpty) {
        final decoded = json.decode(rawMistakes) as Map<String, dynamic>;
        decoded.forEach((k, v) {
          if (v is num) _letterMistakes[k] = v.toInt();
        });
      }
      notifyListeners();
    } catch (_) {}
  }

  int? bestScoreFor(int jilid, int page) => _bestScores['$jilid-$page'];

  bool isPagePassed(int jilid, int page) =>
      (bestScoreFor(jilid, page) ?? 0) >= passThresholdPct;

  int passedCountFor(int jilid, int totalPages) {
    int count = 0;
    for (int p = 1; p <= totalPages; p++) {
      if (isPagePassed(jilid, p)) count++;
    }
    return count;
  }

  List<WeakLetterStat> topWeakLetters({int limit = 5}) {
    final entries = _letterMistakes.entries
        .where((e) => e.value > 0)
        .map((e) => WeakLetterStat(letter: e.key, mistakes: e.value))
        .toList()
      ..sort((a, b) => b.mistakes.compareTo(a.mistakes));
    if (entries.length <= limit) return entries;
    return entries.sublist(0, limit);
  }

  Future<void> recordPageScore(int jilid, int page, int accuracyPct) async {
    await ensureLoaded();
    final key = '$jilid-$page';
    final prev = _bestScores[key] ?? 0;
    if (accuracyPct > prev) {
      _bestScores[key] = accuracyPct.clamp(0, 100);
      notifyListeners();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('iqro_best_scores', json.encode(_bestScores));
    }
  }

  Future<void> recordMistakeLetters(String arabicText) async {
    await ensureLoaded();
    bool changed = false;
    for (final rune in arabicText.runes) {
      // Base Hijaiyah letters U+0621..U+064A
      if (rune >= 0x0621 && rune <= 0x064A) {
        final ch = String.fromCharCode(rune);
        _letterMistakes[ch] = (_letterMistakes[ch] ?? 0) + 1;
        changed = true;
      }
    }
    if (changed) {
      notifyListeners();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'iqro_letter_mistakes',
        json.encode(_letterMistakes),
      );
    }
  }

  Future<void> clearWeakLetters() async {
    _letterMistakes.clear();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('iqro_letter_mistakes');
  }
}
