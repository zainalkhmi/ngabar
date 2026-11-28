import 'dart:async';
import 'package:flutter/material.dart';
import '../audio/mistake_audio_service.dart';
import '../core/app_state.dart';
import 'iqro_audio_service.dart';
import 'iqro_repository.dart';
import 'makhraj_visualizer.dart';

/// Bottom sheet shown when tapping a RED (mistake) Iqro' cell, allowing the
/// user to compare their recorded voice against the correct offline pronunciation.
class IqroMistakeSheet extends StatelessWidget {
  final int jilid;
  final int page;
  final IqroCellData cell;
  final VoidCallback onRetryCell;

  const IqroMistakeSheet({
    super.key,
    required this.jilid,
    required this.page,
    required this.cell,
    required this.onRetryCell,
  });

  static Future<void> show(
    BuildContext context, {
    required int jilid,
    required int page,
    required IqroCellData cell,
    required VoidCallback onRetryCell,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => IqroMistakeSheet(
        jilid: jilid,
        page: page,
        cell: cell,
        onRetryCell: onRetryCell,
      ),
    ).then((_) {
      unawaited(MistakeAudioService.instance.stopPlayback());
      unawaited(IqroAudioService.instance.stop());
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    final c = app.colors;
    final isDark = app.isDarkMode;
    final isId = app.isIndonesian;
    final isAr = app.isArabic;
    final mistakeService = MistakeAudioService.instance;

    return ValueListenableBuilder<int>(
      valueListenable: mistakeService.revision,
      builder: (context, _, __) {
        final clip = mistakeService.getClip(
          200 + jilid,
          page,
          cell.orderId.clamp(0, 255),
        );

        return Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 22),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
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
                const SizedBox(height: 16),
                Text(
                  isAr
                      ? 'تقييم القراءة • اقرأ $jilid (ص $page)'
                      : (isId
                          ? "Evaluasi Bacaan • Iqro' $jilid (Hal $page)"
                          : "Reading Review • Iqro' $jilid (Pg $page)"),
                  style: TextStyle(
                    fontFamily: 'cairo',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: c.textSecondary,
                  ),
                ),
                const SizedBox(height: 10),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444)
                        .withValues(alpha: isDark ? 0.16 : 0.09),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.5),
                    ),
                  ),
                  child: Column(
                    children: [
                      Text(
                        cell.arabic,
                        textDirection: TextDirection.rtl,
                        style: TextStyle(
                          fontFamily: 'HafsSmart',
                          fontSize: 38,
                          color: isDark
                              ? const Color(0xFFFCA5A5)
                              : const Color(0xFF991B1B),
                        ),
                      ),
                      if (cell.latin.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          cell.latin,
                          style: TextStyle(
                            fontFamily: 'cairo',
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: c.textSecondary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 18),

                // Side-by-side comparison buttons
                Row(
                  children: [
                    // 1. User's recorded voice
                    Expanded(
                      child: ValueListenableBuilder<bool>(
                        valueListenable: mistakeService.isPlayingNotifier,
                        builder: (context, isPlaying, _) {
                          final bool hasRec = clip != null;
                          return _CompareActionCard(
                            icon: isPlaying
                                ? Icons.stop_rounded
                                : Icons.mic_rounded,
                            title: isAr
                                ? 'صوتك'
                                : (isId ? 'Suara Anda' : 'Your Voice'),
                            subtitle: hasRec
                                ? (isAr
                                    ? '${(clip.durationMs / 1000).toStringAsFixed(1)} ث'
                                    : (isId
                                        ? '${(clip.durationMs / 1000).toStringAsFixed(1)} dtk'
                                        : '${(clip.durationMs / 1000).toStringAsFixed(1)} sec'))
                                : (isAr
                                    ? 'جاري التحضير...'
                                    : (isId ? 'Menyiapkan...' : 'Preparing...')),
                            color: const Color(0xFFEF4444),
                            enabled: hasRec,
                            isDark: isDark,
                            c: c,
                            onTap: () {
                              if (!hasRec) return;
                              IqroAudioService.instance.stop();
                              if (isPlaying) {
                                mistakeService.stopPlayback();
                              } else {
                                mistakeService.playClip(clip);
                              }
                            },
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    // 2. Correct offline pronunciation
                    Expanded(
                      child: _CompareActionCard(
                        icon: Icons.volume_up_rounded,
                        title: isAr
                            ? 'النطق الصحيح'
                            : (isId ? 'Pelafalan Benar' : 'Correct Sound'),
                        subtitle: isAr ? 'صوت اقرأ' : "Audio Iqro'",
                        color: const Color(0xFF10B981),
                        enabled: true,
                        isDark: isDark,
                        c: c,
                        onTap: () {
                          mistakeService.stopPlayback();
                          IqroAudioService.instance.speakArabic(
                            cell.arabic,
                            latinText: cell.latin,
                          );
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                MakhrajVisualizer(arabicText: cell.arabic),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                      onRetryCell();
                    },
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: Text(
                      isAr
                          ? 'إعادة قراءة هذا المربع'
                          : (isId ? 'Ulangi Baca Sel Ini' : 'Retry This Cell'),
                      style: const TextStyle(
                        fontFamily: 'cairo',
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: c.text,
                      side: BorderSide(color: c.border),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _CompareActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final bool enabled;
  final bool isDark;
  final ThemeColors c;
  final VoidCallback onTap;

  const _CompareActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.enabled,
    required this.isDark,
    required this.c,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.45,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            color: color.withValues(alpha: isDark ? 0.16 : 0.10),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.45)),
          ),
          child: Column(
            children: [
              Icon(icon, size: 24, color: color),
              const SizedBox(height: 6),
              Text(
                title,
                style: TextStyle(
                  fontFamily: 'cairo',
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: c.text,
                ),
              ),
              Text(
                subtitle,
                style: TextStyle(
                  fontFamily: 'cairo',
                  fontSize: 11,
                  color: c.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
