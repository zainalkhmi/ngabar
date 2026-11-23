import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/app_state.dart';
import 'dialog_base.dart';

// ══════════════════════════════════════════════════════════════════════════════
// 1. APP GUIDE & HOW-TO DIALOG
// ══════════════════════════════════════════════════════════════════════════════

/// Ultra-lightweight user guide explaining:
/// 1. Voice recitation with mic & word status colors.
/// 2. Hifz / Hide Verse Mode (revealing words on recitation).
/// 3. Audio recitation & word pronunciation.
/// 4. Voice search inside Surah list.
/// 5. Quran Maglis live peer rooms.
class AppGuideDialog extends StatelessWidget {
  const AppGuideDialog({super.key});

  /// Displays the AppGuideDialog modal centered with zero eye strain.
  static Future<void> show(BuildContext context) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: DialogTokens.barrierColor,
      builder: (_) => const AppGuideDialog(),
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_seen_app_guide_v1', true);
    await prefs.setBool('has_seen_v1_2_maglis_whats_new', true);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    final c = app.colors;
    final isId = app.isIndonesian;
    final isDark = app.isDarkMode;

    final divider = Padding(
      padding: const EdgeInsets.symmetric(vertical: 5.5),
      child: Divider(
        height: 1,
        thickness: 0.7,
        color: c.border.withValues(alpha: isDark ? 0.16 : 0.22),
      ),
    );

    return AppDialog(
      maxWidth: 395,
      scrollable: true,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      topTrailing: IconButton(
        onPressed: () => Navigator.of(context).pop(),
        icon: Icon(Icons.close_rounded, color: c.muted, size: 20),
        visualDensity: VisualDensity.compact,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
      ),
      content: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: c.surfaceHigh.withValues(alpha: isDark ? 0.35 : 0.55),
          borderRadius: BorderRadius.circular(DialogTokens.cardRadius),
          border: Border.fromBorderSide(DialogTokens.borderSide(c, isDark)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          children: [
            // 1. Voice Recitation & Colors
            _buildRow(
              icon: Icons.mic_rounded,
              iconColor: c.primary,
              title: isId ? 'Pelacakan Tilawah AI' : 'Voice Recitation',
              c: c,
              extra: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isId
                        ? 'Tekan tombol mikrofon di bawah dan mulailah membaca Al-Qur’an.'
                        : 'Tap the bottom Mic button and start reciting aloud.',
                    style: TextStyle(color: c.textSecondary, fontSize: 11.5, height: 1.35),
                  ),
                  const SizedBox(height: 5),
                  Wrap(
                    spacing: 5,
                    runSpacing: 4,
                    children: [
                      _buildChip(c.green, isId ? 'Hijau: Benar' : 'Green: Correct', c, isDark),
                      _buildChip(c.warning, isId ? 'Kuning: Tajwid (tekan untuk detail)' : 'Yellow: Tajweed (tap to view)', c, isDark),
                      _buildChip(c.red, isId ? 'Merah: Kurang tepat' : 'Red: Error', c, isDark),
                    ],
                  ),
                ],
              ),
            ),
            divider,

            // 2. Hifz / Hide Verse Mode
            _buildRow(
              icon: Icons.visibility_off_rounded,
              iconColor: const Color(0xFF6366F1),
              title: isId ? 'Mode Hafalan (Sembunyikan Ayat)' : 'Hifz Mode (Hide Verses)',
              text: isId
                  ? 'Tekan ikon mata untuk menyembunyikan teks ayat; kata akan terbuka otomatis saat dibaca dengan benar.'
                  : 'Tap the Eye icon to hide words; they reveal as you recite correctly.',
              c: c,
            ),
            divider,

            // 3. Audio Recitation
            _buildRow(
              icon: Icons.play_circle_fill_rounded,
              iconColor: isDark ? c.gold : const Color(0xFFD97706),
              title: isId ? 'Putar Audio Murottal' : 'Audio Playback',
              text: isId
                  ? 'Tekan nomor ayat untuk mendengar qari, atau tekan kata untuk mendengar pelafalannya.'
                  : 'Tap Ayah number to hear recitation, or tap any word to hear pronunciation.',
              c: c,
            ),
            divider,

            // 4. Voice Search
            _buildRow(
              icon: Icons.graphic_eq_rounded,
              iconColor: const Color(0xFF10B981),
              title: isId ? 'Pencarian Suara' : 'Voice Search',
              text: isId
                  ? 'Cari ayat dalam daftar surat secara instan hanya dengan melafalkannya.'
                  : 'Recite any verse inside the Surah list to jump to it instantly.',
              c: c,
            ),
            divider,

            // 5. Quran Majlis
            _buildRow(
              icon: Icons.groups_rounded,
              iconColor: const Color(0xFF2563EB),
              title: isId ? 'Majlis Quran' : 'Quran Majlis',
              text: isId
                  ? 'Tilawah bersama secara langsung via audio & sinkronisasi halaman mushaf dengan kode 5 angka.'
                  : 'Recite together live with open voice call & synced pages via a 5-digit code.',
              c: c,
            ),
          ],
        ),
      ),
      primaryAction: AppDialogActionItem(
        label: isId ? 'Mengerti' : 'Got it',
        onPressed: () => Navigator.of(context).pop(),
      ),
    );
  }

  Widget _buildChip(Color color, String label, ThemeColors c, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.16 : 0.10),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: color.withValues(alpha: isDark ? 0.38 : 0.28),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5.5,
            height: 5.5,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4.5),
          Text(
            label,
            style: TextStyle(
              color: isDark ? c.text : color,
              fontSize: 10.6,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    required ThemeColors c,
    String? text,
    Widget? extra,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 16.5, color: iconColor),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(color: c.text, fontSize: 12.5, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 1.5),
              if (text != null)
                Text(
                  text,
                  style: TextStyle(color: c.textSecondary, fontSize: 11.5, height: 1.35),
                ),
              if (extra != null) extra,
            ],
          ),
        ),
      ],
    );
  }
}

/// Backward compatibility alias
typedef WhatsNewDialog = AppGuideDialog;

// ══════════════════════════════════════════════════════════════════════════════
// 2. MAGLIS HOW-TO EXPLANATION DIALOG
// ══════════════════════════════════════════════════════════════════════════════

class MaglisExplanationDialog extends StatelessWidget {
  const MaglisExplanationDialog({super.key});

  /// Displays the explanation dialog and persists that the user has seen it.
  static Future<void> show(BuildContext context) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: DialogTokens.barrierColor,
      builder: (_) => const MaglisExplanationDialog(),
    );
    final prefs = await SharedPreferences.getInstance();
    AppState.instance.hasSeenMaglisExplanation = true;
    await prefs.setBool('has_seen_maglis_explanation', true);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    final isId = app.isIndonesian;
    final c = app.colors;

    final purpose = isId
        ? 'Majlis tilawah Al-Qur’an interaktif dengan sambungan suara langsung dan sinkronisasi mushaf bersama (hingga 4 peserta).'
        : 'A live Quran Majlis with open voice & synced Mushaf (up to 4 peers) to recite and correct together.';

    return AppDialog(
      heroIcon: const AppDialogHeroIcon(
        icon: Icons.groups_rounded,
        iconSize: 30,
        padding: 12,
      ),
      title: isId ? 'Majlis Al-Qur’an' : 'The Glorious Quran Majlis',
      banner: AppDialogInfoBanner(
        text: purpose,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildStepRow(
            number: '1',
            title: isId ? 'Kode Majlis (5 Digit)' : '5-Digit Majlis Code',
            body: isId
                ? '• Tuan Rumah: Tekan "Buka Majlis" dan bagikan kode kepada teman.\n• Peserta: Tekan "Gabung Majlis", masukkan kode 5 digit, dan langsung bergabung.'
                : '• Teacher: Taps "Open Majlis" and shares the code.\n• Student: Taps "Join Majlis", types code, and enters instantly.',
            c: c,
          ),
          const SizedBox(height: 10),
          _buildStepRow(
            number: '2',
            title: isId ? 'Tilawah & Saling Memperbaiki' : 'Reciting & Guiding',
            body: isId
                ? '• Panggilan suara aktif secara otomatis untuk saling menyimak dan berbincang.\n• Tekan tombol "Rekam" saat giliran membaca untuk menampilkan mushaf dan bacaan Anda ke semua peserta.'
                : '• Voice call is live for everyone to listen and guide.\n• Tap "Record" to broadcast your recitation and verses live.',
            c: c,
          ),
        ],
      ),
      primaryAction: AppDialogActionItem(
        label: isId ? 'Mengerti, Mulai' : "Got it, let's start",
        onPressed: () {
          Navigator.of(context).pop();
        },
      ),
    );
  }

  Widget _buildStepRow({
    required String number,
    required String title,
    required String body,
    required ThemeColors c,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: c.surfaceHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: c.border.withValues(alpha: 0.35),
          width: 0.9,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: c.primary,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              number,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: c.text,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: TextStyle(
                    color: c.muted,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
