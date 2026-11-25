import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../audio/camcorder_sound_helper.dart';
import '../../../audio/quran_download_service.dart';
import '../../../audio/quran_audio_service.dart';
import '../../../audio/screen_recording_service.dart';
import '../../../core/app_state.dart';
import '../../../core/highlighting_controller.dart';
import 'dialog_service.dart';

// ══════════════════════════════════════════════════════════════════════════════
// 1. SETTINGS TILE & DIVIDER
// ══════════════════════════════════════════════════════════════════════════════

/// Thin flush separator line for grouped lists.
class SettingDivider extends StatelessWidget {
  final ThemeColors c;
  const SettingDivider({super.key, required this.c});

  @override
  Widget build(BuildContext context) {
    final isDark = AppState.instance.isDarkMode;
    return Container(
      height: 1,
      margin: const EdgeInsetsDirectional.only(start: 56, end: 16),
      color: isDark
          ? Colors.white.withValues(alpha: 0.06)
          : Colors.black.withValues(alpha: 0.05),
    );
  }
}

/// Minimalist setting row tile that handles trailing controls and sub-sliders.
class SettingTile extends StatelessWidget {
  final IconData? icon;
  final Widget? iconWidget;
  final String title;
  final ThemeColors c;
  final Widget? trailing;
  final Widget? bottom;
  final Widget? badge;
  final double? trailingWidth;
  final VoidCallback? onTap;

  const SettingTile({
    super.key,
    this.icon,
    this.iconWidget,
    required this.title,
    required this.c,
    this.trailing,
    this.bottom,
    this.badge,
    this.trailingWidth,
    this.onTap,
  }) : assert(icon != null || iconWidget != null,
            'Either icon or iconWidget must be provided');

  @override
  Widget build(BuildContext context) {
    final isDark = AppState.instance.isDarkMode;

    final content = Padding(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981)
                      .withValues(alpha: isDark ? 0.14 : 0.09),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: const Color(0xFF10B981)
                        .withValues(alpha: isDark ? 0.28 : 0.20),
                    width: 1,
                  ),
                ),
                child: iconWidget ??
                    (icon != null
                        ? Icon(icon, color: const Color(0xFF10B981), size: 20)
                        : const SizedBox.shrink()),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        style: TextStyle(
                          color: c.text,
                          fontSize: 16.5,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.1,
                        ),
                      ),
                      if (badge != null) ...[
                        const SizedBox(width: 6),
                        badge!,
                      ],
                    ],
                  ),
                ),
              ),
              if (trailing != null) ...[
                const SizedBox(width: 12),
                if (trailingWidth != null)
                  SizedBox(width: trailingWidth, child: trailing!)
                else if (trailing is AppSegmentedPillSelector)
                  SizedBox(width: 122, child: trailing!)
                else if (trailing is Row)
                  SizedBox(width: 130, child: trailing!)
                else
                  trailing!,
              ],
            ],
          ),
          if (bottom != null) ...[
            const SizedBox(height: 14),
            bottom!,
          ],
        ],
      ),
    );

    if (onTap != null) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: content,
        ),
      );
    }
    return content;
  }
}

/// Offline Quran Recitation & Timings download tile for settings.
class QuranDownloadTile extends StatelessWidget {
  final ThemeColors c;
  final bool isAr;
  final bool isDark;

  const QuranDownloadTile({
    super.key,
    required this.c,
    required this.isAr,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        QuranDownloadService.instance.isDownloading,
        QuranDownloadService.instance.progress,
      ]),
      builder: (context, _) {
        final isDownloading = QuranDownloadService.instance.isDownloading.value;
        final progress = QuranDownloadService.instance.progress.value;
        final percent = (progress * 100).toInt();

        final app = AppState.instance;
        final isId = app.isIndonesian;
        return SettingTile(
          icon: Icons.cloud_download_rounded,
          title: isId ? 'Unduh Audio Tilawah' : 'Download Recitation Audio',
          c: c,
          onTap: () {
            Navigator.of(context).pop();
            AudioDownloadDialog.show(context);
          },
          trailing: isDownloading
              ? Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: c.primary.withValues(alpha: isDark ? 0.20 : 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: c.primary.withValues(alpha: isDark ? 0.40 : 0.25),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 12,
                        height: 12,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          value: progress.clamp(0.0, 1.0),
                          valueColor: AlwaysStoppedAnimation<Color>(c.primary),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isAr ? '${QuranTypography.toArabicDigits(percent)}٪' : '$percent%',
                        style: TextStyle(
                          fontFamily: 'cairo',
                          color: c.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                )
              : Icon(
                  Icons.arrow_forward_ios_rounded,
                  size: 15,
                  color: c.muted,
                ),
        );
      },
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// 2. SETTINGS MODAL BOTTOM SHEET
// ══════════════════════════════════════════════════════════════════════════════

/// Settings modal bottom sheet with modern styling and responsive reactivity.
class SettingsSheet extends StatelessWidget {
  const SettingsSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return AppBottomSheet(
      maxHeightFactor: 0.75,
      extraListenable: AppState.instance.mushafModeNotifier,
      headerBuilder: (context, c, isAr, isDark) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 2, 20, 4),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFF10B981)
                .withValues(alpha: isDark ? 0.08 : 0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: const Color(0xFF10B981)
                  .withValues(alpha: isDark ? 0.22 : 0.15),
              width: 0.8,
            ),
          ),
          child: Center(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                'بفضل الله وبرحمته ربنا تقبل منا إنك أنت السميع العليم',
                maxLines: 1,
                softWrap: false,
                textAlign: TextAlign.center,
                textDirection: TextDirection.rtl,
                style: const TextStyle(
                  color: Color(0xFF10B981),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  height: 1.25,
                ),
              ),
            ),
          ),
        ),
      ),
      builder: (context, c, isAr, isDark) {
        final app = AppState.instance;
        final isId = app.isIndonesian;
        return SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 14),

              // ── Application Preferences Card ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.05)
                        : Colors.black.withValues(alpha: 0.035),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.black.withValues(alpha: 0.06),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                            alpha: isDark ? 0.25 : 0.03),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // 1. Language
                      SettingTile(
                        icon: Icons.language_rounded,
                        title: app.isIndonesian ? 'Bahasa' : 'Language',
                        c: c,
                        trailing: AppSegmentedPillSelector(
                          labels: const ['Indonesia', 'English'],
                          selected: app.lang == AppLanguage.id ? 0 : 1,
                          c: c,
                          onSelected: (i) {
                            app.setLanguage(i == 0 ? AppLanguage.id : AppLanguage.en);
                          },
                        ),
                      ),
                      SettingDivider(c: c),

                      // 2. Theme
                      SettingTile(
                        icon: Icons.palette_rounded,
                        title: app.isIndonesian ? 'Tema' : 'Theme',
                        c: c,
                        trailing: AppSegmentedPillSelector(
                          labels: app.isIndonesian
                              ? const ['Terang', 'Gelap']
                              : const ['Light', 'Dark'],
                          selected: app.theme.index,
                          c: c,
                          onSelected: (i) =>
                              app.setTheme(AppTheme.values[i]),
                        ),
                      ),
                      SettingDivider(c: c),

                      // 3. Offline Audio & Timing Download
                      QuranDownloadTile(c: c, isAr: isAr, isDark: isDark),

                      // 3b. Rekaman Layar & Penyimpanan
                      SettingDivider(c: c),
                      ListenableBuilder(
                        listenable: Listenable.merge([
                          ScreenRecordingService.instance.recordingsNotifier,
                          ScreenRecordingService.instance.totalBytesNotifier,
                        ]),
                        builder: (context, _) {
                          final recs = ScreenRecordingService
                              .instance.recordingsNotifier.value;
                          final bytes = ScreenRecordingService
                              .instance.totalBytesNotifier.value;
                          final sizeStr =
                              SavedScreenRecording.formatBytes(bytes);
                          return SettingTile(
                            icon: Icons.video_library_rounded,
                            title: isId
                                ? 'Rekaman Layar & Storage'
                                : 'Screen Recordings & Storage',
                            c: c,
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 9, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981)
                                    .withValues(alpha: isDark ? 0.18 : 0.10),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: const Color(0xFF10B981)
                                      .withValues(alpha: isDark ? 0.35 : 0.22),
                                ),
                              ),
                              child: Text(
                                recs.isEmpty
                                    ? (isId ? 'Kosong' : 'Empty')
                                    : '${recs.length} · $sizeStr',
                                style: const TextStyle(
                                  color: Color(0xFF10B981),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            onTap: () {
                              Navigator.of(context).pop();
                              DialogService.showScreenRecordings(context);
                            },
                          );
                        },
                      ),

                      // 4. Dukung Pengembangan Aplikasi
                      SettingDivider(c: c),
                      SettingTile(
                        icon: Icons.volunteer_activism_rounded,
                        title: 'Dukung Pengembangan Aplikasi',
                        c: c,
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981)
                                .withValues(alpha: isDark ? 0.20 : 0.12),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: const Color(0xFF10B981)
                                  .withValues(alpha: isDark ? 0.40 : 0.25),
                            ),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'QRIS',
                                style: TextStyle(
                                  color: Color(0xFF10B981),
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(width: 4),
                              Icon(
                                Icons.arrow_forward_ios_rounded,
                                size: 10.5,
                                color: Color(0xFF10B981),
                              ),
                            ],
                          ),
                        ),
                        onTap: () {
                          Navigator.of(context).pop();
                          DialogService.showDonation(context);
                        },
                      ),

                      // 5. Nama Profil Majelis (4 Huruf - Zoom/Teams style)
                      SettingDivider(c: c),
                      SettingTile(
                        icon: Icons.badge_rounded,
                        title: isId ? 'Nama Profil Majelis' : 'Majlis Profile Name',
                        c: c,
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981)
                                .withValues(alpha: isDark ? 0.20 : 0.12),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: const Color(0xFF10B981)
                                  .withValues(alpha: isDark ? 0.40 : 0.25),
                            ),
                          ),
                          child: Text(
                            app.maglisUserName.isNotEmpty
                                ? app.maglisUserName
                                : (isId ? 'Atur (4 Huruf)' : 'Set (4 Letters)'),
                            style: const TextStyle(
                              color: Color(0xFF10B981),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ),
                        onTap: () {
                          Navigator.of(context).pop();
                          _showEditNameDialog(context, app, isDark, isId, c);
                        },
                      ),

                      // 6. Peringatan Kesalahan (Suara & Getar)
                      SettingDivider(c: c),
                      SettingTile(
                        icon: Icons.vibration_rounded,
                        title: isId
                            ? 'Peringatan Kesalahan (Suara & Getar)'
                            : 'Mistake Alert (Sound & Vibrate)',
                        c: c,
                        trailing: Switch.adaptive(
                          value: app.mistakeAlertEnabled,
                          activeThumbColor: const Color(0xFF10B981),
                          onChanged: (val) {
                            app.setMistakeAlertEnabled(val);
                            if (val) {
                              CamcorderSoundHelper.instance.playMistakeAlert();
                            }
                          },
                        ),
                      ),

                      // 6. Recite Player (Murottal Audio Tilawah)
                      SettingDivider(c: c),
                      ListenableBuilder(
                        listenable: QuranAudioService.instance.isPlayingNotifier,
                        builder: (context, _) {
                          final isPlaying =
                              QuranAudioService.instance.isPlayingNotifier.value;
                          return SettingTile(
                            icon: isPlaying
                                ? Icons.pause_circle_rounded
                                : Icons.play_circle_fill_rounded,
                            title: 'Recite Player (Murottal)',
                            c: c,
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981).withValues(
                                    alpha: isDark ? 0.20 : 0.12),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: const Color(0xFF10B981).withValues(
                                      alpha: isDark ? 0.40 : 0.25),
                                ),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    isPlaying
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                    size: 14,
                                    color: const Color(0xFF10B981),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    isPlaying ? 'Jeda' : 'Putar',
                                    style: const TextStyle(
                                      color: Color(0xFF10B981),
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            onTap: () async {
                              final player = QuranAudioService.instance;
                              if (player.isPlayingNotifier.value) {
                                await player.pause();
                              } else {
                                final curSurah =
                                    AppState.instance.lastSurah;
                                final curAyah =
                                    AppState.instance.lastAyah;
                                await player.play(
                                  surah: curSurah,
                                  ayah: curAyah,
                                  continuous: true,
                                );
                              }
                            },
                          );
                        },
                      ),

                      // 7. Sliders in reading mode
                      if (!app.isMushafMode) ...[
                        SettingDivider(c: c),
                        FontSliderTile(c: c, app: app, isAr: isAr),
                        SettingDivider(c: c),
                        AutoScrollSliderTile(c: c, app: app, isAr: isAr),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // ── Bottom Action Buttons (How to Use & Reset - Single Line Guaranteed) ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.center,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // 1. Dukung Aplikasi
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () {
                            Navigator.of(context).pop();
                            DialogService.showDonation(context);
                          },
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.volunteer_activism_rounded,
                                  size: 13,
                                  color: Color(0xFF10B981),
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'Dukung Aplikasi',
                                  style: TextStyle(
                                    color: Color(0xFF10B981),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    height: 1.1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      Container(
                        width: 3,
                        height: 3,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          color: c.textSecondary.withValues(alpha: 0.35),
                          shape: BoxShape.circle,
                        ),
                      ),

                      // 2. How to Use
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () {
                            Navigator.of(context).pop();
                            DialogService.showAppGuide(context);
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.help_outline_rounded,
                                  size: 13,
                                  color: c.textSecondary.withValues(alpha: 0.65),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  app.isIndonesian
                                      ? 'Panduan Penggunaan'
                                      : 'How to Use',
                                  style: TextStyle(
                                    color: c.textSecondary.withValues(alpha: 0.70),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    height: 1.1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                      Container(
                        width: 3,
                        height: 3,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          color: c.textSecondary.withValues(alpha: 0.35),
                          shape: BoxShape.circle,
                        ),
                      ),

                      // 3. Reset to Default Settings
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () async {
                            final prefs =
                                await SharedPreferences.getInstance();
                            final savedSurah = prefs.getInt('last_surah');
                            final savedAyah = prefs.getInt('last_ayah');
                            await prefs.clear();
                            if (savedSurah != null) {
                              await prefs.setInt('last_surah', savedSurah);
                            }
                            if (savedAyah != null) {
                              await prefs.setInt('last_ayah', savedAyah);
                            }
                            if (context.mounted) {
                              await app.load();
                              if (context.mounted) {
                                Navigator.of(context).pop();
                                app.showSettingsResetBanner();
                              }
                            }
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.refresh_rounded,
                                  size: 13,
                                  color:
                                      c.textSecondary.withValues(alpha: 0.65),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  app.isIndonesian
                                      ? 'Atur Ulang Pengaturan'
                                      : 'Reset Settings',
                                  style: TextStyle(
                                    color: c.textSecondary
                                        .withValues(alpha: 0.70),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    height: 1.1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  static void _showEditNameDialog(
    BuildContext context,
    AppState app,
    bool isDark,
    bool isId,
    dynamic c,
  ) {
    final controller = TextEditingController(text: app.maglisUserName);
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981)
                          .withValues(alpha: isDark ? 0.20 : 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(Icons.badge_rounded,
                        color: Color(0xFF10B981), size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      isId ? 'Nama Profil Majelis' : 'Majlis Display Name',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                isId
                    ? 'Nama singkat (maks. 4 huruf) yang akan ditampilkan saat bergabung di Majelis.'
                    : 'Short display name (max 4 letters) shown to peers in Majlis.',
                style: TextStyle(fontSize: 12, color: c.muted, height: 1.3),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: controller,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                maxLength: 4,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 2.0,
                  color: Color(0xFF10B981),
                ),
                decoration: InputDecoration(
                  filled: true,
                  fillColor: isDark
                      ? Colors.white.withValues(alpha: 0.06)
                      : Colors.black.withValues(alpha: 0.04),
                  hintText: isId ? 'MISAL: ZAIN' : 'E.G. JOHN',
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.15)
                          : Colors.black.withValues(alpha: 0.12),
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                        color: Color(0xFF10B981), width: 1.8),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: Text(
                      isId ? 'Batal' : 'Cancel',
                      style: TextStyle(color: c.muted),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF10B981),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    onPressed: () {
                      final val = controller.text.trim().toUpperCase();
                      app.setMaglisUserName(val);
                      Navigator.of(ctx).pop();
                    },
                    child: Text(
                      isId ? 'Simpan' : 'Save',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// 3. FONT SIZE & AUTO-SCROLL SLIDERS
// ══════════════════════════════════════════════════════════════════════════════

class FontSliderTile extends StatefulWidget {
  final ThemeColors c;
  final AppState app;
  final bool isAr;

  const FontSliderTile({
    super.key,
    required this.c,
    required this.app,
    required this.isAr,
  });

  @override
  State<FontSliderTile> createState() => _FontSliderTileState();
}

class _FontSliderTileState extends State<FontSliderTile> {
  late double _localSize;

  @override
  void initState() {
    super.initState();
    _localSize = widget.app.fontSize;
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final app = widget.app;
    final isDark = app.isDarkMode;

    return SettingTile(
      iconWidget: const Center(
        child: Text(
          'Aa',
          style: TextStyle(
            color: Color(0xFF10B981),
            fontSize: 16,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.5,
          ),
        ),
      ),
      title: app.isIndonesian ? 'Ukuran Font' : 'Font Size',
      c: c,
      trailing: Row(
        children: [
          Text(
            'أ',
            style: TextStyle(
              fontFamily: 'HafsSmart',
              color: c.muted,
              fontSize: 12,
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                thumbShape: const RoundSliderThumbShape(
                  enabledThumbRadius: 7,
                ),
                overlayShape: const RoundSliderOverlayShape(
                  overlayRadius: 14,
                ),
                trackHeight: 4,
                activeTrackColor: const Color(0xFF10B981),
                inactiveTrackColor: isDark
                    ? Colors.white.withValues(alpha: 0.12)
                    : Colors.black.withValues(alpha: 0.08),
                thumbColor: const Color(0xFF10B981),
                overlayColor: const Color(0xFF10B981).withValues(alpha: 0.15),
              ),
              child: Slider(
                value: _localSize,
                min: 16.0,
                max: 42.0,
                onChanged: (v) {
                  setState(() => _localSize = v);
                  app.setFontSize(v);
                },
                onChangeEnd: (v) {
                  app.setFontSize(v, persistImmediately: true);
                },
              ),
            ),
          ),
          Text(
            'أ',
            style: TextStyle(
              fontFamily: 'HafsSmart',
              color: c.muted,
              fontSize: 22,
            ),
          ),
        ],
      ),
    );
  }
}

class AutoScrollSliderTile extends StatefulWidget {
  final ThemeColors c;
  final AppState app;
  final bool isAr;

  const AutoScrollSliderTile({
    super.key,
    required this.c,
    required this.app,
    required this.isAr,
  });

  @override
  State<AutoScrollSliderTile> createState() => _AutoScrollSliderTileState();
}

class _AutoScrollSliderTileState extends State<AutoScrollSliderTile> {
  late double _localSpeed;

  @override
  void initState() {
    super.initState();
    _localSpeed = widget.app.autoScrollSpeed.toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.c;
    final app = widget.app;
    final isDark = app.isDarkMode;
    final labels = AppState.speedLabels;

    return SettingTile(
      icon: Icons.speed_rounded,
      title: app.isIndonesian ? 'Kecepatan Gulir' : 'Auto-Scroll Speed',
      c: c,
      trailing: Text(
        labels[_localSpeed.toInt()],
        style: const TextStyle(
          color: Color(0xFF10B981),
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      ),
      bottom: SliderTheme(
        data: SliderThemeData(
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
          trackHeight: 4,
          activeTrackColor: const Color(0xFF10B981),
          inactiveTrackColor: isDark
              ? Colors.white.withValues(alpha: 0.12)
              : Colors.black.withValues(alpha: 0.08),
          thumbColor: const Color(0xFF10B981),
          overlayColor: const Color(0xFF10B981).withValues(alpha: 0.15),
          tickMarkShape: const RoundSliderTickMarkShape(tickMarkRadius: 2),
          activeTickMarkColor: Colors.white,
          inactiveTickMarkColor: isDark
              ? Colors.white.withValues(alpha: 0.15)
              : Colors.black.withValues(alpha: 0.12),
        ),
        child: Slider(
          value: _localSpeed,
          min: 0,
          max: (labels.length - 1).toDouble(),
          divisions: labels.length - 1,
          label: labels[_localSpeed.toInt()],
          onChanged: (v) {
            setState(() => _localSpeed = v);
          },
          onChangeEnd: (v) {
            app.setAutoScrollSpeed(v.toInt());
          },
        ),
      ),
    );
  }
}
