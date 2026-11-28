import 'dart:async';
import 'package:flutter/material.dart';
import '../core/app_state.dart';
import 'pitch_maqam_analyzer.dart';
import 'quran_audio_service.dart';

/// Interactive Pitch & Maqam Tilawah Analyzer sheet using DTW contour matching.
class PitchMaqamSheet extends StatefulWidget {
  const PitchMaqamSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const PitchMaqamSheet(),
    );
  }

  @override
  State<PitchMaqamSheet> createState() => _PitchMaqamSheetState();
}

class _PitchMaqamSheetState extends State<PitchMaqamSheet> {
  TilawahMaqam _selectedMaqam = TilawahMaqam.bayyati;

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    final c = app.colors;
    final isDark = app.isDarkMode;
    final analyzer = PitchMaqamAnalyzer.instance;
    final result = analyzer.analyzeAgainst(_selectedMaqam);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 22),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        border: Border.all(color: c.border.withValues(alpha: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: c.textSecondary.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0EA5E9)
                          .withValues(alpha: isDark ? 0.2 : 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.show_chart_rounded,
                      color: Color(0xFF0EA5E9),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Pitch & Maqam Analyzer (DTW)',
                          style: TextStyle(
                            fontFamily: 'cairo',
                            fontSize: 15.5,
                            fontWeight: FontWeight.w800,
                            color: c.text,
                          ),
                        ),
                        Text(
                          'Bandingkan kurva nada F0 Anda dengan pola Maqam tilawah',
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
              const SizedBox(height: 14),

              // Maqam selector chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final m in TilawahMaqam.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: Text(
                            PitchMaqamAnalyzer.maqamName(m),
                            style: const TextStyle(
                              fontFamily: 'cairo',
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          selected: _selectedMaqam == m,
                          onSelected: (_) => setState(() => _selectedMaqam = m),
                          selectedColor:
                              const Color(0xFF0EA5E9).withValues(alpha: 0.22),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                PitchMaqamAnalyzer.maqamDescription(_selectedMaqam),
                style: TextStyle(
                  fontFamily: 'cairo',
                  fontSize: 11.5,
                  color: c.textSecondary,
                ),
              ),
              const SizedBox(height: 14),

              // Dual Pitch Contour Graph
              Container(
                height: 170,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: c.bg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: c.border.withValues(alpha: 0.5)),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            _LegendDot(
                              color: const Color(0xFFF59E0B),
                              label: 'Pola ${PitchMaqamAnalyzer.maqamName(_selectedMaqam)}',
                              c: c,
                            ),
                            const SizedBox(width: 12),
                            _LegendDot(
                              color: const Color(0xFF10B981),
                              label: 'Suara Anda',
                              c: c,
                            ),
                          ],
                        ),
                        if (result.userCurve.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981)
                                  .withValues(alpha: isDark ? 0.22 : 0.14),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Kecocokan: ${result.similarityPct}%',
                              style: TextStyle(
                                fontFamily: 'cairo',
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                color: isDark
                                    ? const Color(0xFF34D399)
                                    : const Color(0xFF047857),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: CustomPaint(
                        size: Size.infinite,
                        painter: _PitchContourPainter(
                          referenceCurve: result.referenceCurve,
                          userCurve: result.userCurve,
                          isDark: isDark,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              if (result.userCurve.isEmpty)
                Text(
                  'Belum ada kurva suara. Nyalakan Mic & baca beberapa kata di Mushaf, lalu buka kembali panel ini untuk melihat grafik DTW nada Anda.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'cairo',
                    fontSize: 11.5,
                    color: c.textSecondary,
                  ),
                )
              else
                Text(
                  'Rata-rata F0 suara Anda: ${result.avgHz.round()} Hz (${result.userCurve.length} sampel)',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'cairo',
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: c.textSecondary,
                  ),
                ),

              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        unawaited(QuranAudioService.instance.play(
                          surah: app.lastSurah,
                          ayah: app.lastAyah,
                          continuous: false,
                        ));
                      },
                      icon: const Icon(Icons.volume_up_rounded, size: 18),
                      label: const Text(
                        'Contoh Qari',
                        style: TextStyle(
                          fontFamily: 'cairo',
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0EA5E9),
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () {
                        analyzer.reset();
                        setState(() {});
                      },
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text(
                        'Reset Kurva',
                        style: TextStyle(
                          fontFamily: 'cairo',
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  final ThemeColors c;

  const _LegendDot({
    required this.color,
    required this.label,
    required this.c,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontFamily: 'cairo',
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: c.text,
          ),
        ),
      ],
    );
  }
}

class _PitchContourPainter extends CustomPainter {
  final List<double> referenceCurve;
  final List<double> userCurve;
  final bool isDark;

  _PitchContourPainter({
    required this.referenceCurve,
    required this.userCurve,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Baseline 0-semitone guide
    final gridPaint = Paint()
      ..color = (isDark ? Colors.white : Colors.black).withValues(alpha: 0.10)
      ..strokeWidth = 1.0;
    canvas.drawLine(
      Offset(0, size.height * 0.5),
      Offset(size.width, size.height * 0.5),
      gridPaint,
    );

    _drawCurve(
      canvas,
      size,
      referenceCurve,
      const Color(0xFFF59E0B),
      strokeWidth: 2.2,
    );
    if (userCurve.length >= 2) {
      _drawCurve(
        canvas,
        size,
        userCurve,
        const Color(0xFF10B981),
        strokeWidth: 3.0,
      );
    }
  }

  void _drawCurve(
    Canvas canvas,
    Size size,
    List<double> pts,
    Color color, {
    required double strokeWidth,
  }) {
    if (pts.length < 2) return;
    final path = Path();
    for (int i = 0; i < pts.length; i++) {
      final x = (i / (pts.length - 1)) * size.width;
      // Map -6..+6 semitones to height..0
      final normY = (pts[i].clamp(-6.0, 6.0) + 6.0) / 12.0;
      final y = size.height - (normY * size.height);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _PitchContourPainter oldDelegate) => true;
}
