import 'package:flutter/material.dart';
import '../../../core/app_state.dart';
import 'dialog_base.dart';

/// Modal dialog for user donations and supporting app development via QRIS.
class DonationDialog extends StatelessWidget {
  const DonationDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierColor: DialogTokens.barrierColor,
      barrierDismissible: true,
      builder: (context) => const DonationDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    final isDark = app.isDarkMode;
    final c = app.colors;

    return AppDialog(
      maxWidth: 420.0,
      scrollable: true,
      heroIcon: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: const Color(0xFF10B981).withValues(alpha: isDark ? 0.20 : 0.12),
          shape: BoxShape.circle,
          border: Border.all(
            color: const Color(0xFF10B981).withValues(alpha: isDark ? 0.45 : 0.30),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF10B981).withValues(alpha: isDark ? 0.25 : 0.15),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Center(
          child: Icon(
            Icons.volunteer_activism_rounded,
            color: Color(0xFF10B981),
            size: 32,
          ),
        ),
      ),
      title: 'Dukung Pengembangan Aplikasi',
      subtitle: 'Infaq & Sedekah Pengembangan Fitur Al-Qur’an & AI Tajwid',
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Penjelasan Aplikasi & Donasi ──
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.04)
                  : Colors.black.withValues(alpha: 0.025),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.06),
              ),
            ),
            child: Text(
              'Aplikasi ini dikembangkan agar proses belajar dan membaca Al-Qur’an semakin nyaman, akurat, dan mudah diakses siapa saja. Dukungan Anda melalui QRIS bersifat sepenuhnya sukarela dan membantu kami pengembangan, maintenance, menyempurnakan fitur tajwid, pembaruan model AI untuk menghadirkan pembaruan yang lebih baik.',
              textAlign: TextAlign.justify,
              style: TextStyle(
                color: c.textSecondary,
                fontSize: 13.5,
                height: 1.55,
                letterSpacing: 0.1,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── QRIS Image Card ──
          Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 290),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.10),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  ),
                ],
                border: Border.all(
                  color: const Color(0xFFE2E8F0),
                  width: 1.2,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: Image.asset(
                        'assets/qris.png',
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            height: 240,
                            alignment: Alignment.center,
                            child: const Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.qr_code_2_rounded, size: 48, color: Colors.grey),
                                SizedBox(height: 8),
                                Text(
                                  'Gambar QRIS sedang dimuat',
                                  style: TextStyle(color: Colors.grey, fontSize: 12),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    color: const Color(0xFFF8FAFC),
                    child: const Text(
                      'Bisa di-scan dengan semua aplikasi Mobile Banking & E-Wallet (BCA, Mandiri, BRI, BSI, GoPay, OVO, Dana, ShopeePay, dll)',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // ── Kutipan Hadits HR. Muslim ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: isDark ? 0.10 : 0.06),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFF10B981).withValues(alpha: isDark ? 0.25 : 0.18),
                width: 1,
              ),
            ),
            child: Column(
              children: [
                const Icon(
                  Icons.format_quote_rounded,
                  color: Color(0xFF10B981),
                  size: 26,
                ),
                const SizedBox(height: 4),
                Text(
                  '“Jika seorang manusia meninggal dunia, maka terputuslah amalannya kecuali dari tiga perkara: sedekah jariyah, ilmu yang diambil manfaatnya, atau anak saleh yang mendoakannya.”',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isDark ? const Color(0xFFD1FAE5) : const Color(0xFF065F46),
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                    height: 1.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '— HR. Muslim',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isDark ? const Color(0xFF6EE7B7) : const Color(0xFF047857),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // ── Penutup / Doa ──
          Center(
            child: Text(
              'Jazakumullahu khairan atas doa dan dukungannya',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: c.primary,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.1,
              ),
            ),
          ),
        ],
      ),
      primaryAction: AppDialogActionItem(
        label: 'Tutup',
        onPressed: () => Navigator.of(context).pop(),
      ),
    );
  }
}
