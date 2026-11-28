import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../core/app_state.dart';

enum MadTargetType { none, ghunnah2, mad45, mad6 }

class MadMeterState {
  final MadTargetType type;
  final String label;
  final double currentHarakat;
  final double minTarget;
  final double maxTarget;

  const MadMeterState({
    required this.type,
    required this.label,
    required this.currentHarakat,
    required this.minTarget,
    required this.maxTarget,
  });

  bool get isInRange =>
      currentHarakat >= minTarget && currentHarakat <= maxTarget + 0.8;
}

/// Real-time Mad & Ghunnah duration meter.
/// Passively measures sustained voiced RMS energy from existing 16kHz PCM chunks
/// without modifying or slowing down Sherpa-ONNX AI detection.
class MadDurationMeter {
  MadDurationMeter._();
  static final MadDurationMeter instance = MadDurationMeter._();

  static const double _msPerHarakat = 230.0;
  static const double _voicedRmsThreshold = 0.014;

  final ValueNotifier<MadMeterState?> stateNotifier =
      ValueNotifier<MadMeterState?>(null);

  int _lastWordKey = -1;
  MadTargetType _activeType = MadTargetType.none;
  String _activeLabel = '';
  double _minTarget = 2.0;
  double _maxTarget = 2.0;
  int _voicedMs = 0;

  void reset() {
    _lastWordKey = -1;
    _activeType = MadTargetType.none;
    _voicedMs = 0;
    stateNotifier.value = null;
  }

  /// Updates the active word being recited so the meter knows whether to
  /// track a 2-harakat Ghunnah/Dengung or a 4-6 harakat Mad.
  void updateActiveWord({
    required int wordKey,
    required String uthmaniWord,
  }) {
    if (wordKey == _lastWordKey) return;
    _lastWordKey = wordKey;
    _voicedMs = 0;

    final detected = _classifyWord(uthmaniWord);
    _activeType = detected.$1;
    _activeLabel = detected.$2;
    _minTarget = detected.$3;
    _maxTarget = detected.$4;

    if (_activeType == MadTargetType.none) {
      stateNotifier.value = null;
    } else {
      stateNotifier.value = MadMeterState(
        type: _activeType,
        label: _activeLabel,
        currentHarakat: 0.0,
        minTarget: _minTarget,
        maxTarget: _maxTarget,
      );
    }
  }

  /// Passively inspects 16kHz Float32 PCM chunks in microseconds.
  void onAudioChunk(Float32List chunk) {
    if (_activeType == MadTargetType.none || chunk.isEmpty) return;

    // Fast RMS energy check (step by 4 samples for ultra-low CPU)
    double sumSq = 0.0;
    int count = 0;
    for (int i = 0; i < chunk.length; i += 4) {
      final s = chunk[i];
      sumSq += s * s;
      count++;
    }
    final double rms = count > 0 ? math.sqrt(sumSq / count) : 0.0;
    final int chunkMs = ((chunk.length / 16000.0) * 1000.0).round();

    if (rms >= _voicedRmsThreshold) {
      _voicedMs += chunkMs;
      final double harakat = (_voicedMs / _msPerHarakat).clamp(0.0, 7.0);
      stateNotifier.value = MadMeterState(
        type: _activeType,
        label: _activeLabel,
        currentHarakat: harakat,
        minTarget: _minTarget,
        maxTarget: _maxTarget,
      );
    }
  }

  static (MadTargetType, String, double, double) _classifyWord(String word) {
    if (word.isEmpty) return (MadTargetType.none, '', 0, 0);
    final runes = word.runes.toList();

    // Maddah sign U+0653 (ٓ) -> Mad Wajib / Jaiz (4-5) or Mad Lazim (6 if followed by shaddah U+0651)
    final int maddahIdx = runes.indexOf(0x0653);
    if (maddahIdx != -1) {
      final bool hasShaddahAfter =
          runes.skip(maddahIdx + 1).any((r) => r == 0x0651);
      if (hasShaddahAfter) {
        return (MadTargetType.mad6, 'Mad Lazim • 6 Harakat', 5.5, 6.5);
      }
      return (MadTargetType.mad45, 'Mad Wajib/Jaiz • 4–5 Harakat', 4.0, 5.5);
    }

    // Nun/Mim Mushaddadah (نّ / مّ) -> Ghunnah 2 Harakat
    for (int i = 0; i < runes.length - 1; i++) {
      if ((runes[i] == 0x0646 || runes[i] == 0x0645) &&
          runes[i + 1] == 0x0651) {
        return (MadTargetType.ghunnah2, 'Ghunnah / Dengung • 2 Harakat', 1.8, 2.8);
      }
    }

    // Nun Sukun (نْ) or Tanwin (ً ٍ ٌ) -> Dengung / Ikhfa / Idgham 2 Harakat
    if (word.contains('\u0646\u0652') ||
        runes.any((r) => r == 0x064B || r == 0x064C || r == 0x064D)) {
      return (MadTargetType.ghunnah2, 'Dengung / Ikhfa • 2 Harakat', 1.8, 2.8);
    }

    return (MadTargetType.none, '', 0, 0);
  }
}

/// Floating real-time Mad & Ghunnah beat meter widget.
class MadMeterPill extends StatelessWidget {
  const MadMeterPill({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = AppState.instance.isDarkMode;

    return ValueListenableBuilder<MadMeterState?>(
      valueListenable: MadDurationMeter.instance.stateNotifier,
      builder: (context, st, _) {
        if (st == null) return const SizedBox.shrink();

        final Color barColor = st.isInRange
            ? const Color(0xFF10B981)
            : (st.currentHarakat < st.minTarget
                ? const Color(0xFFF59E0B)
                : const Color(0xFF38BDF8));

        final double progress = (st.currentHarakat / 6.0).clamp(0.0, 1.0);

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: (isDark ? const Color(0xFF0F172A) : Colors.white)
                .withValues(alpha: 0.94),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: barColor.withValues(alpha: 0.65),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.10),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(Icons.equalizer_rounded, size: 16, color: barColor),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      st.label,
                      style: TextStyle(
                        fontFamily: 'cairo',
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                  ),
                  Text(
                    '${st.currentHarakat.toStringAsFixed(1)} ketuk',
                    style: TextStyle(
                      fontFamily: 'cairo',
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: barColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // 0..6 harakat bar with 2, 4, 6 beat markers
              Stack(
                children: [
                  Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.10)
                          : Colors.black.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  FractionallySizedBox(
                    widthFactor: progress,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      height: 8,
                      decoration: BoxDecoration(
                        color: barColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  for (final mark in const ['0', '2', '4', '6'])
                    Text(
                      mark,
                      style: TextStyle(
                        fontFamily: 'cairo',
                        fontSize: 9.5,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF64748B),
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
