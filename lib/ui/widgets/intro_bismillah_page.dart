import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../core/app_state.dart';

/// Halaman pembuka (Intro Screen) bergaya ikonik Nokia "Connecting People"
/// yang diadaptasi khusus menjadi:
///
///               "Mi-Qro"
///         "read together  connect"
///
/// Menampilkan animasi dua tangan siluet/vektor elegan yang saling mendekat
/// dari kiri-atas dan kanan-bawah menuju titik temu di tengah (Mushaf bersinar),
/// dengan getaran haptik dan tipografi premium Nokia classic-modern.
class IntroBismillahPage extends StatefulWidget {
  final VoidCallback onFinish;

  const IntroBismillahPage({super.key, required this.onFinish});

  @override
  State<IntroBismillahPage> createState() => _IntroBismillahPageState();
}

class _IntroBismillahPageState extends State<IntroBismillahPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl;

  // Animasi pergerakan dua tangan saling mendekat
  late final Animation<double> _handApproachAnim;

  // Animasi titik temu (sparkle / touch connection)
  late final Animation<double> _sparkleAnim;

  // Animasi pemunculan teks "Mi-Qro" dan "read together  connect"
  late final Animation<double> _textFadeAnim;
  late final Animation<double> _textSlideAnim;

  Timer? _autoDismissTimer;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );

    // 0.0 - 0.55: Kedua tangan bergerak mendekat dari sudut luar
    _handApproachAnim = CurvedAnimation(
      parent: _animCtrl,
      curve: const Interval(0.0, 0.55, curve: Curves.easeOutCubic),
    );

    // 0.50 - 0.75: Cahaya/sparkle mekar saat ujung tangan bertemu
    _sparkleAnim = CurvedAnimation(
      parent: _animCtrl,
      curve: const Interval(0.48, 0.75, curve: Curves.easeOutBack),
    );

    // 0.60 - 1.0: Nama Mi-Qro & slogan "read together  connect" muncul
    _textFadeAnim = CurvedAnimation(
      parent: _animCtrl,
      curve: const Interval(0.60, 0.95, curve: Curves.easeIn),
    );

    _textSlideAnim = Tween<double>(begin: 18.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _animCtrl,
        curve: const Interval(0.60, 0.95, curve: Curves.easeOutCubic),
      ),
    );

    _animCtrl.forward();

    // Otomatis selesai dan masuk ke layar utama setelah animasi selesai
    _autoDismissTimer = Timer(const Duration(milliseconds: 3200), () {
      if (mounted) {
        _dismiss();
      }
    });
  }

  void _dismiss() {
    _autoDismissTimer?.cancel();
    _animCtrl.reverse().then((_) {
      if (mounted) {
        widget.onFinish();
      }
    });
  }

  @override
  void dispose() {
    _autoDismissTimer?.cancel();
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    final isDark = app.isDarkMode;

    // Latar belakang khas Nokia biru gelap atau emerald modern
    final Color bgColor = isDark ? const Color(0xFF030712) : const Color(0xFF0F172A);

    return Scaffold(
      backgroundColor: bgColor,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _dismiss,
        child: AnimatedBuilder(
          animation: _animCtrl,
          builder: (context, _) {
            final double approach = _handApproachAnim.value;
            final double sparkle = _sparkleAnim.value;

            return Stack(
              children: [
                // 1. Ambient Background Glow
                Center(
                  child: Container(
                    width: 340,
                    height: 340,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          const Color(0xFF10B981).withValues(alpha: 0.16 * sparkle),
                          const Color(0xFF38BDF8).withValues(alpha: 0.08 * sparkle),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),

                // 2. Tangan Kiri-Atas (Bergerak dari kiri atas ke tengah)
                Positioned(
                  top: -120 + (120 * approach),
                  left: -120 + (120 * approach),
                  child: Transform.rotate(
                    angle: 0.78, // ~45 derajat
                    child: _buildHandSilhouette(
                      isLeft: true,
                      approach: approach,
                    ),
                  ),
                ),

                // 3. Tangan Kanan-Bawah (Bergerak dari kanan bawah ke tengah)
                Positioned(
                  bottom: -120 + (120 * approach),
                  right: -120 + (120 * approach),
                  child: Transform.rotate(
                    angle: -2.36, // ~-135 derajat berhadapan
                    child: _buildHandSilhouette(
                      isLeft: false,
                      approach: approach,
                    ),
                  ),
                ),

                // 4. Titik Pertemuan Cahaya / Sparkle di Tengah (Connecting Moment)
                Center(
                  child: Opacity(
                    opacity: sparkle.clamp(0.0, 1.0),
                    child: Transform.scale(
                      scale: 0.6 + (0.5 * sparkle),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          // Radiant Ring
                          Container(
                            width: 70,
                            height: 70,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: RadialGradient(
                                colors: [
                                  Colors.white.withValues(alpha: 0.85),
                                  const Color(0xFF34D399).withValues(alpha: 0.6),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                          ),
                          // Small Icon Mushaf di tengah persentuhan
                          const Icon(
                            Icons.auto_stories_rounded,
                            size: 26,
                            color: Colors.white,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // 5. Branding Teks: Mi-Qro & "read together  connect"
                SafeArea(
                  child: Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 64),
                      child: Opacity(
                        opacity: _textFadeAnim.value,
                        child: Transform.translate(
                          offset: Offset(0, _textSlideAnim.value),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Kaligrafi Bismillah Kecil Anggun
                              Text(
                                'بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ',
                                textDirection: TextDirection.rtl,
                                style: TextStyle(
                                  fontFamily: 'HafsSmart',
                                  fontSize: 16,
                                  color: const Color(0xFF34D399).withValues(alpha: 0.9),
                                ),
                              ),
                              const SizedBox(height: 12),

                              // NAMA APP: Mi-Qro
                              RichText(
                                text: const TextSpan(
                                  style: TextStyle(
                                    fontFamily: 'cairo',
                                    fontSize: 38,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 2.2,
                                    color: Colors.white,
                                  ),
                                  children: [
                                    TextSpan(text: 'Mi-'),
                                    TextSpan(
                                      text: 'Qro',
                                      style: TextStyle(
                                        color: Color(0xFF10B981),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 8),

                              // SLOGAN: "read together  connect"
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: const Color(0xFF10B981).withValues(alpha: 0.4),
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'read together',
                                      style: TextStyle(
                                        fontFamily: 'cairo',
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white.withValues(alpha: 0.92),
                                        letterSpacing: 1.2,
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 8),
                                      child: Container(
                                        width: 4,
                                        height: 4,
                                        decoration: const BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: Color(0xFF10B981),
                                        ),
                                      ),
                                    ),
                                    const Text(
                                      'connect',
                                      style: TextStyle(
                                        fontFamily: 'cairo',
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFF34D399),
                                        letterSpacing: 1.4,
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              const SizedBox(height: 28),

                              // Hint Ketuk Layar
                              Text(
                                'Ketuk untuk melanjutkan',
                                style: TextStyle(
                                  fontFamily: 'cairo',
                                  fontSize: 11,
                                  color: Colors.white.withValues(alpha: 0.45),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  /// Custom vector-like hand silhouette rendering
  Widget _buildHandSilhouette({required bool isLeft, required double approach}) {
    return CustomPaint(
      size: const Size(260, 180),
      painter: _NokiaHandPainter(
        color: const Color(0xFF94A3B8).withValues(alpha: 0.85),
        accentColor: const Color(0xFF10B981).withValues(alpha: 0.4),
        isLeft: isLeft,
      ),
    );
  }
}

/// Custom painter yang melukiskan lengan dan jari tangan siluet ikonik Nokia
class _NokiaHandPainter extends CustomPainter {
  final Color color;
  final Color accentColor;
  final bool isLeft;

  _NokiaHandPainter({
    required this.color,
    required this.accentColor,
    required this.isLeft,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill
      ..isAntiAlias = true;

    final glowPaint = Paint()
      ..color = accentColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..isAntiAlias = true;

    final path = Path();

    // Gambar lengan yang menjulur (Arm & Forearm)
    path.moveTo(0, size.height * 0.70);
    path.cubicTo(
      size.width * 0.25,
      size.height * 0.65,
      size.width * 0.45,
      size.height * 0.55,
      size.width * 0.60,
      size.height * 0.48,
    );

    // Pangkal telapak tangan & pergelangan
    path.lineTo(size.width * 0.68, size.height * 0.42);

    // Ibu jari (Thumb) sedikit terbuka ke arah bawah
    path.cubicTo(
      size.width * 0.70,
      size.height * 0.58,
      size.width * 0.76,
      size.height * 0.65,
      size.width * 0.82,
      size.height * 0.62,
    );
    path.cubicTo(
      size.width * 0.85,
      size.height * 0.56,
      size.width * 0.78,
      size.height * 0.46,
      size.width * 0.75,
      size.height * 0.40,
    );

    // Jari Telunjuk yang menjangkau ke depan (Index finger reaching out)
    path.lineTo(size.width * 0.94, size.height * 0.32);
    path.cubicTo(
      size.width * 0.98,
      size.height * 0.30,
      size.width * 0.98,
      size.height * 0.24,
      size.width * 0.93,
      size.height * 0.23,
    );
    path.lineTo(size.width * 0.76, size.height * 0.28);

    // Jari Tengah & Manis melengkung santai
    path.lineTo(size.width * 0.72, size.height * 0.22);
    path.cubicTo(
      size.width * 0.65,
      size.height * 0.18,
      size.width * 0.55,
      size.height * 0.26,
      size.width * 0.48,
      size.height * 0.35,
    );

    // Kembali ke batas lengan atas
    path.lineTo(0, size.height * 0.38);
    path.close();

    canvas.drawPath(path, paint);
    canvas.drawPath(path, glowPaint);
  }

  @override
  bool shouldRepaint(covariant _NokiaHandPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.isLeft != isLeft;
}
