import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/app_state.dart';

/// Halaman pembuka (Intro / Splash Page) dengan kaligrafi Bismillah
/// dalam rasm Utsmani Al-Qur'an yang anggun, transisi halus, dan branding "ngabar".
class IntroBismillahPage extends StatefulWidget {
  final VoidCallback onFinish;

  const IntroBismillahPage({super.key, required this.onFinish});

  @override
  State<IntroBismillahPage> createState() => _IntroBismillahPageState();
}

class _IntroBismillahPageState extends State<IntroBismillahPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl;
  late final Animation<double> _fadeAnim;
  late final Animation<double> _scaleAnim;
  Timer? _autoDismissTimer;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );

    _fadeAnim = CurvedAnimation(
      parent: _animCtrl,
      curve: Curves.easeOutCubic,
    );

    _scaleAnim = Tween<double>(begin: 0.94, end: 1.0).animate(
      CurvedAnimation(
        parent: _animCtrl,
        curve: Curves.easeOutBack,
      ),
    );

    _animCtrl.forward();

    // Otomatis masuk ke aplikasi setelah 2.8 detik jika tidak disentuh
    _autoDismissTimer = Timer(const Duration(milliseconds: 2800), () {
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
    final isId = app.isIndonesian;

    const emeraldPrimary = Color(0xFF10B981);
    const goldAccent = Color(0xFFD4AF37);

    final bgColor = isDark ? const Color(0xFF090D16) : const Color(0xFFF8FAFC);
    final cardBg = isDark
        ? const Color(0xFF111827).withValues(alpha: 0.90)
        : Colors.white.withValues(alpha: 0.95);
    final textColor = isDark ? Colors.white : const Color(0xFF0F172A);
    final subTextColor = isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

    return Material(
      color: bgColor,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _dismiss,
        child: FadeTransition(
          opacity: _fadeAnim,
          child: ScaleTransition(
            scale: _scaleAnim,
            child: Stack(
              children: [
                // Ornamen Latar Belakang Lingkaran Halus
                Positioned(
                  top: -100,
                  right: -100,
                  child: Container(
                    width: 320,
                    height: 320,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          emeraldPrimary.withValues(alpha: isDark ? 0.18 : 0.12),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  bottom: -120,
                  left: -80,
                  child: Container(
                    width: 300,
                    height: 300,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          goldAccent.withValues(alpha: isDark ? 0.12 : 0.08),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),
                ),

                // Konten Utama
                SafeArea(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Spacer(flex: 3),

                          // Logo / Nama Aplikasi "ngabar"
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 6),
                            decoration: BoxDecoration(
                              color: emeraldPrimary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: emeraldPrimary.withValues(alpha: 0.35),
                                width: 1.2,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(
                                  Icons.menu_book_rounded,
                                  size: 18,
                                  color: emeraldPrimary,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'ngabar',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: 2.0,
                                    color: isDark ? Colors.white : emeraldPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 32),

                          // Kartu Mewah Kaligrafi Bismillah dalam Bahasa Al-Qur'an
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 24, vertical: 32),
                            decoration: BoxDecoration(
                              color: cardBg,
                              borderRadius: BorderRadius.circular(28),
                              border: Border.all(
                                color: emeraldPrimary.withValues(alpha: 0.25),
                                width: 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: emeraldPrimary.withValues(
                                      alpha: isDark ? 0.20 : 0.08),
                                  blurRadius: 28,
                                  offset: const Offset(0, 10),
                                ),
                              ],
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // Hiasan Atas
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(
                                      width: 32,
                                      height: 1.5,
                                      color: goldAccent.withValues(alpha: 0.6),
                                    ),
                                    const Padding(
                                      padding:
                                          EdgeInsets.symmetric(horizontal: 8),
                                      child: Icon(
                                        Icons.star_rounded,
                                        size: 14,
                                        color: goldAccent,
                                      ),
                                    ),
                                    Container(
                                      width: 32,
                                      height: 1.5,
                                      color: goldAccent.withValues(alpha: 0.6),
                                    ),
                                  ],
                                ),

                                const SizedBox(height: 22),

                                // BISMILLAH DALAM RASM AL-QUR'AN
                                const FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    'بِسْمِ ٱللَّهِ ٱلرَّحْمَٰنِ ٱلرَّحِيمِ',
                                    textAlign: TextAlign.center,
                                    textDirection: TextDirection.rtl,
                                    style: TextStyle(
                                      fontFamily: 'HafsSmart',
                                      fontSize: 32,
                                      fontWeight: FontWeight.bold,
                                      height: 1.6,
                                      color: Color(0xFF10B981),
                                      letterSpacing: 0.5,
                                    ),
                                  ),
                                ),

                                const SizedBox(height: 18),

                                // Terjemahan Bismillah
                                Text(
                                  isId
                                      ? 'Dengan menyebut nama Allah Yang Maha Pengasih lagi Maha Penyayang'
                                      : 'In the name of Allah, the Entirely Merciful, the Especially Merciful',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    fontStyle: FontStyle.italic,
                                    color: subTextColor,
                                    height: 1.4,
                                  ),
                                ),

                                const SizedBox(height: 18),

                                // Hiasan Bawah
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Container(
                                      width: 32,
                                      height: 1.5,
                                      color: goldAccent.withValues(alpha: 0.6),
                                    ),
                                    const Padding(
                                      padding:
                                          EdgeInsets.symmetric(horizontal: 8),
                                      child: Icon(
                                        Icons.star_rounded,
                                        size: 14,
                                        color: goldAccent,
                                      ),
                                    ),
                                    Container(
                                      width: 32,
                                      height: 1.5,
                                      color: goldAccent.withValues(alpha: 0.6),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 24),

                          // Deskripsi Ringkas
                          Text(
                            isId
                                ? 'Aplikasi Pelacak Tilawah & Tajwid Al-Qur\'an'
                                : 'Real-Time Quran Recitation & Tajweed Tracker',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: textColor.withValues(alpha: 0.85),
                            ),
                          ),

                          const Spacer(flex: 3),

                          // Tombol Masuk / Buka Al-Qur'an
                          SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: emeraldPrimary,
                                foregroundColor: Colors.white,
                                elevation: 4,
                                shadowColor:
                                    emeraldPrimary.withValues(alpha: 0.4),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                ),
                              ),
                              onPressed: _dismiss,
                              icon: const Icon(Icons.arrow_forward_rounded,
                                  size: 20),
                              label: Text(
                                isId
                                    ? 'Mulai Membaca Al-Qur\'an'
                                    : 'Start Reading Quran',
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 12),

                          // Keterangan Ketuk di Mana Saja
                          Text(
                            isId
                                ? 'Ketuk layar untuk langsung masuk'
                                : 'Tap anywhere to enter',
                            style: TextStyle(
                              fontSize: 12,
                              color: subTextColor.withValues(alpha: 0.8),
                            ),
                          ),

                          const Spacer(flex: 1),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
