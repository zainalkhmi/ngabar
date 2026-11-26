import 'package:flutter/material.dart';
import '../core/app_state.dart';
import 'iqro_audio_service.dart';
import 'iqro_controller.dart';
import 'iqro_picker_sheet.dart';
import 'iqro_repository.dart';

/// Digital Iqro Mushaf view replacing MushafView when Iqro mode is active.
/// Displays structured rows & columns from dyazincahya/iqro-json with
/// real-time green (correct) and red (mistake) AI highlighting.
class IqroView extends StatefulWidget {
  final ThemeColors c;
  final bool isRecording;
  final VoidCallback onExitIqro;

  const IqroView({
    super.key,
    required this.c,
    required this.isRecording,
    required this.onExitIqro,
  });

  @override
  State<IqroView> createState() => _IqroViewState();
}

class _IqroViewState extends State<IqroView> {
  bool _showLatin = false;

  @override
  void initState() {
    super.initState();
    final app = AppState.instance;
    final ctrl = IqroController.instance;
    if (ctrl.currentPageData == null ||
        ctrl.currentPageData!.jilid != app.iqroJilid ||
        ctrl.currentPageData!.page != app.iqroPage) {
      ctrl.loadPage(app.iqroJilid, app.iqroPage);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    final c = widget.c;
    final isDark = app.isDarkMode;
    final safeTop = MediaQuery.of(context).padding.top;
    final safeBottom = MediaQuery.of(context).padding.bottom;

    return ListenableBuilder(
      listenable: Listenable.merge([
        IqroController.instance,
        app.iqroPositionNotifier,
      ]),
      builder: (context, _) {
        final ctrl = IqroController.instance;
        final pageData = ctrl.currentPageData;
        final jilid = app.iqroJilid;
        final page = app.iqroPage;
        final totalPages = IqroRepository.instance.pageCountFor(jilid);

        return Container(
          color: c.bg,
          child: Column(
            children: [
              // Top Mushaf-style Iqro header
              Container(
                padding: EdgeInsets.fromLTRB(14, safeTop + 8, 14, 10),
                decoration: BoxDecoration(
                  color: c.surface,
                  border: Border(
                    bottom: BorderSide(
                      color: c.border.withValues(alpha: 0.45),
                      width: 0.8,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    // Back to Mushaf pill
                    _HeaderPill(
                      icon: Icons.menu_book_rounded,
                      label: app.isIndonesian ? 'Mushaf' : 'Mushaf',
                      isDark: isDark,
                      c: c,
                      onTap: widget.onExitIqro,
                    ),
                    const SizedBox(width: 8),
                    // Jilid & Page selector pill
                    Expanded(
                      child: GestureDetector(
                        onTap: () => IqroPickerSheet.show(context),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981)
                                .withValues(alpha: isDark ? 0.16 : 0.10),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: const Color(0xFF10B981)
                                  .withValues(alpha: 0.35),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                "Iqro' $jilid  •  Hal $page/$totalPages",
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontFamily: 'cairo',
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: isDark
                                      ? const Color(0xFF34D399)
                                      : const Color(0xFF047857),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                Icons.keyboard_arrow_down_rounded,
                                size: 18,
                                color: isDark
                                    ? const Color(0xFF34D399)
                                    : const Color(0xFF047857),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Latin transliteration toggle
                    _HeaderPill(
                      icon: Icons.translate_rounded,
                      label: 'Latin',
                      isActive: _showLatin,
                      isDark: isDark,
                      c: c,
                      onTap: () => setState(() => _showLatin = !_showLatin),
                    ),
                    const SizedBox(width: 6),
                    // Reset page highlights
                    _HeaderIconBtn(
                      icon: Icons.refresh_rounded,
                      tooltip: 'Reset Halaman',
                      isDark: isDark,
                      c: c,
                      onTap: ctrl.resetPageProgress,
                    ),
                  ],
                ),
              ),

              // Live AI heard / instruction strip
              if (widget.isRecording ||
                  (pageData != null && pageData.instructionId.isNotEmpty))
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 7,
                  ),
                  color: widget.isRecording
                      ? const Color(0xFF10B981)
                          .withValues(alpha: isDark ? 0.12 : 0.08)
                      : c.surface.withValues(alpha: 0.6),
                  child: widget.isRecording
                      ? Row(
                          children: [
                            Container(
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(
                                color: Color(0xFF10B981),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                ctrl.lastHeardText.isEmpty
                                    ? 'Mendengarkan bacaan Iqro\'...'
                                    : 'Terdeteksi: ${ctrl.lastHeardText}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textDirection: ctrl.lastHeardText.isEmpty
                                    ? TextDirection.ltr
                                    : TextDirection.rtl,
                                style: TextStyle(
                                  fontFamily: 'cairo',
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: isDark
                                      ? const Color(0xFF34D399)
                                      : const Color(0xFF047857),
                                ),
                              ),
                            ),
                            Text(
                              '${ctrl.correctCount}/${pageData?.content.length ?? 0}',
                              style: TextStyle(
                                fontFamily: 'cairo',
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: c.textSecondary,
                              ),
                            ),
                          ],
                        )
                      : Text(
                          app.isArabic
                              ? (pageData!.instructionAr.isNotEmpty
                                  ? pageData.instructionAr
                                  : pageData.instructionId)
                              : (app.isIndonesian
                                  ? pageData!.instructionId
                                  : (pageData!.instructionEn.isNotEmpty
                                      ? pageData.instructionEn
                                      : pageData.instructionId)),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontFamily: 'cairo',
                            fontSize: 11.5,
                            color: c.textSecondary,
                          ),
                        ),
                ),

              // Main Iqro Page Canvas
              Expanded(
                child: ctrl.isLoading || pageData == null
                    ? Center(
                        child: CircularProgressIndicator(color: c.emerald),
                      )
                    : _buildPageContent(pageData, ctrl, c, isDark, safeBottom),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPageContent(
    IqroPageData pageData,
    IqroController ctrl,
    ThemeColors c,
    bool isDark,
    double safeBottom,
  ) {
    final rows = pageData.rows;
    final totalPages = IqroRepository.instance.pageCountFor(pageData.jilid);
    // Map orderId -> flat index in pageData.content
    final Map<int, int> indexByOrder = {
      for (int i = 0; i < pageData.content.length; i++)
        pageData.content[i].orderId: i,
    };

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(12, 12, 12, safeBottom + 96),
      child: Column(
        children: [
          // Topic banner if present
          if (pageData.topicArab.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: c.border.withValues(alpha: 0.6),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    pageData.topicArab,
                    textDirection: TextDirection.rtl,
                    style: TextStyle(
                      fontFamily: 'HafsSmart',
                      fontSize: 26,
                      color: c.text,
                    ),
                  ),
                  if (pageData.topicLatin.isNotEmpty) ...[
                    const SizedBox(width: 12),
                    Text(
                      pageData.topicLatin,
                      style: TextStyle(
                        fontFamily: 'cairo',
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: c.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),

          // Mushaf-framed Iqro rows (RTL right-to-left)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: c.border.withValues(alpha: 0.7),
                width: 1.2,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.05),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: [
                for (int r = 0; r < rows.length; r++) ...[
                  Directionality(
                    textDirection: TextDirection.rtl,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          for (final cell in rows[r])
                            Expanded(
                              child: _buildCell(
                                cell: cell,
                                flatIndex: indexByOrder[cell.orderId] ?? 0,
                                ctrl: ctrl,
                                c: c,
                                isDark: isDark,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (r < rows.length - 1)
                    Divider(
                      height: 8,
                      thickness: 0.6,
                      color: c.border.withValues(alpha: 0.3),
                    ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Prev / Next Page Controls
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _PageNavButton(
                icon: Icons.chevron_left_rounded,
                label: 'Hal Sebelumnya',
                enabled: pageData.page > 1,
                c: c,
                isDark: isDark,
                onTap: () => ctrl.goToPage(pageData.jilid, pageData.page - 1),
              ),
              Text(
                '${pageData.page} / $totalPages',
                style: TextStyle(
                  fontFamily: 'cairo',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: c.textSecondary,
                ),
              ),
              _PageNavButton(
                icon: Icons.chevron_right_rounded,
                label: 'Hal Berikutnya',
                iconRight: true,
                enabled: pageData.page < totalPages,
                c: c,
                isDark: isDark,
                onTap: () => ctrl.goToPage(pageData.jilid, pageData.page + 1),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCell({
    required IqroCellData cell,
    required int flatIndex,
    required IqroController ctrl,
    required ThemeColors c,
    required bool isDark,
  }) {
    final status = ctrl.statusFor(cell.orderId);
    final isActive = ctrl.activeIndex == flatIndex;

    Color bgColor = Colors.transparent;
    Color borderColor = Colors.transparent;
    Color textColor = c.text;

    if (status == IqroCellStatus.correct) {
      bgColor = const Color(0xFF10B981).withValues(alpha: isDark ? 0.22 : 0.14);
      borderColor = const Color(0xFF10B981).withValues(alpha: 0.65);
      textColor = isDark ? const Color(0xFF6EE7B7) : const Color(0xFF065F46);
    } else if (status == IqroCellStatus.mistake) {
      bgColor = const Color(0xFFEF4444).withValues(alpha: isDark ? 0.22 : 0.14);
      borderColor = const Color(0xFFEF4444).withValues(alpha: 0.70);
      textColor = isDark ? const Color(0xFFFCA5A5) : const Color(0xFF991B1B);
    } else if (isActive) {
      bgColor = const Color(0xFFF59E0B).withValues(alpha: isDark ? 0.15 : 0.10);
      borderColor = const Color(0xFFF59E0B).withValues(alpha: 0.75);
    }

    return GestureDetector(
      onTap: () {
        ctrl.selectCell(flatIndex);
        IqroAudioService.instance.speakArabic(cell.arabic);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        margin: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: borderColor,
            width: isActive || status != IqroCellStatus.unread ? 1.4 : 0.5,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                cell.arabic,
                textDirection: TextDirection.rtl,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'HafsSmart',
                  fontSize: 27,
                  height: 1.45,
                  color: textColor,
                ),
              ),
            ),
            if (_showLatin && cell.latin.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                cell.latin,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textDirection: TextDirection.ltr,
                style: TextStyle(
                  fontFamily: 'cairo',
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: c.textSecondary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HeaderPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final bool isDark;
  final ThemeColors c;
  final VoidCallback onTap;

  const _HeaderPill({
    required this.icon,
    required this.label,
    this.isActive = false,
    required this.isDark,
    required this.c,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = isActive
        ? (isDark ? const Color(0xFF34D399) : const Color(0xFF047857))
        : c.text;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: isActive
              ? const Color(0xFF10B981).withValues(alpha: isDark ? 0.2 : 0.12)
              : (isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.black.withValues(alpha: 0.05)),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: isActive
                ? const Color(0xFF10B981).withValues(alpha: 0.5)
                : c.border.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: fg),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'cairo',
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeaderIconBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool isDark;
  final ThemeColors c;
  final VoidCallback onTap;

  const _HeaderIconBtn({
    required this.icon,
    required this.tooltip,
    required this.isDark,
    required this.c,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: isDark
                ? Colors.white.withValues(alpha: 0.06)
                : Colors.black.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, size: 18, color: c.text),
        ),
      ),
    );
  }
}

class _PageNavButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool iconRight;
  final bool enabled;
  final ThemeColors c;
  final bool isDark;
  final VoidCallback onTap;

  const _PageNavButton({
    required this.icon,
    required this.label,
    this.iconRight = false,
    required this.enabled,
    required this.c,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1.0 : 0.35,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.border.withValues(alpha: 0.6)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!iconRight) Icon(icon, size: 18, color: c.text),
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'cairo',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: c.text,
                ),
              ),
              if (iconRight) Icon(icon, size: 18, color: c.text),
            ],
          ),
        ),
      ),
    );
  }
}
