import 'package:flutter/material.dart';
import '../core/app_state.dart';
import 'iqro_audio_service.dart';

enum MakhrajZone {
  halqDeep,    // Pangkal tenggorokan (ء هـ)
  halqMid,     // Tengah tenggorokan (ع ح)
  halqTop,     // Ujung tenggorokan (غ خ)
  lisanBack,   // Pangkal lidah (ق ك)
  lisanMid,    // Tengah lidah (ج ش ي)
  lisanSide,   // Tepi lidah (ض)
  lisanTip,    // Ujung lidah (ل ن ر ط د ت ص ز س ظ ذ ث)
  syafatan,    // Dua bibir (ف و ب م)
}

class MakhrajInfo {
  final String letter;
  final String name;
  final MakhrajZone zone;
  final String titleId;
  final String titleEn;
  final String descId;
  final String descEn;
  /// Normalized articulation point on the vocal tract canvas (0..1, 0..1)
  final Offset point;

  const MakhrajInfo({
    required this.letter,
    required this.name,
    required this.zone,
    required this.titleId,
    required this.titleEn,
    required this.descId,
    required this.descEn,
    required this.point,
  });
}

/// Interactive animated Makharijul Huruf vocal-tract visualizer.
/// Pure UI component — zero impact on Sherpa-ONNX AI detection.
class MakhrajVisualizer extends StatefulWidget {
  final String arabicText;

  const MakhrajVisualizer({super.key, required this.arabicText});

  @override
  State<MakhrajVisualizer> createState() => _MakhrajVisualizerState();
}

class _MakhrajVisualizerState extends State<MakhrajVisualizer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late List<MakhrajInfo> _letters;
  int _selectedIdx = 0;

  static const Map<int, MakhrajInfo> _catalog = {
    0x0627: MakhrajInfo(
      letter: 'ا',
      name: 'Alif / Hamzah',
      zone: MakhrajZone.halqDeep,
      titleId: 'Pangkal Tenggorokan (Al-Halq)',
      titleEn: 'Deep Throat (Al-Halq)',
      descId: 'Keluar dari pangkal tenggorokan paling bawah dengan rongga mulut terbuka.',
      descEn: 'Produced from the lowest part of the throat with an open mouth.',
      point: Offset(0.32, 0.78),
    ),
    0x0628: MakhrajInfo(
      letter: 'ب',
      name: 'Ba',
      zone: MakhrajZone.syafatan,
      titleId: 'Dua Bibir (Asy-Syafatan)',
      titleEn: 'Both Lips (Asy-Syafatan)',
      descId: 'Merapatkan bibir atas dan bawah secara kuat lalu dilepas.',
      descEn: 'Pressing the upper and lower lips firmly together and releasing.',
      point: Offset(0.84, 0.44),
    ),
    0x062A: MakhrajInfo(
      letter: 'ت',
      name: 'Ta',
      zone: MakhrajZone.lisanTip,
      titleId: 'Ujung Lidah & Pangkal Gigi Seri Atas',
      titleEn: 'Tongue Tip & Upper Gum Line',
      descId: 'Ujung lidah menempel pada pangkal gigi seri bagian atas dengan hembusan halus.',
      descEn: 'Tongue tip touches the gum ridge behind the upper front teeth.',
      point: Offset(0.76, 0.36),
    ),
    0x062B: MakhrajInfo(
      letter: 'ث',
      name: 'Tsa',
      zone: MakhrajZone.lisanTip,
      titleId: 'Ujung Lidah & Ujung Gigi Seri Atas',
      titleEn: 'Tongue Tip & Upper Teeth Edge',
      descId: 'Ujung lidah menyentuh ringan ujung gigi seri atas dengan aliran udara lembut.',
      descEn: 'Tongue tip lightly touches the edge of the upper front teeth.',
      point: Offset(0.80, 0.40),
    ),
    0x062C: MakhrajInfo(
      letter: 'ج',
      name: 'Jim',
      zone: MakhrajZone.lisanMid,
      titleId: 'Tengah Lidah & Langit-Langit',
      titleEn: 'Middle Tongue & Hard Palate',
      descId: 'Tengah lidah diangkat menempel ke langit-langit atas bagian tengah.',
      descEn: 'Middle of the tongue presses against the middle of the hard palate.',
      point: Offset(0.55, 0.30),
    ),
    0x062D: MakhrajInfo(
      letter: 'ح',
      name: 'Ha (Pedas)',
      zone: MakhrajZone.halqMid,
      titleId: 'Tengah Tenggorokan (Al-Halq)',
      titleEn: 'Middle Throat (Al-Halq)',
      descId: 'Udara mengalir bersih melalui penyempitan tengah tenggorokan tanpa serak.',
      descEn: 'Clean airflow through the constricted middle throat without raspiness.',
      point: Offset(0.32, 0.62),
    ),
    0x062E: MakhrajInfo(
      letter: 'خ',
      name: 'Kho',
      zone: MakhrajZone.halqTop,
      titleId: 'Ujung Tenggorokan (Adnal Halq)',
      titleEn: 'Upper Throat (Adnal Halq)',
      descId: 'Keluar dari tenggorokan bagian atas dekat pangkal lidah dengan getaran halus.',
      descEn: 'Upper throat near the root of the tongue with gentle friction.',
      point: Offset(0.35, 0.48),
    ),
    0x062F: MakhrajInfo(
      letter: 'د',
      name: 'Dal',
      zone: MakhrajZone.lisanTip,
      titleId: 'Ujung Lidah & Pangkal Gigi Seri Atas',
      titleEn: 'Tongue Tip & Upper Gum Line',
      descId: 'Ujung lidah menempel mantap pada pangkal gigi seri atas.',
      descEn: 'Tongue tip presses firmly against the base of the upper front teeth.',
      point: Offset(0.75, 0.36),
    ),
    0x0630: MakhrajInfo(
      letter: 'ذ',
      name: 'Dzal',
      zone: MakhrajZone.lisanTip,
      titleId: 'Ujung Lidah & Ujung Gigi Seri Atas',
      titleEn: 'Tongue Tip & Upper Teeth Edge',
      descId: 'Ujung lidah menyentuh ujung gigi seri atas disertai suara bergetar.',
      descEn: 'Tongue tip touches the edge of the upper front teeth with voice.',
      point: Offset(0.80, 0.40),
    ),
    0x0631: MakhrajInfo(
      letter: 'ر',
      name: 'Ro',
      zone: MakhrajZone.lisanTip,
      titleId: 'Punggung Ujung Lidah & Langit Depan',
      titleEn: 'Tongue Tip Back & Front Palate',
      descId: 'Ujung lidah melengkung menyentuh langit-langit depan tepat di belakang gusi.',
      descEn: 'Curved tongue tip taps the front palate just behind the upper gums.',
      point: Offset(0.72, 0.33),
    ),
    0x0632: MakhrajInfo(
      letter: 'ز',
      name: 'Zai',
      zone: MakhrajZone.lisanTip,
      titleId: 'Ujung Lidah & Gigi Seri Bawah',
      titleEn: 'Tongue Tip & Lower Front Teeth',
      descId: 'Ujung lidah dekat gigi seri bawah menghasilkan desisan bergetar.',
      descEn: 'Tongue tip near the lower front teeth producing a voiced buzz.',
      point: Offset(0.78, 0.44),
    ),
    0x0633: MakhrajInfo(
      letter: 'س',
      name: 'Sin',
      zone: MakhrajZone.lisanTip,
      titleId: 'Ujung Lidah & Gigi Seri Bawah (Shafir)',
      titleEn: 'Tongue Tip & Lower Teeth (Whistle)',
      descId: 'Aliran udara berdesis tipis melewati celah ujung lidah dan gigi seri.',
      descEn: 'Crisp sibilant airflow between the tongue tip and front teeth.',
      point: Offset(0.78, 0.44),
    ),
    0x0634: MakhrajInfo(
      letter: 'ش',
      name: 'Syin',
      zone: MakhrajZone.lisanMid,
      titleId: 'Tengah Lidah (Tafasyi)',
      titleEn: 'Middle Tongue (Spread Air)',
      descId: 'Udara menyebar luas di antara tengah lidah dan langit-langit.',
      descEn: 'Air spreads broadly between the middle tongue and the palate.',
      point: Offset(0.56, 0.31),
    ),
    0x0635: MakhrajInfo(
      letter: 'ص',
      name: 'Shod',
      zone: MakhrajZone.lisanTip,
      titleId: 'Ujung Lidah & Pangkal Lidah Terangkat (Tebal)',
      titleEn: 'Tongue Tip + Raised Back (Emphatic)',
      descId: 'Ujung lidah di gigi seri bawah sambil mengangkat pangkal lidah (suara tebal).',
      descEn: 'Tongue tip at lower teeth while raising the back of the tongue.',
      point: Offset(0.76, 0.44),
    ),
    0x0636: MakhrajInfo(
      letter: 'ض',
      name: 'Dhod',
      zone: MakhrajZone.lisanSide,
      titleId: 'Tepi Lidah & Gigi Geraham Atas',
      titleEn: 'Side of Tongue & Upper Molars',
      descId: 'Salah satu atau kedua tepi lidah menekan gigi geraham atas.',
      descEn: 'One or both sides of the tongue press against the upper molars.',
      point: Offset(0.52, 0.42),
    ),
    0x0637: MakhrajInfo(
      letter: 'ط',
      name: 'Tho',
      zone: MakhrajZone.lisanTip,
      titleId: 'Ujung Lidah & Pangkal Gigi Atas (Tebal)',
      titleEn: 'Tongue Tip & Upper Gums (Emphatic)',
      descId: 'Ujung lidah di pangkal gigi atas dengan pangkal lidah terangkat kuat.',
      descEn: 'Tongue tip on upper gum ridge with strong back-tongue elevation.',
      point: Offset(0.74, 0.35),
    ),
    0x0638: MakhrajInfo(
      letter: 'ظ',
      name: 'Zho',
      zone: MakhrajZone.lisanTip,
      titleId: 'Ujung Lidah & Ujung Gigi Atas (Tebal)',
      titleEn: 'Tongue Tip & Upper Teeth Edge (Emphatic)',
      descId: 'Ujung lidah di ujung gigi seri atas sambil menebalkan suara.',
      descEn: 'Tongue tip at upper teeth edge with emphatic raised back tongue.',
      point: Offset(0.79, 0.40),
    ),
    0x0639: MakhrajInfo(
      letter: 'ع',
      name: "'Ain",
      zone: MakhrajZone.halqMid,
      titleId: 'Tengah Tenggorokan (Wasathul Halq)',
      titleEn: 'Middle Throat (Wasathul Halq)',
      descId: 'Menekan katup tengah tenggorokan sehingga suara terdengar bulat dan dalam.',
      descEn: 'Constricting the middle throat for a deep, resonant pharyngeal sound.',
      point: Offset(0.32, 0.62),
    ),
    0x063A: MakhrajInfo(
      letter: 'غ',
      name: 'Ghoin',
      zone: MakhrajZone.halqTop,
      titleId: 'Ujung Tenggorokan (Adnal Halq)',
      titleEn: 'Upper Throat (Adnal Halq)',
      descId: 'Dari tenggorokan bagian atas dengan suara bergetar halus dan tebal.',
      descEn: 'From the upper throat with a smooth voiced uvular vibration.',
      point: Offset(0.35, 0.48),
    ),
    0x0641: MakhrajInfo(
      letter: 'ف',
      name: 'Fa',
      zone: MakhrajZone.syafatan,
      titleId: 'Bibir Bawah & Ujung Gigi Seri Atas',
      titleEn: 'Lower Lip & Upper Front Teeth',
      descId: 'Ujung gigi seri atas menyentuh bagian dalam bibir bawah.',
      descEn: 'Upper front teeth gently touch the inner edge of the lower lip.',
      point: Offset(0.83, 0.46),
    ),
    0x0642: MakhrajInfo(
      letter: 'ق',
      name: 'Qof',
      zone: MakhrajZone.lisanBack,
      titleId: 'Pangkal Lidah & Langit-Langit Lunak',
      titleEn: 'Back of Tongue & Soft Palate',
      descId: 'Pangkal lidah paling belakang menempel pada langit-langit lunak (uvula).',
      descEn: 'Deepest back of the tongue touches the soft palate (uvula).',
      point: Offset(0.39, 0.36),
    ),
    0x0643: MakhrajInfo(
      letter: 'ك',
      name: 'Kaf',
      zone: MakhrajZone.lisanBack,
      titleId: 'Pangkal Lidah & Langit-Langit Keras',
      titleEn: 'Back of Tongue & Hard Palate',
      descId: 'Sedikit lebih ke depan dari Qof, menempel di batas langit-langit keras.',
      descEn: 'Slightly forward from Qof, touching the hard-soft palate border.',
      point: Offset(0.45, 0.34),
    ),
    0x0644: MakhrajInfo(
      letter: 'ل',
      name: 'Lam',
      zone: MakhrajZone.lisanTip,
      titleId: 'Tepi Ujung Lidah & Gusi Atas',
      titleEn: 'Front Edge of Tongue & Upper Gums',
      descId: 'Ujung tepi lidah menyentuh lengkung gusi bagian atas.',
      descEn: 'Front edge of the tongue touches the upper gum arch.',
      point: Offset(0.71, 0.34),
    ),
    0x0645: MakhrajInfo(
      letter: 'م',
      name: 'Mim',
      zone: MakhrajZone.syafatan,
      titleId: 'Dua Bibir & Rongga Hidung',
      titleEn: 'Both Lips & Nasal Passage',
      descId: 'Merapatkan kedua bibir dengan suara berdengung ringan melalui hidung.',
      descEn: 'Closing both lips gently with light nasal resonance.',
      point: Offset(0.84, 0.44),
    ),
    0x0646: MakhrajInfo(
      letter: 'ن',
      name: 'Nun',
      zone: MakhrajZone.lisanTip,
      titleId: 'Ujung Lidah & Gusi Atas + Hidung',
      titleEn: 'Tongue Tip & Upper Gums + Nasal',
      descId: 'Ujung lidah menempel pada gusi atas disertai dengung lembut di hidung.',
      descEn: 'Tongue tip touches upper gums with gentle nasal resonance.',
      point: Offset(0.73, 0.35),
    ),
    0x0647: MakhrajInfo(
      letter: 'ه',
      name: 'Ha (Besar)',
      zone: MakhrajZone.halqDeep,
      titleId: 'Pangkal Tenggorokan (Aqshal Halq)',
      titleEn: 'Deep Throat (Aqshal Halq)',
      descId: 'Udara berhembus ringan dari pangkal tenggorokan bagian dada.',
      descEn: 'Soft breathy airflow from the deepest part of the throat.',
      point: Offset(0.32, 0.78),
    ),
    0x0648: MakhrajInfo(
      letter: 'و',
      name: 'Waw',
      zone: MakhrajZone.syafatan,
      titleId: 'Dua Bibir Memonyong',
      titleEn: 'Rounded Both Lips',
      descId: 'Membulatkan kedua bibir ke depan tanpa menutup rapat.',
      descEn: 'Rounding both lips forward leaving a small central opening.',
      point: Offset(0.86, 0.44),
    ),
    0x064A: MakhrajInfo(
      letter: 'ي',
      name: 'Ya',
      zone: MakhrajZone.lisanMid,
      titleId: 'Tengah Lidah & Langit-Langit',
      titleEn: 'Middle Tongue & Palate',
      descId: 'Mengangkat tengah lidah mendekati langit-langit tanpa menyentuh rapat.',
      descEn: 'Raising the middle tongue toward the palate without full closure.',
      point: Offset(0.56, 0.32),
    ),
  };

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _letters = _extractLetters(widget.arabicText);
  }

  @override
  void didUpdateWidget(covariant MakhrajVisualizer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.arabicText != widget.arabicText) {
      _letters = _extractLetters(widget.arabicText);
      _selectedIdx = 0;
    }
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  static List<MakhrajInfo> _extractLetters(String text) {
    final List<MakhrajInfo> result = [];
    final Set<int> seen = {};
    for (final rune in text.runes) {
      int normalized = rune;
      if (rune == 0x0622 || rune == 0x0623 || rune == 0x0625 || rune == 0x0671 || rune == 0x0621) {
        normalized = 0x0627;
      } else if (rune == 0x0629) {
        normalized = 0x062A;
      } else if (rune == 0x0649 || rune == 0x0626) {
        normalized = 0x064A;
      } else if (rune == 0x0624) {
        normalized = 0x0648;
      }
      final info = _catalog[normalized];
      if (info != null && seen.add(normalized)) {
        result.add(info);
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    if (_letters.isEmpty) return const SizedBox.shrink();
    final app = AppState.instance;
    final c = app.colors;
    final isDark = app.isDarkMode;
    final isId = app.isIndonesian;
    final active = _letters[_selectedIdx.clamp(0, _letters.length - 1)];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.border.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.record_voice_over_rounded,
                size: 16,
                color: Color(0xFF10B981),
              ),
              const SizedBox(width: 6),
              Text(
                isId ? 'Visualisasi Makharijul Huruf' : 'Makhraj Articulation Map',
                style: TextStyle(
                  fontFamily: 'cairo',
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: c.text,
                ),
              ),
            ],
          ),
          if (_letters.length > 1) ...[
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (int i = 0; i < _letters.length; i++)
                    GestureDetector(
                      onTap: () {
                        setState(() => _selectedIdx = i);
                        IqroAudioService.instance.speakArabic(
                          '${_letters[i].letter}\u064e',
                        );
                      },
                      child: Container(
                        margin: const EdgeInsets.only(right: 6),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _selectedIdx == i
                              ? const Color(0xFF10B981)
                              : c.surface,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _selectedIdx == i
                                ? const Color(0xFF10B981)
                                : c.border.withValues(alpha: 0.5),
                          ),
                        ),
                        child: Text(
                          '${_letters[i].letter}  ${_letters[i].name}',
                          style: TextStyle(
                            fontFamily: 'cairo',
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color:
                                _selectedIdx == i ? Colors.white : c.text,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              // Animated vocal tract diagram
              Container(
                width: 112,
                height: 96,
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF0F172A)
                      : const Color(0xFFF1F5F9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: c.border.withValues(alpha: 0.4)),
                ),
                child: AnimatedBuilder(
                  animation: _pulseCtrl,
                  builder: (context, _) {
                    return CustomPaint(
                      painter: _VocalTractPainter(
                        point: active.point,
                        pulse: _pulseCtrl.value,
                        isDark: isDark,
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${active.letter} (${active.name})',
                      style: TextStyle(
                        fontFamily: 'cairo',
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                        color: const Color(0xFF10B981),
                      ),
                    ),
                    Text(
                      isId ? active.titleId : active.titleEn,
                      style: TextStyle(
                        fontFamily: 'cairo',
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: c.text,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      isId ? active.descId : active.descEn,
                      style: TextStyle(
                        fontFamily: 'cairo',
                        fontSize: 11,
                        height: 1.35,
                        color: c.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _VocalTractPainter extends CustomPainter {
  final Offset point;
  final double pulse;
  final bool isDark;

  _VocalTractPainter({
    required this.point,
    required this.pulse,
    required this.isDark,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final outlinePaint = Paint()
      ..color = isDark
          ? Colors.white.withValues(alpha: 0.28)
          : const Color(0xFF475569).withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    // Stylized side-profile vocal tract: palate roof, lips, tongue & throat
    final tractPath = Path()
      ..moveTo(w * 0.85, h * 0.36) // Upper lip
      ..quadraticBezierTo(w * 0.65, h * 0.22, w * 0.42, h * 0.28) // Palate
      ..quadraticBezierTo(w * 0.26, h * 0.35, w * 0.26, h * 0.86); // Back throat
    canvas.drawPath(tractPath, outlinePaint);

    // Lower jaw + tongue contour
    final tonguePaint = Paint()
      ..color = const Color(0xFFF43F5E).withValues(alpha: isDark ? 0.35 : 0.22)
      ..style = PaintingStyle.fill;
    final tonguePath = Path()
      ..moveTo(w * 0.38, h * 0.86)
      ..lineTo(w * 0.38, h * 0.56)
      ..quadraticBezierTo(w * 0.54, h * 0.38, w * 0.78, h * 0.44)
      ..quadraticBezierTo(w * 0.68, h * 0.62, w * 0.38, h * 0.86)
      ..close();
    canvas.drawPath(tonguePath, tonguePaint);
    canvas.drawPath(tonguePath, outlinePaint);

    // Lower lip
    canvas.drawLine(
      Offset(w * 0.82, h * 0.50),
      Offset(w * 0.88, h * 0.50),
      outlinePaint,
    );

    // Pulsing articulation point
    final center = Offset(w * point.dx, h * point.dy);
    final haloRadius = 7.0 + (pulse * 7.0);
    canvas.drawCircle(
      center,
      haloRadius,
      Paint()
        ..color = const Color(0xFF10B981).withValues(alpha: 0.35 * (1 - pulse * 0.5)),
    );
    canvas.drawCircle(
      center,
      4.5,
      Paint()..color = const Color(0xFF10B981),
    );
  }

  @override
  bool shouldRepaint(covariant _VocalTractPainter oldDelegate) =>
      oldDelegate.point != point ||
      oldDelegate.pulse != pulse ||
      oldDelegate.isDark != isDark;
}
