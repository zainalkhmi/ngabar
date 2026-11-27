import 'package:flutter/material.dart';
import '../audio/mistake_audio_service.dart';
import '../core/app_state.dart';
import '../core/subscription_service.dart';
import '../maglis/maglis_controller.dart';
import '../ui/widgets/dialogs/subscription_paywall_sheet.dart';
import 'iqro_audio_service.dart';
import 'iqro_controller.dart';
import 'iqro_mistake_sheet.dart';
import 'iqro_picker_sheet.dart';
import 'iqro_progress_service.dart';
import 'iqro_repository.dart';
import 'iqro_tajweed_service.dart';
import 'iqro_tajweed_sheet.dart';

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
        MistakeAudioService.instance.revision,
        IqroAudioService.instance.isAutoPlayingNotifier,
        IqroAudioService.instance.autoPlayOrderIdNotifier,
        IqroAudioService.instance.tempoNotifier,
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
                      color: c.border.withValues(alpha: 0.5),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    // Back to Quran Mushaf button
                    _HeaderIconBtn(
                      icon: Icons.menu_book_rounded,
                      tooltip: app.isIndonesian
                          ? 'Kembali ke Mushaf Al-Qur\'an'
                          : 'Return to Mushaf',
                      isDark: isDark,
                      c: c,
                      onTap: widget.onExitIqro,
                    ),
                    const SizedBox(width: 8),

                    // Jilid & Page selector pill
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          IqroPickerSheet.show(context);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.white.withValues(alpha: 0.06)
                                : Colors.black.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: c.border.withValues(alpha: 0.6),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981)
                                      .withValues(alpha: isDark ? 0.25 : 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  'Jilid $jilid',
                                  style: TextStyle(
                                    fontFamily: 'cairo',
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: isDark
                                        ? const Color(0xFF34D399)
                                        : const Color(0xFF047857),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Halaman $page / $totalPages',
                                  style: TextStyle(
                                    fontFamily: 'cairo',
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: c.text,
                                  ),
                                ),
                              ),
                              Icon(
                                Icons.keyboard_arrow_down_rounded,
                                size: 20,
                                color: c.textSecondary,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(width: 8),

                    // Toggle Latin transliteration
                    _HeaderIconBtn(
                      icon: _showLatin
                          ? Icons.subtitles_rounded
                          : Icons.subtitles_off_rounded,
                      tooltip: _showLatin
                          ? 'Sembunyikan Latin'
                          : 'Tampilkan Latin',
                      isDark: isDark,
                      c: c,
                      onTap: () {
                        setState(() => _showLatin = !_showLatin);
                      },
                    ),

                    const SizedBox(width: 6),

                    // Reset progress for this page
                    _HeaderIconBtn(
                      icon: Icons.refresh_rounded,
                      tooltip: 'Reset Halaman',
                      isDark: isDark,
                      c: c,
                      onTap: () => ctrl.resetPageProgress(),
                    ),
                  ],
                ),
              ),

              // Sub-toolbar: Auto-Play, Tempo, Exam Mode & Stats
              if (pageData != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: c.surface,
                    border: Border(
                      bottom: BorderSide(
                        color: c.border.withValues(alpha: 0.35),
                        width: 0.7,
                      ),
                    ),
                  ),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        // 1. Auto-Play "Dengar & Ikuti"
                        _HeaderPill(
                          icon: IqroAudioService.instance.isAutoPlayingNotifier.value
                              ? Icons.stop_circle_rounded
                              : Icons.play_circle_filled_rounded,
                          label: IqroAudioService.instance.isAutoPlayingNotifier.value
                              ? 'Stop'
                              : 'Dengar',
                          isActive: IqroAudioService.instance.isAutoPlayingNotifier.value,
                          isDark: isDark,
                          c: c,
                          onTap: ctrl.isExamMode
                              ? () {}
                              : () {
                                  if (IqroAudioService
                                      .instance.isAutoPlayingNotifier.value) {
                                    IqroAudioService.instance.stopAutoPlay();
                                  } else {
                                    IqroAudioService.instance.startAutoPlayPage(
                                      pageData.content,
                                      startIndex: ctrl.activeIndex,
                                      onCellActive: (idx) =>
                                          ctrl.selectCell(idx),
                                    );
                                  }
                                },
                        ),
                        const SizedBox(width: 6),
                        // 2. Tempo Toggle (0.75x / 1.0x)
                        _HeaderPill(
                          icon: Icons.speed_rounded,
                          label: IqroAudioService.instance.tempo < 1.0
                              ? '0.75x'
                              : '1.0x',
                          isActive: IqroAudioService.instance.tempo < 1.0,
                          isDark: isDark,
                          c: c,
                          onTap: () =>
                              IqroAudioService.instance.toggleTempo(),
                        ),
                        const SizedBox(width: 6),
                        // 3. Exam Mode ("Ujian")
                        _HeaderPill(
                          icon: Icons.assignment_turned_in_rounded,
                          label: ctrl.isExamMode ? 'Mode Ujian' : 'Ujian',
                          isActive: ctrl.isExamMode,
                          isDark: isDark,
                          c: c,
                          onTap: () {
                            if (!ctrl.isExamMode &&
                                !SubscriptionService.instance.isPremium) {
                              SubscriptionPaywallSheet.show(context);
                              return;
                            }
                            IqroAudioService.instance.stopAutoPlay();
                            ctrl.setExamMode(!ctrl.isExamMode);
                          },
                        ),
                        if (ctrl.isExamMode || ctrl.isPageCompleted) ...[
                          const SizedBox(width: 6),
                          _HeaderPill(
                            icon: Icons.emoji_events_rounded,
                            label: 'Rapor (${ctrl.accuracyPct}%)',
                            isActive: ctrl.accuracyPct >=
                                IqroProgressService.passThresholdPct,
                            isDark: isDark,
                            c: c,
                            onTap: () => _showExamReportSheet(
                              context,
                              pageData: pageData,
                              ctrl: ctrl,
                              c: c,
                              isDark: isDark,
                            ),
                          ),
                        ],
                        if (MaglisController.instance.inSession) ...[
                          const SizedBox(width: 6),
                          _HeaderPill(
                            icon: Icons.groups_rounded,
                            label: 'Kirim ke Majlis',
                            isActive: true,
                            isDark: isDark,
                            c: c,
                            onTap: () {
                              MaglisController.instance.sendChatMessage(
                                "📖 Belajar Iqro' ${pageData.jilid} • Hal ${pageData.page}",
                              );
                            },
                          ),
                        ],
                      ],
                    ),
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
                                    ? (app.isArabic
                                        ? 'جاري الاستماع لقراءة اقرأ...'
                                        : (app.isIndonesian
                                            ? 'Mendengarkan bacaan Iqro\'...'
                                            : 'Listening to Iqro recitation...'))
                                    : '"${ctrl.lastHeardText}"',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                textDirection: ctrl.lastHeardText.isEmpty
                                    ? TextDirection.ltr
                                    : TextDirection.rtl,
                                style: TextStyle(
                                  fontFamily: 'cairo',
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: c.text,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: (ctrl.isCurrentCellInQuran
                                        ? const Color(0xFF10B981)
                                        : const Color(0xFFF59E0B))
                                    .withValues(alpha: isDark ? 0.22 : 0.14),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                ctrl.isCurrentCellInQuran
                                    ? 'AI Qur\'an'
                                    : 'AI Latihan',
                                style: TextStyle(
                                  fontFamily: 'cairo',
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: ctrl.isCurrentCellInQuran
                                      ? (isDark
                                          ? const Color(0xFF34D399)
                                          : const Color(0xFF047857))
                                      : (isDark
                                          ? const Color(0xFFFBBF24)
                                          : const Color(0xFFB45309)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 6),
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
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
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

          if (ctrl.isPageCompleted) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981)
                    .withValues(alpha: isDark ? 0.16 : 0.10),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: const Color(0xFF10B981).withValues(alpha: 0.45),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_circle_rounded,
                    color: Color(0xFF10B981),
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      AppState.instance.isArabic
                          ? 'أحسنت! اكتملت الصفحة'
                          : (AppState.instance.isIndonesian
                              ? 'Alhamdulillah, halaman selesai!'
                              : 'Great! Page completed!'),
                      style: TextStyle(
                        fontFamily: 'cairo',
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: isDark
                            ? const Color(0xFF6EE7B7)
                            : const Color(0xFF065F46),
                      ),
                    ),
                  ),
                  if (pageData.page < totalPages || pageData.jilid < 6)
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () {
                        if (pageData.page < totalPages) {
                          ctrl.goToPage(pageData.jilid, pageData.page + 1);
                        } else if (pageData.jilid < 6) {
                          ctrl.goToPage(pageData.jilid + 1, 1);
                        }
                      },
                      child: Text(
                        pageData.page < totalPages
                            ? (AppState.instance.isIndonesian
                                ? 'Lanjut Hal ${pageData.page + 1}'
                                : 'Next Pg ${pageData.page + 1}')
                            : (AppState.instance.isIndonesian
                                ? "Lanjut Iqro' ${pageData.jilid + 1}"
                                : "Next Iqro' ${pageData.jilid + 1}"),
                        style: const TextStyle(
                          fontFamily: 'cairo',
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 16),

          // Prev / Next Page Controls
          Row(
            children: [
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: _PageNavButton(
                    icon: Icons.chevron_left_rounded,
                    label: AppState.instance.isArabic
                        ? 'السابق'
                        : (AppState.instance.isIndonesian
                            ? 'Sebelumnya'
                            : 'Previous'),
                    enabled: pageData.page > 1,
                    c: c,
                    isDark: isDark,
                    onTap: () => ctrl.goToPage(pageData.jilid, pageData.page - 1),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  '${pageData.page} / $totalPages',
                  style: TextStyle(
                    fontFamily: 'cairo',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: c.textSecondary,
                  ),
                ),
              ),
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: _PageNavButton(
                    icon: Icons.chevron_right_rounded,
                    label: AppState.instance.isArabic
                        ? 'التالي'
                        : (AppState.instance.isIndonesian
                            ? 'Berikutnya'
                            : 'Next'),
                    iconRight: true,
                    enabled: pageData.page < totalPages,
                    c: c,
                    isDark: isDark,
                    onTap: () => ctrl.goToPage(pageData.jilid, pageData.page + 1),
                  ),
                ),
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
    final isAutoPlayingThis =
        IqroAudioService.instance.autoPlayOrderIdNotifier.value == cell.orderId;

    // Detect Tajweed rule for advanced jilids (Iqro' 4, 5, 6)
    final jilid = ctrl.currentPageData?.jilid ?? 1;
    final tajweedRule = jilid >= 4
        ? IqroTajweedService.instance.detectRule(cell.arabic)
        : null;

    Color bgColor = Colors.transparent;
    Color borderColor = Colors.transparent;
    Color textColor = c.text;

    if (isAutoPlayingThis) {
      bgColor = const Color(0xFF0EA5E9).withValues(alpha: isDark ? 0.24 : 0.14);
      borderColor = const Color(0xFF0EA5E9).withValues(alpha: 0.85);
    } else if (status == IqroCellStatus.correct) {
      bgColor = const Color(0xFF10B981).withValues(alpha: isDark ? 0.22 : 0.14);
      borderColor = const Color(0xFF10B981).withValues(alpha: 0.65);
      textColor = isDark ? const Color(0xFF6EE7B7) : const Color(0xFF065F46);
    } else if (status == IqroCellStatus.tajweed) {
      bgColor = const Color(0xFFF59E0B).withValues(alpha: isDark ? 0.24 : 0.16);
      borderColor = const Color(0xFFF59E0B).withValues(alpha: 0.80);
      textColor = isDark ? const Color(0xFFFDE68A) : const Color(0xFF92400E);
    } else if (status == IqroCellStatus.mistake) {
      bgColor = const Color(0xFFEF4444).withValues(alpha: isDark ? 0.22 : 0.14);
      borderColor = const Color(0xFFEF4444).withValues(alpha: 0.70);
      textColor = isDark ? const Color(0xFFFCA5A5) : const Color(0xFF991B1B);
    } else if (isActive) {
      bgColor = const Color(0xFFF59E0B).withValues(alpha: isDark ? 0.15 : 0.10);
      borderColor = const Color(0xFFF59E0B).withValues(alpha: 0.75);
    }

    final hasMistakeClip = status == IqroCellStatus.mistake &&
        ctrl.currentPageData != null &&
        MistakeAudioService.instance.hasClip(
          200 + ctrl.currentPageData!.jilid,
          ctrl.currentPageData!.page,
          cell.orderId.clamp(0, 255),
        );

    return GestureDetector(
      onTap: () {
        if (status == IqroCellStatus.mistake && ctrl.currentPageData != null) {
          IqroMistakeSheet.show(
            context,
            jilid: ctrl.currentPageData!.jilid,
            page: ctrl.currentPageData!.page,
            cell: cell,
            onRetryCell: () => ctrl.selectCell(flatIndex),
          );
          return;
        }
        if (status == IqroCellStatus.tajweed && tajweedRule != null) {
          IqroTajweedSheet.show(
            context,
            cell: cell,
            rule: tajweedRule,
            onRetryCell: () => ctrl.selectCell(flatIndex),
          );
          return;
        }
        ctrl.selectCell(flatIndex);
        if (!ctrl.isExamMode) {
          IqroAudioService.instance.speakArabic(
            cell.arabic,
            latinText: cell.latin,
            inQuran: cell.inQuran,
          );
        }
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Tajweed badge if detected
                if (tajweedRule != null)
                  GestureDetector(
                    onTap: () {
                      IqroTajweedSheet.show(
                        context,
                        cell: cell,
                        rule: tajweedRule,
                        onRetryCell: () => ctrl.selectCell(flatIndex),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: Color(tajweedRule.badgeColorValue)
                            .withValues(alpha: isDark ? 0.22 : 0.15),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: Color(tajweedRule.badgeColorValue)
                              .withValues(alpha: 0.5),
                          width: 0.6,
                        ),
                      ),
                      child: Text(
                        tajweedRule.nameId.split(' ')[0],
                        style: TextStyle(
                          fontFamily: 'cairo',
                          fontSize: 7.5,
                          fontWeight: FontWeight.w800,
                          color: Color(tajweedRule.badgeColorValue),
                        ),
                      ),
                    ),
                  )
                else
                  const SizedBox.shrink(),

                // Qur'an / Latihan badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: (cell.inQuran
                            ? const Color(0xFF047857)
                            : const Color(0xFF64748B))
                        .withValues(alpha: isDark ? 0.28 : 0.14),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: (cell.inQuran
                              ? const Color(0xFF10B981)
                              : const Color(0xFF94A3B8))
                          .withValues(alpha: isDark ? 0.45 : 0.35),
                      width: 0.7,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (cell.inQuran) ...[
                        Icon(
                          Icons.menu_book_rounded,
                          size: 9.5,
                          color: isDark
                              ? const Color(0xFF34D399)
                              : const Color(0xFF047857),
                        ),
                        const SizedBox(width: 3),
                      ],
                      Text(
                        cell.inQuran ? "Qur'an" : 'Latihan',
                        style: TextStyle(
                          fontFamily: 'cairo',
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                          color: cell.inQuran
                              ? (isDark
                                  ? const Color(0xFF34D399)
                                  : const Color(0xFF047857))
                              : c.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
              decoration: cell.inQuran
                  ? BoxDecoration(
                      color: isDark
                          ? const Color(0xFF064E3B).withValues(alpha: 0.08)
                          : const Color(0xFFECFDF5).withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: const Color(0xFF10B981)
                            .withValues(alpha: isDark ? 0.18 : 0.22),
                        width: 0.8,
                      ),
                    )
                  : null,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  cell.arabic,
                  textDirection: TextDirection.rtl,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'HafsSmart',
                    fontSize: cell.inQuran ? 30 : 27,
                    height: 1.45,
                    letterSpacing: cell.inQuran ? 0.4 : 0.0,
                    fontWeight: cell.inQuran ? FontWeight.w500 : FontWeight.normal,
                    color: textColor,
                  ),
                ),
              ),
            ),
            if (_showLatin && !ctrl.isExamMode && cell.latin.isNotEmpty) ...[
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
            if (hasMistakeClip) ...[
              const SizedBox(height: 2),
              const Icon(
                Icons.graphic_eq_rounded,
                size: 13,
                color: Color(0xFFEF4444),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showExamReportSheet(
    BuildContext context, {
    required IqroPageData pageData,
    required IqroController ctrl,
    required ThemeColors c,
    required bool isDark,
  }) {
    final pct = ctrl.accuracyPct;
    final passed = pct >= IqroProgressService.passThresholdPct;
    final mistakes = ctrl.mistakenCells;
    final totalPages = IqroRepository.instance.pageCountFor(pageData.jilid);

    if (pct > 0) {
      IqroProgressService.instance.recordPageScore(
        pageData.jilid,
        pageData.page,
        pct,
      );
    }

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 22),
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
              Icon(
                passed ? Icons.stars_rounded : Icons.school_rounded,
                size: 44,
                color: passed
                    ? const Color(0xFFFACC15)
                    : const Color(0xFFF59E0B),
              ),
              const SizedBox(height: 8),
              Text(
                passed
                    ? "Lulus! Iqro' ${pageData.jilid} Hal ${pageData.page}"
                    : "Terus Berlatih • Iqro' ${pageData.jilid} Hal ${pageData.page}",
                style: TextStyle(
                  fontFamily: 'cairo',
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: c.text,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Akurasi: $pct% (${ctrl.correctCount}/${pageData.content.length} Benar, ${ctrl.mistakeCount} Salah)',
                style: TextStyle(
                  fontFamily: 'cairo',
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: passed
                      ? const Color(0xFF10B981)
                      : const Color(0xFFF59E0B),
                ),
              ),
              if (mistakes.isNotEmpty) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Ketuk kata yang salah untuk dengar perbandingan:',
                    style: TextStyle(
                      fontFamily: 'cairo',
                      fontSize: 11.5,
                      color: c.textSecondary,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final m in mistakes.take(8))
                      GestureDetector(
                        onTap: () {
                          Navigator.of(ctx).pop();
                          IqroMistakeSheet.show(
                            context,
                            jilid: pageData.jilid,
                            page: pageData.page,
                            cell: m,
                            onRetryCell: () {},
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFEF4444)
                                .withValues(alpha: isDark ? 0.2 : 0.12),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: const Color(0xFFEF4444)
                                  .withValues(alpha: 0.5),
                            ),
                          ),
                          child: Text(
                            m.arabic,
                            textDirection: TextDirection.rtl,
                            style: TextStyle(
                              fontFamily: 'HafsSmart',
                              fontSize: 18,
                              color: isDark
                                  ? const Color(0xFFFCA5A5)
                                  : const Color(0xFF991B1B),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        ctrl.resetPageProgress();
                      },
                      child: const Text(
                        'Ulangi',
                        style: TextStyle(fontFamily: 'cairo'),
                      ),
                    ),
                  ),
                  if (pageData.page < totalPages) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF10B981),
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          ctrl.goToPage(pageData.jilid, pageData.page + 1);
                        },
                        child: const Text(
                          'Halaman Berikutnya',
                          style: TextStyle(
                            fontFamily: 'cairo',
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
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
  final bool enabled;
  final bool iconRight;
  final ThemeColors c;
  final bool isDark;
  final VoidCallback onTap;

  const _PageNavButton({
    required this.icon,
    required this.label,
    required this.enabled,
    this.iconRight = false,
    required this.c,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (!enabled) return const SizedBox.shrink();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
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
              if (!iconRight) ...[
                Icon(icon, size: 18, color: c.text),
                const SizedBox(width: 4),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'cairo',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: c.text,
                  ),
                ),
              ),
              if (iconRight) ...[
                const SizedBox(width: 4),
                Icon(icon, size: 18, color: c.text),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
