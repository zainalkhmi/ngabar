import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../../core/platform_utils.dart';
import '../../core/app_state.dart';
import '../../core/maglis_link_service.dart';
import '../../maglis/maglis_controller.dart';
import '../../audio/quran_audio_service.dart';
import '../../audio/screen_recording_service.dart';
import '../../iqro/iqro_audio_service.dart';
import '../../iqro/iqro_picker_sheet.dart';
import 'dialogs/live_stream_sheet.dart';

enum MicBarMode { recording, maglis, maglisRecording, normal }

class BottomActionBar extends StatelessWidget {
  final bool isRecording;
  final bool isLoadingEngine;
  final ThemeColors c;
  final VoidCallback onMic;
  final bool isBlur;
  final VoidCallback onToggleBlur;
  final bool isTajweed;
  final VoidCallback onToggleTajweed;
  final String surahName;
  final VoidCallback onSurahTap;
  final VoidCallback onSettingsTap;
  final VoidCallback? onPlayReciteTap;
  final VoidCallback? onVoiceSearchTap;
  final bool isVoiceSearching;
  final bool isScreenRecording;
  final VoidCallback? onScreenRecordTap;
  final VoidCallback? onOpenRecordingsTap;
  final bool isInMaglis;
  final VoidCallback? onMaglisTap;
  final VoidCallback? onMaglisExitTap;
  final VoidCallback? onMaglisChatTap;
  final String? maglisRoomCode;
  final int maglisPeerCount;
  final bool isRemoteReciting;
  final bool isIqroMode;
  final VoidCallback? onIqroTap;

  const BottomActionBar({
    super.key,
    required this.isRecording,
    this.isLoadingEngine = false,
    required this.c,
    required this.onMic,
    required this.isBlur,
    required this.onToggleBlur,
    required this.isTajweed,
    required this.onToggleTajweed,
    required this.surahName,
    required this.onSurahTap,
    required this.onSettingsTap,
    this.onPlayReciteTap,
    this.onVoiceSearchTap,
    this.isVoiceSearching = false,
    this.isScreenRecording = false,
    this.onScreenRecordTap,
    this.onOpenRecordingsTap,
    this.isInMaglis = false,
    this.onMaglisTap,
    this.onMaglisExitTap,
    this.onMaglisChatTap,
    this.maglisRoomCode,
    this.maglisPeerCount = 0,
    this.isRemoteReciting = false,
    this.isIqroMode = false,
    this.onIqroTap,
  });

  MicBarMode get mode => isInMaglis
      ? (isRecording ? MicBarMode.maglisRecording : MicBarMode.maglis)
      : (isRecording ? MicBarMode.recording : MicBarMode.normal);

  static Color _btnBg(bool isDark, {bool isActive = false}) => isActive
      ? const Color(0xFF10B981).withValues(alpha: isDark ? 0.22 : 0.15)
      : (isDark ? const Color(0xFF1B2430) : const Color(0xFFF1F5F9));

  static Color _btnBorder(bool isDark, {bool isActive = false}) => isActive
      ? const Color(0xFF10B981).withValues(alpha: isDark ? 0.75 : 0.60)
      : (isDark
          ? Colors.white.withValues(alpha: 0.10)
          : Colors.black.withValues(alpha: 0.08));

  static Color _btnFg(bool isDark, {bool isActive = false}) => isActive
      ? (isDark ? const Color(0xFF10B981) : const Color(0xFF059699))
      : (isDark ? const Color(0xFFE2E8F0) : const Color(0xFF1E293B));

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    final bool isDark = app.isDarkMode;
    final bool isAr = app.isArabic;

    return SafeArea(
      top: false,
      child: RepaintBoundary(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final double maxW = constraints.maxWidth;
            final bool isNarrow = maxW < 360.0;

            final double dockHeight = isNarrow ? 46.0 : 48.0;
            const double dockRadius = 20.0;
            const double hPad = 8.0;
            const double borderW = 1.1;
            const double rightTuck = 4.0;
            final double btnHeight = isNarrow ? 36.0 : 38.0;

            const double protrusion = 4.0;
            final double recHeight = dockHeight + (protrusion * 2.0);
            final double micWidth = isNarrow ? 56.0 : 62.0;

            final double stdBtnWidth =
                isNarrow ? 30.0 : (maxW < 400.0 ? 33.5 : 37.0);
            final double gap = isNarrow ? 2.5 : (maxW < 400.0 ? 3.5 : 5.0);
            final double maglisGap = isNarrow ? 6.0 : 8.0;

            final int recBtnCount = onScreenRecordTap != null ? 3 : 2;
            final double normalWidth = math.min(maxW - 20.0, 460.0);
            final double recordingWidth =
                micWidth + (stdBtnWidth * recBtnCount) + (gap * recBtnCount) + 22.0;

            final double maglisWidth = math.min(maxW - 28.0, 344.0);
            final double maglisRightMargin =
                math.max(14.0, (maxW - maglisWidth) / 2.0);

            final double targetWidth = switch (mode) {
              MicBarMode.recording => recordingWidth,
              MicBarMode.maglis || MicBarMode.maglisRecording => maglisWidth,
              MicBarMode.normal => normalWidth,
            };

            final double normalRightMargin =
                math.max(10.0, (maxW - normalWidth) / 2.0);
            final double rightMargin =
                (mode == MicBarMode.maglis || mode == MicBarMode.maglisRecording)
                    ? maglisRightMargin
                    : normalRightMargin;

            final int normalBtnCount = 2 +
                (onIqroTap != null ? 1 : 0) +
                (onVoiceSearchTap != null ? 1 : 0) +
                (onPlayReciteTap != null ? 1 : 0);
            final double minNormalActionWidth =
                (stdBtnWidth * normalBtnCount) + (gap * normalBtnCount) + 72.0;
            const double minMaglisActionWidth = 220.0;

            final Color pillBg =
                isDark ? const Color(0xF40F151D) : const Color(0xFAFFFFFF);
            final Color pillBorder = isRecording
                ? const Color(0xFFF43F5E)
                    .withValues(alpha: isDark ? 0.42 : 0.30)
                : (isDark
                    ? Colors.white.withValues(alpha: 0.12)
                    : Colors.black.withValues(alpha: 0.08));

            return Padding(
              padding: EdgeInsets.only(
                bottom: 10.0 - protrusion,
                right: rightMargin,
                left: 10.0,
              ),
              child: Align(
                alignment: Alignment.bottomRight,
                child: SizedBox(
                  width: targetWidth,
                  height: recHeight,
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.centerRight,
                    children: [
                      // 1. Floating Capsule Back Chassis
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOutCubic,
                        width: targetWidth,
                        height: dockHeight,
                        margin: const EdgeInsets.only(right: rightTuck),
                        padding: const EdgeInsets.only(left: hPad),
                        decoration: BoxDecoration(
                          color: pillBg,
                          borderRadius: BorderRadius.circular(dockRadius),
                          border: Border.all(
                            color: pillBorder,
                            width: borderW,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: isRecording
                                  ? const Color(0xFFF43F5E).withValues(
                                      alpha: isDark ? 0.22 : 0.12,
                                    )
                                  : Colors.black.withValues(
                                      alpha: isDark ? 0.38 : 0.08,
                                    ),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Directionality(
                          textDirection: TextDirection.rtl,
                          child: Row(
                            children: [
                              SizedBox(
                                width: micWidth - rightTuck - borderW + 4.0,
                              ),
                              SizedBox(
                                width:
                                    (mode == MicBarMode.maglis || mode == MicBarMode.maglisRecording) ? maglisGap : gap,
                              ),
                              Expanded(
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 160),
                                  switchInCurve: Curves.easeOutCubic,
                                  switchOutCurve: Curves.easeInCubic,
                                  layoutBuilder:
                                      (currentChild, previousChildren) {
                                    return Stack(
                                      clipBehavior: Clip.hardEdge,
                                      alignment: Alignment.centerRight,
                                      children: [
                                        ...previousChildren.map(
                                          (w) => IgnorePointer(child: w),
                                        ),
                                        if (currentChild != null) currentChild,
                                      ],
                                    );
                                  },
                                  child: switch (mode) {
                                    // CASE 1: SOLO RECORDING (Compact Tarteel Pill)
                                    MicBarMode.recording =>
                                      SingleChildScrollView(
                                        key: const ValueKey('mode_recording'),
                                        scrollDirection: Axis.horizontal,
                                        physics:
                                            const NeverScrollableScrollPhysics(),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            _buildActionButton(
                                              child: Icon(
                                                isBlur
                                                    ? Icons
                                                        .visibility_off_rounded
                                                    : Icons.visibility_outlined,
                                                size: 19.5,
                                                color: _btnFg(
                                                  isDark,
                                                  isActive: isBlur,
                                                ),
                                              ),
                                              tooltip: isAr
                                                  ? 'إخفاء الآيات'
                                                  : 'Sembunyikan Ayat',
                                              isActive: isBlur,
                                              isDark: isDark,
                                              borderlessWhenInactive: true,
                                              width: stdBtnWidth,
                                              height: btnHeight,
                                              dockHeight: dockHeight,
                                              onTap: onToggleBlur,
                                            ),
                                            SizedBox(width: gap),
                                            _buildActionButton(
                                              child: Icon(
                                                isTajweed
                                                    ? Icons
                                                        .record_voice_over_rounded
                                                    : Icons
                                                        .record_voice_over_outlined,
                                                size: 19.0,
                                                color: _btnFg(
                                                  isDark,
                                                  isActive: isTajweed,
                                                ),
                                              ),
                                              tooltip: isAr
                                                  ? 'أحكام التجويد'
                                                  : 'Pemeriksa Tajwid',
                                              isActive: isTajweed,
                                              isDark: isDark,
                                              borderlessWhenInactive: true,
                                              width: stdBtnWidth,
                                              height: btnHeight,
                                              dockHeight: dockHeight,
                                              onTap: onToggleTajweed,
                                            ),
                                            if (onScreenRecordTap != null) ...[
                                              SizedBox(width: gap),
                                              _buildActionButton(
                                                child: Icon(
                                                  isScreenRecording
                                                      ? Icons.stop_circle_rounded
                                                      : Icons.videocam_outlined,
                                                  size: 20.0,
                                                  color: isScreenRecording
                                                      ? const Color(0xFFE11D48)
                                                      : _btnFg(isDark),
                                                ),
                                                tooltip: app.isIndonesian
                                                    ? (isScreenRecording
                                                        ? 'Hentikan Rekam Layar'
                                                        : 'Rekam Layar & Audio')
                                                    : (isScreenRecording
                                                        ? 'Stop Screen Record'
                                                        : 'Screen Record'),
                                                isActive: isScreenRecording,
                                                isDark: isDark,
                                                borderlessWhenInactive: true,
                                                width: stdBtnWidth,
                                                height: btnHeight,
                                                dockHeight: dockHeight,
                                                onTap: onScreenRecordTap!,
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),

                                    // CASE 2: MAGLIS SESSION (Minimal & Breathable)
                                    MicBarMode.maglis ||
                                    MicBarMode.maglisRecording =>
                                      _NonOverflowingActionRow(
                                        key: const ValueKey('mode_maglis'),
                                        minWidth: minMaglisActionWidth,
                                        child: Row(
                                          children: [
                                            // 1. Quick Reading Tools (Surah, Blur, Tajweed, Settings)
                                            Expanded(
                                              child: Stack(
                                                clipBehavior: Clip.none,
                                                children: [
                                                  _buildActionButton(
                                                    child: Icon(
                                                      Icons.tune_rounded,
                                                      size: 20.0,
                                                      color: isScreenRecording
                                                          ? const Color(0xFFE11D48)
                                                          : _btnFg(
                                                              isDark,
                                                              isActive: isBlur || isTajweed,
                                                            ),
                                                    ),
                                                    tooltip: app.isIndonesian
                                                        ? 'Alat Baca & Surah'
                                                        : (isAr
                                                            ? 'أدوات القراءة والسورة'
                                                            : 'Reading Tools & Surah'),
                                                    isActive: isBlur || isTajweed || isScreenRecording,
                                                    isDark: isDark,
                                                    borderlessWhenInactive: true,
                                                    height: btnHeight,
                                                    dockHeight: dockHeight,
                                                    onTap: () =>
                                                        _showMaglisToolsSheet(context),
                                                  ),
                                                  if (isBlur || isTajweed || isScreenRecording)
                                                    Positioned(
                                                      top: 6,
                                                      right: 6,
                                                      child: Container(
                                                        width: 7,
                                                        height: 7,
                                                        decoration: BoxDecoration(
                                                          color: isScreenRecording
                                                              ? const Color(0xFFE11D48)
                                                              : const Color(0xFF10B981),
                                                          shape: BoxShape.circle,
                                                        ),
                                                      ),
                                                    ),
                                                ],
                                              ),
                                            ),
                                            SizedBox(width: maglisGap),
                                            // 2. Raise Hand / Turn-Taking
                                            Expanded(
                                              child: AnimatedBuilder(
                                                animation: MaglisController.instance,
                                                builder: (context, _) {
                                                  final maglis = MaglisController.instance;
                                                  final bool raised = maglis.isHandRaised;
                                                  final int queueCount = maglis.tadarusQueue.length;
                                                  final bool isMyTurn =
                                                      maglis.nextInQueue == maglis.localPeerId;

                                                  return Stack(
                                                    clipBehavior: Clip.none,
                                                    children: [
                                                      _buildActionButton(
                                                        child: Icon(
                                                          raised
                                                              ? Icons.pan_tool_rounded
                                                              : Icons.pan_tool_outlined,
                                                          size: 19.0,
                                                          color: isMyTurn
                                                              ? const Color(0xFF10B981)
                                                              : (raised
                                                                  ? const Color(0xFFF59E0B)
                                                                  : _btnFg(isDark)),
                                                        ),
                                                        tooltip: app.isIndonesian
                                                            ? (raised
                                                                ? 'Turunkan Tangan (Batal Antre)'
                                                                : 'Angkat Tangan (Antre Giliran)')
                                                            : (isAr
                                                                ? 'رفع اليد للتلاوة'
                                                                : 'Raise Hand to Recite'),
                                                        isActive: raised || isMyTurn,
                                                        isDark: isDark,
                                                        borderlessWhenInactive: true,
                                                        height: btnHeight,
                                                        dockHeight: dockHeight,
                                                        onTap: () {
                                                          maglis.toggleRaiseHand();
                                                        },
                                                      ),
                                                      if (queueCount > 0)
                                                        Positioned(
                                                          top: 3,
                                                          right: 4,
                                                          child: Container(
                                                            padding: const EdgeInsets.all(2.5),
                                                            decoration: BoxDecoration(
                                                              color: isMyTurn
                                                                  ? const Color(0xFF10B981)
                                                                  : const Color(0xFFF59E0B),
                                                              shape: BoxShape.circle,
                                                            ),
                                                            constraints: const BoxConstraints(
                                                                minWidth: 14, minHeight: 14),
                                                            alignment: Alignment.center,
                                                            child: Text(
                                                              '$queueCount',
                                                              style: const TextStyle(
                                                                color: Colors.white,
                                                                fontSize: 8,
                                                                fontWeight: FontWeight.w900,
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                    ],
                                                  );
                                                },
                                              ),
                                            ),
                                            // 3. Pass Turn / Oper Giliran (only when active/queued)
                                            AnimatedBuilder(
                                              animation: MaglisController.instance,
                                              builder: (context, _) {
                                                final maglis = MaglisController.instance;
                                                final bool canPass = isRecording ||
                                                    maglis.isLocalReciting ||
                                                    (maglis.isHost &&
                                                        maglis.tadarusQueue.isNotEmpty);
                                                if (!canPass) return const SizedBox.shrink();

                                                return Container(
                                                  width: stdBtnWidth,
                                                  margin: EdgeInsets.only(right: maglisGap),
                                                  child: _buildActionButton(
                                                    child: const Icon(
                                                      Icons.skip_next_rounded,
                                                      size: 21.0,
                                                      color: Color(0xFF10B981),
                                                    ),
                                                    tooltip: app.isIndonesian
                                                        ? 'Oper Giliran Membaca'
                                                        : (isAr
                                                            ? 'تمرير الدور للتالي'
                                                            : 'Pass Turn to Next'),
                                                    isActive: true,
                                                    isDark: isDark,
                                                    width: stdBtnWidth,
                                                    height: btnHeight,
                                                    dockHeight: dockHeight,
                                                    onTap: () {
                                                      maglis.passTurnToNext();
                                                    },
                                                  ),
                                                );
                                              },
                                            ),
                                            SizedBox(width: maglisGap),
                                            // 4. Majlis Chat
                                            Expanded(
                                              child: ValueListenableBuilder<int>(
                                                valueListenable:
                                                    MaglisController.instance.unreadChatCount,
                                                builder: (context, unreadCount, _) {
                                                  final bool hasUnread = unreadCount > 0;
                                                  return Stack(
                                                    clipBehavior: Clip.none,
                                                    children: [
                                                      _buildActionButton(
                                                        child: Icon(
                                                          Icons.chat_bubble_outline_rounded,
                                                          size: 19.0,
                                                          color: hasUnread
                                                              ? const Color(0xFF10B981)
                                                              : _btnFg(isDark),
                                                        ),
                                                        tooltip: app.isIndonesian
                                                            ? 'Obrolan Majlis'
                                                            : (isAr
                                                                ? 'محادثة المجلس'
                                                                : 'Majlis Chat'),
                                                        isActive: hasUnread,
                                                        isDark: isDark,
                                                        borderlessWhenInactive: true,
                                                        height: btnHeight,
                                                        dockHeight: dockHeight,
                                                        onTap: onMaglisChatTap ?? () {},
                                                      ),
                                                      if (hasUnread)
                                                        Positioned(
                                                          top: 5,
                                                          right: 5,
                                                          child: Container(
                                                            width: 8,
                                                            height: 8,
                                                            decoration: const BoxDecoration(
                                                              color: Color(0xFF10B981),
                                                              shape: BoxShape.circle,
                                                            ),
                                                          ),
                                                        ),
                                                    ],
                                                  );
                                                },
                                              ),
                                            ),
                                            SizedBox(width: maglisGap),
                                            // 5. Leave Majlis (Clean soft-rose button)
                                            Expanded(
                                              child: _buildLeaveButton(
                                                height: btnHeight,
                                                dockHeight: dockHeight,
                                                isDark: isDark,
                                                isAr: isAr,
                                                onTap: onMaglisExitTap ?? () {},
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),

                                    // CASE 3: NORMAL READING (Clean Tarteel AI Style)
                                    MicBarMode.normal =>
                                      _NonOverflowingActionRow(
                                        key: const ValueKey('mode_normal'),
                                        minWidth: minNormalActionWidth,
                                        child: Row(
                                          children: [
                                            _buildMaglisEntryButton(
                                              isDark: isDark,
                                              isAr: isAr,
                                              width: stdBtnWidth,
                                              height: btnHeight,
                                              dockHeight: dockHeight,
                                              showNewBadge:
                                                  app.showMaglisNewBadge,
                                              onTap: onMaglisTap ?? () {},
                                            ),
                                            SizedBox(width: gap),
                                            Expanded(
                                              child: _buildSurahPill(
                                                isDark: isDark,
                                                isAr: isAr,
                                                isNarrow: isNarrow,
                                                height: btnHeight,
                                                dockHeight: dockHeight,
                                              ),
                                            ),
                                            if (onIqroTap != null) ...[
                                              SizedBox(width: gap),
                                              _buildActionButton(
                                                child: Column(
                                                  mainAxisAlignment:
                                                      MainAxisAlignment.center,
                                                  children: [
                                                    Icon(
                                                      Icons.auto_stories_rounded,
                                                      size: 16.5,
                                                      color: _btnFg(
                                                        isDark,
                                                        isActive: isIqroMode,
                                                      ),
                                                    ),
                                                    Text(
                                                      'IQRO',
                                                      style: TextStyle(
                                                        fontFamily: 'cairo',
                                                        fontSize: 7.5,
                                                        height: 1.0,
                                                        fontWeight:
                                                            FontWeight.w800,
                                                        color: _btnFg(
                                                          isDark,
                                                          isActive: isIqroMode,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                tooltip: isAr
                                                    ? 'تعلم اقرأ (١-٦)'
                                                    : "Belajar Iqro' (Jilid 1–6)",
                                                isActive: isIqroMode,
                                                isDark: isDark,
                                                borderlessWhenInactive: true,
                                                width: stdBtnWidth,
                                                height: btnHeight,
                                                dockHeight: dockHeight,
                                                onTap: onIqroTap!,
                                              ),
                                            ],
                                            if (onVoiceSearchTap != null) ...[
                                              SizedBox(width: gap),
                                              _buildActionButton(
                                                child: SizedBox(
                                                  width: 22,
                                                  height: 22,
                                                  child: Stack(
                                                    clipBehavior: Clip.none,
                                                    alignment: Alignment.center,
                                                    children: [
                                                      Icon(
                                                        Icons.search_rounded,
                                                        size: 20.0,
                                                        color: _btnFg(
                                                          isDark,
                                                          isActive:
                                                              isVoiceSearching,
                                                        ),
                                                      ),
                                                      Positioned(
                                                        right: -1,
                                                        bottom: 0,
                                                        child: Container(
                                                          padding:
                                                              const EdgeInsets
                                                                  .all(1),
                                                          decoration:
                                                              BoxDecoration(
                                                            color: isDark
                                                                ? const Color(
                                                                    0xFF0F151D)
                                                                : Colors.white,
                                                            shape:
                                                                BoxShape.circle,
                                                          ),
                                                          child: const Icon(
                                                            Icons.mic_rounded,
                                                            size: 9.5,
                                                            color: Color(
                                                                0xFF10B981),
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                tooltip: app.isIndonesian
                                                    ? 'Cari Ayat dengan Suara'
                                                    : (isAr
                                                        ? 'البحث الصوتي عن الآية'
                                                        : 'Voice Verse Search'),
                                                isActive: isVoiceSearching,
                                                isDark: isDark,
                                                borderlessWhenInactive: true,
                                                width: stdBtnWidth,
                                                height: btnHeight,
                                                dockHeight: dockHeight,
                                                onTap: onVoiceSearchTap!,
                                              ),
                                            ],
                                            if (onPlayReciteTap != null) ...[
                                              SizedBox(width: gap),
                                              ListenableBuilder(
                                                listenable: Listenable.merge([
                                                  QuranAudioService
                                                      .instance.isPlayingNotifier,
                                                  IqroAudioService
                                                      .instance.isPlayingNotifier,
                                                ]),
                                                builder: (context, _) {
                                                  final isPlaying = isIqroMode
                                                      ? IqroAudioService.instance
                                                          .isPlayingNotifier.value
                                                      : QuranAudioService.instance
                                                          .isPlayingNotifier.value;
                                                  return _buildActionButton(
                                                    child: Icon(
                                                      isPlaying
                                                          ? Icons.pause_rounded
                                                          : Icons
                                                              .play_arrow_rounded,
                                                      size: 22.0,
                                                      color: isPlaying
                                                          ? const Color(
                                                              0xFF10B981)
                                                          : _btnFg(isDark),
                                                    ),
                                                    tooltip: isIqroMode
                                                        ? (isPlaying
                                                            ? 'Hentikan Audio Iqro'
                                                            : 'Putar Lafal Iqro')
                                                        : (isPlaying
                                                            ? 'Jeda Murottal'
                                                            : 'Putar Murottal'),
                                                    isActive: isPlaying,
                                                    isDark: isDark,
                                                    borderlessWhenInactive:
                                                        true,
                                                    width: stdBtnWidth,
                                                    height: btnHeight,
                                                    dockHeight: dockHeight,
                                                    onTap: onPlayReciteTap!,
                                                  );
                                                },
                                              ),
                                            ],
                                            SizedBox(width: gap),
                                            _buildActionButton(
                                              child: Icon(
                                                Icons.tune_rounded,
                                                size: 19.5,
                                                color: _btnFg(isDark),
                                              ),
                                              tooltip: isAr
                                                  ? 'الإعدادات'
                                                  : 'Pengaturan',
                                              isActive: false,
                                              isDark: isDark,
                                              borderlessWhenInactive: true,
                                              width: stdBtnWidth,
                                              height: btnHeight,
                                              dockHeight: dockHeight,
                                              onTap: onSettingsTap,
                                            ),
                                          ],
                                        ),
                                      ),
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // 2. Protruding Hero Record Key (Flush with right edge)
                      Positioned(
                        top: 0.0,
                        bottom: 0.0,
                        right: 0.0,
                        child: _buildMicButton(
                          width: micWidth,
                          height: recHeight,
                          isDark: isDark,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildMicButton({
    required double width,
    required double height,
    required bool isDark,
  }) {
    final List<Color> gradient = isRecording
        ? const [Color(0xFFFF3B6B), Color(0xFFE11D48)]
        : const [Color(0xFF10B981), Color(0xFF059669)];

    return _TapScale(
      onTap: onMic,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18.0),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: gradient,
          ),
          border: Border.all(
            color: Colors.white.withValues(alpha: isDark ? 0.40 : 0.65),
            width: 1.3,
          ),
          boxShadow: [
            BoxShadow(
              color: gradient[0].withValues(alpha: isDark ? 0.38 : 0.25),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: isLoadingEngine
            ? ValueListenableBuilder<ModelDownloadProgress>(
                valueListenable: AppState.instance.modelDownloadNotifier,
                builder: (context, dl, _) {
                  final bool hasProgress =
                      dl.isDownloading && dl.loadedBytes > 0;
                  final double? progressVal =
                      hasProgress ? dl.progress.clamp(0.0, 1.0) : null;
                  final String pctText = '${dl.percent}%';
                  final String mbText = '${dl.loadedMB.toInt()}/71 MB';

                  return FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Stack(
                            alignment: Alignment.center,
                            children: [
                              SizedBox(
                                width: 21,
                                height: 21,
                                child: CircularProgressIndicator(
                                  value: progressVal,
                                  strokeWidth: 2.1,
                                  color: Colors.white,
                                  backgroundColor:
                                      Colors.white.withValues(alpha: 0.25),
                                ),
                              ),
                              if (hasProgress)
                                Text(
                                  pctText,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 7.5,
                                    fontWeight: FontWeight.w900,
                                    letterSpacing: -0.5,
                                  ),
                                ),
                            ],
                          ),
                          if (hasProgress) ...[
                            const SizedBox(height: 2),
                            Text(
                              mbText,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 8.0,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.2,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              )
            : (isRecording
                ? const _AudioWaveform()
                : const Icon(
                    Icons.mic_rounded,
                    color: Colors.white,
                    size: 26.0,
                  )),
      ),
    );
  }

  Widget _buildActionButton({
    required Widget child,
    required String tooltip,
    required bool isActive,
    required bool isDark,
    bool borderlessWhenInactive = false,
    double? width,
    required double height,
    required double dockHeight,
    required VoidCallback onTap,
  }) {
    final bool showBox = isActive || !borderlessWhenInactive;
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 350),
      child: _TapScale(
        onTap: onTap,
        child: SizedBox(
          width: width,
          height: dockHeight,
          child: Center(
            child: Container(
              width: width ?? double.infinity,
              height: height,
              decoration: BoxDecoration(
                color: showBox ? _btnBg(isDark, isActive: isActive) : Colors.transparent,
                borderRadius: BorderRadius.circular(10.0),
                border: showBox
                    ? Border.all(
                        color: _btnBorder(isDark, isActive: isActive),
                        width: isActive ? 1.2 : 1.0,
                      )
                    : null,
              ),
              alignment: Alignment.center,
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  void _showMaglisToolsSheet(BuildContext context) {
    final app = AppState.instance;
    final bool isDark = app.isDarkMode;
    final bool isId = app.isIndonesian;
    final bool isAr = app.isArabic;
    final sr = ScreenRecordingService.instance;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return ListenableBuilder(
          listenable: Listenable.merge([
            app.blurModeNotifier,
            app.modeNotifier,
            sr.isRecordingNotifier,
            sr.elapsedSecondsNotifier,
            sr.recordingsNotifier,
            sr.totalBytesNotifier,
            sr.isLiveStreamingNotifier,
            sr.liveElapsedSecondsNotifier,
          ]),
          builder: (_, __) {
            final bool blurActive = app.isBlurMode;
            final bool tajweedActive = app.currentMode == AppMode.tajweed;
            final bool screenRecActive = sr.isRecordingNotifier.value;
            final bool liveActive = sr.isLiveStreamingNotifier.value;
            final int elapsedSec = sr.elapsedSecondsNotifier.value;
            final int liveSec = sr.liveElapsedSecondsNotifier.value;
            final int savedCount = sr.recordingsNotifier.value.length;
            final String savedSize =
                SavedScreenRecording.formatBytes(sr.totalBytesNotifier.value);
            final Color surface =
                isDark ? const Color(0xFF131922) : Colors.white;
            final Color border = isDark
                ? Colors.white.withValues(alpha: 0.10)
                : Colors.black.withValues(alpha: 0.08);
            final Color textCol =
                isDark ? const Color(0xFFF1F5F9) : const Color(0xFF0F172A);
            final Color subCol =
                isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

            return Container(
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 16),
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(sheetCtx).height * 0.78,
              ),
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: border),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.12),
                    blurRadius: 24,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        color: subCol.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    if (MaglisController.instance.inSession) ...[
                      _buildToolsTile(
                        icon: Icons.share_rounded,
                        title: isId
                            ? 'Undang Teman (Salin / Bagikan Link)'
                            : (isAr ? 'دعوة للمجلس (مشاركة الرابط)' : 'Invite Friends (Share Link)'),
                        subtitle: isId
                            ? 'Bisa dibuka di HP/Laptop via browser (https://ngabar.vercel.app)'
                            : 'Open via browser without installing app',
                        isDark: isDark,
                        textCol: textCol,
                        subCol: subCol,
                        onTap: () async {
                          Navigator.of(sheetCtx).pop();
                          final code = MaglisController.instance.roomCode;
                          final inviteText = MaglisLinkService.formatInviteText(
                            code,
                            isArabic: isAr,
                            isIndonesian: isId,
                          );
                          final subject = isId
                              ? 'Undangan Majelis Ngaji Bareng (ngabar)'
                              : 'Quran Majlis Invitation';
                          try {
                            await SharePlus.instance.share(ShareParams(
                              text: inviteText,
                              subject: subject,
                              title: subject,
                            ));
                          } catch (_) {
                            final link = MaglisLinkService.formatUrl(code);
                            Clipboard.setData(ClipboardData(text: link));
                            AppState.instance.showBanner(AppBannerInfo(
                              id: 'maglis_link_copied',
                              messageAr: 'تم نسخ رابط المجلس: $link',
                              messageEn: 'Majlis link copied: $link',
                              messageId: 'Tautan Majelis disalin: $link',
                              icon: Icons.link_rounded,
                              customDuration: const Duration(seconds: 2),
                            ));
                          }
                        },
                      ),
                      const SizedBox(height: 8),
                    ],
                    _buildToolsTile(
                      icon: Icons.menu_book_rounded,
                      title: isId
                          ? 'Pilih Surah'
                          : (isAr ? 'اختيار السورة' : 'Select Surah'),
                      subtitle: surahName,
                      isDark: isDark,
                      textCol: textCol,
                      subCol: subCol,
                      onTap: () {
                        Navigator.of(sheetCtx).pop();
                        onSurahTap();
                      },
                    ),
                    const SizedBox(height: 8),
                    _buildToolsTile(
                      icon: Icons.auto_stories_rounded,
                      title: isId
                          ? "Buka Belajar Iqro' (Jilid 1–6)"
                          : (isAr ? 'فتح تعلم اقرأ (١-٦)' : "Open Iqro' (1–6)"),
                      subtitle: isId
                          ? 'Belajar huruf Hijaiyah interaktif dengan pengenalan suara AI'
                          : 'Learn Hijaiyah letters with AI voice matching',
                      isDark: isDark,
                      textCol: textCol,
                      subCol: subCol,
                      onTap: () {
                        Navigator.of(sheetCtx).pop();
                        IqroPickerSheet.show(context);
                      },
                    ),
                    const SizedBox(height: 8),
                    if (onScreenRecordTap != null) ...[
                      _buildToolsTile(
                        icon: screenRecActive
                            ? Icons.stop_circle_rounded
                            : Icons.videocam_rounded,
                        title: isId
                            ? (screenRecActive
                                ? 'Hentikan Rekam Layar'
                                : 'Rekam Layar Majlis')
                            : (screenRecActive
                                ? 'Stop Screen Recording'
                                : 'Record Majlis Screen'),
                        subtitle: screenRecActive
                            ? (isId
                                ? 'Sedang merekam · ${SavedScreenRecording.formatDuration(elapsedSec * 1000)}'
                                : 'Recording · ${SavedScreenRecording.formatDuration(elapsedSec * 1000)}')
                            : (isId
                                ? 'Simpan video mushaf & suara sesi Majlis'
                                : 'Save mushaf video & Majlis audio'),
                        isActive: screenRecActive,
                        isDark: isDark,
                        textCol: textCol,
                        subCol: subCol,
                        onTap: () {
                          Navigator.of(sheetCtx).pop();
                          onScreenRecordTap!();
                        },
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (onOpenRecordingsTap != null) ...[
                      _buildToolsTile(
                        icon: Icons.video_library_rounded,
                        title: isId
                            ? 'Hasil Rekaman & Storage'
                            : 'Saved Recordings & Storage',
                        subtitle: savedCount == 0
                            ? (isId ? 'Belum ada video' : 'No videos yet')
                            : (isId
                                ? '$savedCount video · $savedSize'
                                : '$savedCount videos · $savedSize'),
                        isDark: isDark,
                        textCol: textCol,
                        subCol: subCol,
                        onTap: () {
                          Navigator.of(sheetCtx).pop();
                          onOpenRecordingsTap!();
                        },
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (sr.isSupported) ...[
                      _buildToolsTile(
                        icon: Icons.sensors_rounded,
                        title: isId
                            ? (liveActive
                                ? 'Live Streaming Aktif'
                                : 'Live Streaming (YT / FB)')
                            : (liveActive
                                ? 'Live Stream Active'
                                : 'Live Stream (YT / FB)'),
                        subtitle: liveActive
                            ? 'LIVE · ${SavedScreenRecording.formatDuration(liveSec * 1000)}'
                            : (isId
                                ? 'Siaran langsung via RTMP • Encoder Aman AI'
                                : 'Broadcast via RTMP • AI-Safe Encoder'),
                        isActive: liveActive,
                        isDark: isDark,
                        textCol: textCol,
                        subCol: subCol,
                        onTap: () {
                          Navigator.of(sheetCtx).pop();
                          LiveStreamSheet.show(
                            context,
                            surahName: surahName,
                            isExternalMicActive: isRecording || isVoiceSearching,
                          );
                        },
                      ),
                      const SizedBox(height: 8),
                    ],
                    _buildToolsTile(
                      icon: blurActive
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                      title: isId
                          ? 'Sembunyikan Ayat (Hafalan)'
                          : (isAr ? 'إخفاء الآيات (للحفظ)' : 'Hide Verses (Hifz)'),
                      subtitle: isId
                          ? (blurActive ? 'Aktif — ayat disamarkan' : 'Nonaktif')
                          : (blurActive ? 'Active' : 'Off'),
                      isActive: blurActive,
                      isDark: isDark,
                      textCol: textCol,
                      subCol: subCol,
                      trailing: Switch.adaptive(
                        value: blurActive,
                        activeTrackColor: const Color(0xFF10B981),
                        onChanged: (_) => onToggleBlur(),
                      ),
                      onTap: onToggleBlur,
                    ),
                    const SizedBox(height: 8),
                    _buildToolsTile(
                      icon: tajweedActive
                          ? Icons.record_voice_over_rounded
                          : Icons.record_voice_over_outlined,
                      title: isId
                          ? 'Pemeriksa Tajwid'
                          : (isAr ? 'مدقق التجويد' : 'Tajweed Checker'),
                      subtitle: isId
                          ? (tajweedActive
                              ? 'Aktif — tandai makhraj & mad'
                              : 'Nonaktif')
                          : (tajweedActive ? 'Active' : 'Off'),
                      isActive: tajweedActive,
                      isDark: isDark,
                      textCol: textCol,
                      subCol: subCol,
                      trailing: Switch.adaptive(
                        value: tajweedActive,
                        activeTrackColor: const Color(0xFF10B981),
                        onChanged: (_) => onToggleTajweed(),
                      ),
                      onTap: onToggleTajweed,
                    ),
                    const SizedBox(height: 8),
                    _buildToolsTile(
                      icon: Icons.settings_outlined,
                      title: isId
                          ? 'Pengaturan Tampilan & Audio'
                          : (isAr ? 'الإعدادات' : 'Settings'),
                      isDark: isDark,
                      textCol: textCol,
                      subCol: subCol,
                      onTap: () {
                        Navigator.of(sheetCtx).pop();
                        onSettingsTap();
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildToolsTile({
    required IconData icon,
    required String title,
    String? subtitle,
    bool isActive = false,
    required bool isDark,
    required Color textCol,
    required Color subCol,
    Widget? trailing,
    required VoidCallback onTap,
  }) {
    const Color emerald = Color(0xFF10B981);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isActive
                ? emerald.withValues(alpha: isDark ? 0.14 : 0.08)
                : (isDark
                    ? Colors.white.withValues(alpha: 0.04)
                    : Colors.black.withValues(alpha: 0.025)),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isActive
                  ? emerald.withValues(alpha: 0.45)
                  : (isDark
                      ? Colors.white.withValues(alpha: 0.07)
                      : Colors.black.withValues(alpha: 0.05)),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: (isActive ? emerald : subCol)
                      .withValues(alpha: isDark ? 0.18 : 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: Icon(
                  icon,
                  size: 18,
                  color: isActive ? emerald : textCol,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        color: textCol,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (subtitle != null && subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        style: TextStyle(
                          color: subCol,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                  ],
                ),
              ),
              trailing ??
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: subCol,
                  ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLeaveButton({
    required double height,
    required double dockHeight,
    required bool isDark,
    required bool isAr,
    required VoidCallback onTap,
  }) {
    const Color rose = Color(0xFFF43F5E);
    return Tooltip(
      message: isAr ? 'مغادرة المجلس' : 'Keluar Majlis',
      waitDuration: const Duration(milliseconds: 350),
      child: _TapScale(
        onTap: onTap,
        child: SizedBox(
          height: dockHeight,
          child: Center(
            child: Container(
              width: double.infinity,
              height: height,
              decoration: BoxDecoration(
                color: rose.withValues(alpha: isDark ? 0.22 : 0.13),
                borderRadius: BorderRadius.circular(10.0),
                border: Border.all(
                  color: rose.withValues(alpha: isDark ? 0.45 : 0.35),
                  width: 1.0,
                ),
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.call_end_rounded,
                size: 18.5,
                color: rose,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMaglisEntryButton({
    required bool isDark,
    required bool isAr,
    required double width,
    required double height,
    required double dockHeight,
    required bool showNewBadge,
    required VoidCallback onTap,
  }) {
    final isId = AppState.instance.isIndonesian;
    final tooltip =
        isId ? 'Majlis Ngaji Bareng' : (isAr ? 'مجلس القرآن' : 'Quran Majlis');
    const Color warmGold = Color(0xFFD97706);

    final btn = Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 350),
      child: _TapScale(
        onTap: onTap,
        child: SizedBox(
          width: width,
          height: dockHeight,
          child: Center(
            child: Container(
              width: width,
              height: height,
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFFF59E0B).withValues(alpha: 0.14)
                    : const Color(0xFFF59E0B).withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12.0),
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.groups_rounded,
                size: 21.0,
                color: isDark ? const Color(0xFFFBBF24) : warmGold,
              ),
            ),
          ),
        ),
      ),
    );

    if (!showNewBadge) return btn;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        btn,
        Positioned(
          top: 4.0,
          right: isAr ? 2.0 : null,
          left: isAr ? null : 2.0,
          child: IgnorePointer(
            child: Container(
              width: 8.0,
              height: 8.0,
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B),
                shape: BoxShape.circle,
                border: Border.all(
                  color: isDark ? const Color(0xFF0F151D) : Colors.white,
                  width: 1.3,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSurahPill({
    required bool isDark,
    required bool isAr,
    required bool isNarrow,
    required double height,
    required double dockHeight,
  }) {
    final Color fgColor = _btnFg(isDark);
    final Color effectiveFg = isIqroMode
        ? (isDark ? const Color(0xFF34D399) : const Color(0xFF047857))
        : fgColor;

    return _TapScale(
      onTap: onSurahTap,
      child: SizedBox(
        height: dockHeight,
        child: Center(
          child: Container(
            height: height,
            padding: EdgeInsets.symmetric(horizontal: isNarrow ? 8.0 : 11.0),
            decoration: BoxDecoration(
              color: isIqroMode
                  ? const Color(0xFF10B981)
                      .withValues(alpha: isDark ? 0.16 : 0.10)
                  : (isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.black.withValues(alpha: 0.045)),
              borderRadius: BorderRadius.circular(14.0),
              border: isIqroMode
                  ? Border.all(
                      color: const Color(0xFF10B981)
                          .withValues(alpha: isDark ? 0.45 : 0.35),
                      width: 1.0,
                    )
                  : null,
            ),
            child: Row(
              children: [
                if (isIqroMode)
                  Icon(
                    Icons.auto_stories_rounded,
                    size: isNarrow ? 15.5 : 16.5,
                    color: const Color(0xFF10B981),
                  )
                else
                  _EmptyMushafIcon(
                    size: isNarrow ? 16.0 : 17.0,
                    color: isDark
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF64748B),
                  ),
                SizedBox(width: isNarrow ? 5.0 : 7.0),
                Expanded(
                  child: Text(
                    surahName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'cairo',
                      color: effectiveFg,
                      fontSize: isNarrow ? 12.0 : (isAr ? 13.5 : 13.0),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: isIqroMode
                      ? const Color(0xFF10B981)
                      : (isDark
                          ? const Color(0xFF94A3B8)
                          : const Color(0xFF64748B)),
                  size: isNarrow ? 16.0 : 17.5,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Prevents RenderFlex Overflow During Collapse / Decollapse Width Transitions
// ─────────────────────────────────────────────────────────────────────────────
class _NonOverflowingActionRow extends StatelessWidget {
  final double minWidth;
  final Widget child;

  const _NonOverflowingActionRow({
    super.key,
    required this.minWidth,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= minWidth) {
          return child;
        }
        return ClipRect(
          child: OverflowBox(
            minWidth: minWidth,
            maxWidth: minWidth,
            alignment: Alignment.centerRight,
            child: SizedBox(
              width: minWidth,
              child: child,
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty Open Mushaf Vector Icon (No inner lines)
// ─────────────────────────────────────────────────────────────────────────────
class _EmptyMushafIcon extends StatelessWidget {
  final double size;
  final Color color;

  const _EmptyMushafIcon({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _EmptyMushafPainter(color)),
    );
  }
}

class _EmptyMushafPainter extends CustomPainter {
  final Color color;
  _EmptyMushafPainter(this.color);

  final Paint _paint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round
    ..isAntiAlias = true;

  final Path _path = Path();

  @override
  void paint(Canvas canvas, Size size) {
    final double w = size.width;
    final double h = size.height;
    _paint
      ..color = color
      ..strokeWidth = w * 0.095;

    _path.reset();
    _path
      ..moveTo(w * 0.50, h * 0.25)
      ..quadraticBezierTo(w * 0.31, h * 0.17, w * 0.12, h * 0.23)
      ..lineTo(w * 0.12, h * 0.75)
      ..quadraticBezierTo(w * 0.31, h * 0.69, w * 0.50, h * 0.79)
      ..moveTo(w * 0.50, h * 0.25)
      ..quadraticBezierTo(w * 0.69, h * 0.17, w * 0.88, h * 0.23)
      ..lineTo(w * 0.88, h * 0.75)
      ..quadraticBezierTo(w * 0.69, h * 0.69, w * 0.50, h * 0.79);

    canvas.drawPath(_path, _paint);
    canvas.drawLine(
      Offset(w * 0.50, h * 0.25),
      Offset(w * 0.50, h * 0.80),
      _paint,
    );
  }

  @override
  bool shouldRepaint(covariant _EmptyMushafPainter old) => old.color != color;
}

// ─────────────────────────────────────────────────────────────────────────────
// Smooth 4-Bar Audio Waveform
// ─────────────────────────────────────────────────────────────────────────────
class _AudioWaveform extends StatefulWidget {
  const _AudioWaveform();

  @override
  State<_AudioWaveform> createState() => _AudioWaveformState();
}

class _AudioWaveformState extends State<_AudioWaveform>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  bool _isCurrentRoute = true;
  Animation<double>? _secondaryAnimation;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    if (!AppModalRouteObserver.instance.isModalOpen) {
      _ctrl.repeat();
    }
    AppModalRouteObserver.instance.activeModalsNotifier
        .addListener(_onModalStateChanged);
  }

  void _onModalStateChanged() {
    if (!mounted) return;
    _syncAnimationState();
  }

  void _syncAnimationState() {
    final bool isModalOpen = AppModalRouteObserver.instance.isModalOpen;
    final bool isCovered = !_isCurrentRoute ||
        isModalOpen ||
        (_secondaryAnimation != null && !_secondaryAnimation!.isDismissed);

    if (isCovered) {
      if (_ctrl.isAnimating) _ctrl.stop();
    } else {
      if (!_ctrl.isAnimating) _ctrl.repeat();
    }
  }

  void _onSecondaryStatus(AnimationStatus status) {
    if (!mounted) return;
    _syncAnimationState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    final isCurrent = route?.isCurrent ?? true;
    _isCurrentRoute = isCurrent;

    final newSecondary = route?.secondaryAnimation;
    if (newSecondary != _secondaryAnimation) {
      _secondaryAnimation?.removeStatusListener(_onSecondaryStatus);
      _secondaryAnimation = newSecondary;
      _secondaryAnimation?.addStatusListener(_onSecondaryStatus);
    }

    _syncAnimationState();
  }

  @override
  void dispose() {
    AppModalRouteObserver.instance.activeModalsNotifier
        .removeListener(_onModalStateChanged);
    _secondaryAnimation?.removeStatusListener(_onSecondaryStatus);
    _secondaryAnimation = null;
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox(
        width: 24,
        height: 18,
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) =>
              CustomPaint(painter: _WaveformPainter(_ctrl.value)),
        ),
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final double progress;
  _WaveformPainter(this.progress);

  static final Paint _paint = Paint()..color = Colors.white;

  @override
  void paint(Canvas canvas, Size size) {
    final double t = progress * 2.0 * math.pi;
    const double barW = 2.6;
    const double gap = 2.6;
    double x = (size.width - (4 * barW + 3 * gap)) / 2.0;
    final double cy = size.height / 2.0;

    void drawBar(double h) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, cy - h / 2.0, barW, h),
          const Radius.circular(1.3),
        ),
        _paint,
      );
      x += barW + gap;
    }

    drawBar(6.0 + 3.0 * math.sin(t));
    drawBar(10.0 + 4.5 * math.sin(t + 1.4));
    drawBar(9.5 + 4.0 * math.sin(t + 2.8));
    drawBar(6.5 + 3.0 * math.sin(t + 4.2));
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter old) =>
      old.progress != progress;
}

// ─────────────────────────────────────────────────────────────────────────────
// Robust Touch Handler with Tap Animation
// ─────────────────────────────────────────────────────────────────────────────
class _TapScale extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;

  const _TapScale({
    super.key,
    required this.child,
    required this.onTap,
  });

  @override
  State<_TapScale> createState() => _TapScaleState();
}

class _TapScaleState extends State<_TapScale> {
  final ValueNotifier<bool> _down = ValueNotifier<bool>(false);

  @override
  void dispose() {
    _down.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _down.value = true,
      onTapUp: (_) => _down.value = false,
      onTapCancel: () => _down.value = false,
      onTap: widget.onTap,
      child: ValueListenableBuilder<bool>(
        valueListenable: _down,
        builder: (context, isDown, child) {
          return AnimatedScale(
            scale: isDown ? 0.94 : 1.0,
            duration: const Duration(milliseconds: 60),
            curve: Curves.easeOutCubic,
            child: child,
          );
        },
        child: widget.child,
      ),
    );
  }
}
