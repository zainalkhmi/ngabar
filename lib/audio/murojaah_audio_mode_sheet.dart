import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/app_state.dart';
import '../core/highlighting_controller.dart';
import 'camcorder_sound_helper.dart';
import 'quran_audio_service.dart';

/// Hands-free Audio-Only Muroja'ah sheet.
/// Plays an ayah via Al-Husary, pauses for a configurable recitation window
/// with a gentle chime, then auto-advances (or repeats) without touching
/// the Sherpa-ONNX AI detection pipeline.
class MurojaahAudioModeSheet extends StatefulWidget {
  const MurojaahAudioModeSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const MurojaahAudioModeSheet(),
    ).then((_) {
      unawaited(QuranAudioService.instance.stop());
    });
  }

  @override
  State<MurojaahAudioModeSheet> createState() =>
      _MurojaahAudioModeSheetState();
}

class _MurojaahAudioModeSheetState extends State<MurojaahAudioModeSheet> {
  late int _surah;
  late int _ayah;
  int _pauseSeconds = 8;
  bool _repeatAyah = false;
  bool _isRunning = false;
  bool _isReciteWindow = false;
  int _remainingPause = 0;
  int _runGeneration = 0;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    final app = AppState.instance;
    _surah = QuranMetadata.clampSurah(app.lastSurah);
    _ayah = app.lastAyah.clamp(1, QuranMetadata.getAyahCount(_surah));
  }

  @override
  void dispose() {
    _runGeneration++;
    _countdownTimer?.cancel();
    unawaited(QuranAudioService.instance.stop());
    super.dispose();
  }

  Future<void> _startLoop() async {
    final int gen = ++_runGeneration;
    setState(() {
      _isRunning = true;
      _isReciteWindow = false;
    });

    while (mounted && _isRunning && gen == _runGeneration) {
      setState(() {
        _isReciteWindow = false;
        _remainingPause = 0;
      });

      await QuranAudioService.instance.play(
        surah: _surah,
        ayah: _ayah,
        continuous: false,
      );

      // Wait until ayah playback starts & completes
      await Future<void>.delayed(const Duration(milliseconds: 350));
      while (mounted &&
          _isRunning &&
          gen == _runGeneration &&
          QuranAudioService.instance.isPlayingNotifier.value) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
      }

      if (!mounted || !_isRunning || gen != _runGeneration) break;

      // Enter hands-free user recite window
      CamcorderSoundHelper.instance.playRecordChime(isStart: true);
      setState(() {
        _isReciteWindow = true;
        _remainingPause = _pauseSeconds;
      });

      for (int s = _pauseSeconds; s > 0; s--) {
        if (!mounted || !_isRunning || gen != _runGeneration) break;
        setState(() => _remainingPause = s);
        await Future<void>.delayed(const Duration(seconds: 1));
      }

      if (!mounted || !_isRunning || gen != _runGeneration) break;

      if (!_repeatAyah) {
        final maxAyah = QuranMetadata.getAyahCount(_surah);
        if (_ayah < maxAyah) {
          setState(() => _ayah++);
        } else if (_surah < 114) {
          setState(() {
            _surah++;
            _ayah = 1;
          });
        } else {
          _stopLoop();
          break;
        }
      }
    }
  }

  void _stopLoop() {
    _runGeneration++;
    _countdownTimer?.cancel();
    unawaited(QuranAudioService.instance.stop());
    if (mounted) {
      setState(() {
        _isRunning = false;
        _isReciteWindow = false;
        _remainingPause = 0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    final c = app.colors;
    final isDark = app.isDarkMode;
    final surahName = QuranMetadata.getSurahNameArabic(_surah);
    final maxAyah = QuranMetadata.getAyahCount(_surah);

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        border: Border.all(color: c.border.withValues(alpha: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: c.textSecondary.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981)
                        .withValues(alpha: isDark ? 0.2 : 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.headphones_rounded,
                    color: Color(0xFF10B981),
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Audio-Only Muroja'ah (Hands-Free)",
                        style: TextStyle(
                          fontFamily: 'cairo',
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: c.text,
                        ),
                      ),
                      Text(
                        'Putar ayat → jeda giliran Anda → lanjut otomatis',
                        style: TextStyle(
                          fontFamily: 'cairo',
                          fontSize: 11.5,
                          color: c.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Current Surah & Ayah card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: c.bg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _isReciteWindow
                      ? const Color(0xFFF59E0B)
                      : c.border.withValues(alpha: 0.5),
                  width: _isReciteWindow ? 1.6 : 1.0,
                ),
              ),
              child: Column(
                children: [
                  Text(
                    '$surahName • Ayat $_ayah / $maxAyah',
                    style: TextStyle(
                      fontFamily: 'cairo',
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                      color: c.text,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    !_isRunning
                        ? 'Siap diputar untuk muroja\'ah tanpa lihat layar'
                        : (_isReciteWindow
                            ? 'Giliran Anda mengulang... ($_remainingPause dtk)'
                            : 'Mendengarkan Qari Al-Husary...'),
                    style: TextStyle(
                      fontFamily: 'cairo',
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: _isReciteWindow
                          ? const Color(0xFFF59E0B)
                          : const Color(0xFF10B981),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Pause duration & repeat controls
            Row(
              children: [
                Text(
                  'Jeda Baca:',
                  style: TextStyle(
                    fontFamily: 'cairo',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: c.textSecondary,
                  ),
                ),
                const SizedBox(width: 8),
                for (final sec in [5, 8, 12, 18])
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(
                      label: Text(
                        '${sec}s',
                        style: const TextStyle(
                          fontFamily: 'cairo',
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      selected: _pauseSeconds == sec,
                      onSelected: (_) => setState(() => _pauseSeconds = sec),
                      selectedColor: const Color(0xFF10B981).withValues(alpha: 0.2),
                    ),
                  ),
                const Spacer(),
                FilterChip(
                  label: const Text(
                    'Ulangi',
                    style: TextStyle(
                      fontFamily: 'cairo',
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  selected: _repeatAyah,
                  onSelected: (v) => setState(() => _repeatAyah = v),
                  selectedColor: const Color(0xFF10B981).withValues(alpha: 0.2),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Big Hands-Free Transport Controls
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton.filledTonal(
                  iconSize: 28,
                  onPressed: _ayah > 1
                      ? () {
                          HapticFeedback.selectionClick();
                          setState(() => _ayah--);
                        }
                      : null,
                  icon: const Icon(Icons.skip_previous_rounded),
                ),
                const SizedBox(width: 18),
                GestureDetector(
                  onTap: () {
                    HapticFeedback.mediumImpact();
                    if (_isRunning) {
                      _stopLoop();
                    } else {
                      _startLoop();
                    }
                  },
                  child: Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      color: _isRunning
                          ? const Color(0xFFEF4444)
                          : const Color(0xFF10B981),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: (_isRunning
                                  ? const Color(0xFFEF4444)
                                  : const Color(0xFF10B981))
                              .withValues(alpha: 0.35),
                          blurRadius: 14,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Icon(
                      _isRunning
                          ? Icons.stop_rounded
                          : Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 36,
                    ),
                  ),
                ),
                const SizedBox(width: 18),
                IconButton.filledTonal(
                  iconSize: 28,
                  onPressed: _ayah < maxAyah
                      ? () {
                          HapticFeedback.selectionClick();
                          setState(() => _ayah++);
                        }
                      : null,
                  icon: const Icon(Icons.skip_next_rounded),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
