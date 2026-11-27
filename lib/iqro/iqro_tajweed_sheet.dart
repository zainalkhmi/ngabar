import 'dart:async';
import 'package:flutter/material.dart';
import '../core/app_state.dart';
import 'iqro_audio_service.dart';
import 'iqro_repository.dart';
import 'iqro_tajweed_service.dart';

/// Modal bottom sheet showing Tajweed rule guidance for an Iqro cell
/// (especially when flagged yellow for timing/tajweed by AI, or inspected by user).
class IqroTajweedSheet extends StatelessWidget {
  final IqroCellData cell;
  final IqroTajweedRule rule;
  final VoidCallback? onRetryCell;

  const IqroTajweedSheet({
    super.key,
    required this.cell,
    required this.rule,
    this.onRetryCell,
  });

  static Future<void> show(
    BuildContext context, {
    required IqroCellData cell,
    required IqroTajweedRule rule,
    VoidCallback? onRetryCell,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => IqroTajweedSheet(
        cell: cell,
        rule: rule,
        onRetryCell: onRetryCell,
      ),
    ).then((_) {
      unawaited(IqroAudioService.instance.stop());
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    final c = app.colors;
    final isDark = app.isDarkMode;
    final ruleColor = Color(rule.badgeColorValue);

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: c.border.withValues(alpha: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle bar
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

            // Header with badge
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: ruleColor.withValues(alpha: isDark ? 0.25 : 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: ruleColor.withValues(alpha: 0.6),
                      width: 1.2,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.auto_stories_rounded,
                          size: 14, color: ruleColor),
                      const SizedBox(width: 6),
                      Text(
                        rule.nameId,
                        style: TextStyle(
                          fontFamily: 'cairo',
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: ruleColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Text(
                  rule.nameAr,
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    fontFamily: 'HafsSmart',
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: c.text,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Arabic Display Box
            Container(
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
              decoration: BoxDecoration(
                color: c.bg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: ruleColor.withValues(alpha: 0.4),
                  width: 1.5,
                ),
              ),
              child: Column(
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      cell.arabic,
                      textDirection: TextDirection.rtl,
                      style: TextStyle(
                        fontFamily: 'HafsSmart',
                        fontSize: 38,
                        height: 1.4,
                        color: c.text,
                      ),
                    ),
                  ),
                  if (cell.latin.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      cell.latin,
                      style: TextStyle(
                        fontFamily: 'cairo',
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: c.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Tajweed Explanation Box
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: ruleColor.withValues(alpha: isDark ? 0.12 : 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: ruleColor.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    color: ruleColor,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          app.isIndonesian
                              ? 'Petunjuk Tajwid:'
                              : 'Tajweed Guidance:',
                          style: TextStyle(
                            fontFamily: 'cairo',
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: c.text,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          app.isIndonesian
                              ? rule.descriptionId
                              : rule.descriptionEn,
                          style: TextStyle(
                            fontFamily: 'cairo',
                            fontSize: 12,
                            height: 1.35,
                            color: c.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),

            // Actions: "Dengar Qari" and "Ulangi Bacaan"
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: c.emerald,
                      side: BorderSide(color: c.emerald.withValues(alpha: 0.6)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.volume_up_rounded, size: 18),
                    label: Text(
                      cell.inQuran
                          ? (app.isIndonesian ? 'Dengar Qari' : 'Listen Qari')
                          : (app.isIndonesian ? 'Dengar Audio' : 'Listen Audio'),
                      style: const TextStyle(
                        fontFamily: 'cairo',
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    onPressed: () {
                      IqroAudioService.instance.speakArabic(
                        cell.arabic,
                        latinText: cell.latin,
                        inQuran: cell.inQuran,
                      );
                    },
                  ),
                ),
                if (onRetryCell != null) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: c.emerald,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.replay_rounded, size: 18),
                      label: Text(
                        app.isIndonesian ? 'Coba Lagi' : 'Retry',
                        style: const TextStyle(
                          fontFamily: 'cairo',
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      onPressed: () {
                        Navigator.of(context).pop();
                        onRetryCell!();
                      },
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
