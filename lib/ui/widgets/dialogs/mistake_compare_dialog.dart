import 'dart:async';
import 'package:flutter/material.dart';
import '../../../audio/mistake_audio_service.dart';
import '../../../audio/quran_audio_service.dart';
import '../../../core/app_state.dart';
import '../../../core/highlighting_controller.dart';
import '../../../mushaf/mushaf_provider.dart';
import '../../../iqro/makhraj_visualizer.dart';
import 'dialog_base.dart';
import 'error_detail_dialog.dart' show QvpWordWidget;

/// Modal bottom sheet allowing the user to compare their recorded mispronounced
/// recitation snippet directly against Sheikh Al-Husary's correct recitation.
class MistakeCompareDialog extends StatefulWidget {
  final MistakeAudioClip initialClip;

  const MistakeCompareDialog({
    super.key,
    required this.initialClip,
  });

  static Future<void> show(
    BuildContext context, {
    required MistakeAudioClip clip,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => MistakeCompareDialog(initialClip: clip),
    ).then((_) {
      unawaited(MistakeAudioService.instance.stopPlayback());
      unawaited(QuranAudioService.instance.stop());
    });
  }

  @override
  State<MistakeCompareDialog> createState() => _MistakeCompareDialogState();
}

class _MistakeCompareDialogState extends State<MistakeCompareDialog> {
  late MistakeAudioClip _currentClip;

  @override
  void initState() {
    super.initState();
    _currentClip = widget.initialClip;
  }

  void _selectClip(MistakeAudioClip clip) {
    if (clip.key == _currentClip.key) return;
    unawaited(MistakeAudioService.instance.stopPlayback());
    unawaited(QuranAudioService.instance.stop());
    setState(() {
      _currentClip = clip;
    });
  }

  String _formatDuration(Duration d) {
    final totalSecs = d.inSeconds;
    final mins = totalSecs ~/ 60;
    final secs = totalSecs % 60;
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final mistakeService = MistakeAudioService.instance;
    final app = AppState.instance;

    return ValueListenableBuilder<int>(
      valueListenable: mistakeService.revision,
      builder: (context, _, __) {
        final clips = mistakeService.clips;
        // Ensure _currentClip stays valid if list updated
        MistakeAudioClip activeClip = _currentClip;
        int currentIndex = clips.indexWhere((c) => c.key == activeClip.key);
        if (currentIndex < 0 && clips.isNotEmpty) {
          currentIndex = clips.length - 1;
          activeClip = clips[currentIndex];
        }

        return AppBottomSheet(
          maxHeightFactor: 0.84,
          headerBuilder: (context, c, isAr, isDark) {
            final bool isId = app.isIndonesian;
            final surahAr = QuranMetadata.getSurahNameArabic(activeClip.surah);
            final String titleText = isId
                ? 'Bandingkan Bacaan'
                : (isAr ? 'مقارنة التلاوة' : 'Compare Recitation');
            final String coordText = isId
                ? 'QS. $surahAr • Ayat ${activeClip.ayah}'
                : (isAr
                    ? '$surahAr • آية ${QuranTypography.toArabicDigits(activeClip.ayah)}'
                    : '$surahAr • Ayah ${activeClip.ayah}');

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF43F5E)
                          .withValues(alpha: isDark ? 0.20 : 0.12),
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(
                        color: const Color(0xFFF43F5E)
                            .withValues(alpha: isDark ? 0.45 : 0.30),
                      ),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.compare_arrows_rounded,
                      color: Color(0xFFF43F5E),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          titleText,
                          style: TextStyle(
                            color: c.text,
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          coordText,
                          style: TextStyle(
                            color: c.muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (clips.length > 1)
                    _buildClipPager(
                      clips: clips,
                      currentIndex: currentIndex,
                      c: c,
                      isDark: isDark,
                    ),
                  if (clips.isNotEmpty)
                    IconButton(
                      tooltip: isId
                          ? 'Hapus semua rekaman'
                          : (isAr ? 'مسح التسجيلات' : 'Clear clips'),
                      visualDensity: VisualDensity.compact,
                      onPressed: () {
                        mistakeService.clearAll();
                        if (Navigator.of(context).canPop()) {
                          Navigator.of(context).pop();
                        }
                      },
                      icon: Icon(
                        Icons.delete_outline_rounded,
                        color: c.muted,
                        size: 20,
                      ),
                    ),
                ],
              ),
            );
          },
          builder: (context, c, isAr, isDark) {
            final bool isId = app.isIndonesian;

            return SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Target Word Card ──
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.04)
                          : Colors.black.withValues(alpha: 0.025),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.09)
                            : Colors.black.withValues(alpha: 0.07),
                      ),
                    ),
                    child: Column(
                      children: [
                        Text(
                          isId
                              ? 'Kata yang perlu diperbaiki'
                              : (isAr
                                  ? 'الكلمة التي تحتاج لتصحيح'
                                  : 'Word to review'),
                          style: TextStyle(
                            color: c.muted,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _buildWordDisplay(activeClip, c),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // ── Interactive Makharijul Huruf Diagram ──
                  if (activeClip.wordText.trim().isNotEmpty) ...[
                    MakhrajVisualizer(arabicText: activeClip.wordText),
                    const SizedBox(height: 14),
                  ],

                  // ── Card 1: User's Recorded Audio ──
                  _buildUserAudioCard(
                    clip: activeClip,
                    c: c,
                    isId: isId,
                    isAr: isAr,
                    isDark: isDark,
                  ),

                  const SizedBox(height: 12),

                  // ── Card 2: Correct Qari Audio (Al-Husary) ──
                  _buildQariAudioCard(
                    clip: activeClip,
                    c: c,
                    isId: isId,
                    isAr: isAr,
                    isDark: isDark,
                  ),

                  // ── Session Mistake Chips (if multiple) ──
                  if (clips.length > 1) ...[
                    const SizedBox(height: 16),
                    Text(
                      isId
                          ? 'Daftar Rekaman Kesalahan (${clips.length})'
                          : (isAr
                              ? 'قائمة الأخطاء المسجلة (${clips.length})'
                              : 'Recorded Mistakes (${clips.length})'),
                      style: TextStyle(
                        color: c.muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 36,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: clips.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          final item = clips[index];
                          final bool selected = item.key == activeClip.key;
                          return GestureDetector(
                            onTap: () => _selectClip(item),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 160),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 6),
                              decoration: BoxDecoration(
                                color: selected
                                    ? const Color(0xFFF43F5E).withValues(
                                        alpha: isDark ? 0.24 : 0.14)
                                    : (isDark
                                        ? Colors.white.withValues(alpha: 0.05)
                                        : Colors.black.withValues(alpha: 0.04)),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: selected
                                      ? const Color(0xFFF43F5E)
                                      : (isDark
                                          ? Colors.white.withValues(alpha: 0.10)
                                          : Colors.black
                                              .withValues(alpha: 0.08)),
                                ),
                              ),
                              alignment: Alignment.center,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '${item.surah}:${item.ayah}',
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      color: selected
                                          ? const Color(0xFFF43F5E)
                                          : c.muted,
                                    ),
                                  ),
                                  if (item.wordText.isNotEmpty) ...[
                                    const SizedBox(width: 6),
                                    Text(
                                      item.wordText,
                                      textDirection: TextDirection.rtl,
                                      style: TextStyle(
                                        fontFamily: 'HafsSmart',
                                        fontSize: 15,
                                        color: c.text,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildClipPager({
    required List<MistakeAudioClip> clips,
    required int currentIndex,
    required ThemeColors c,
    required bool isDark,
  }) {
    final bool canPrev = currentIndex > 0;
    final bool canNext = currentIndex >= 0 && currentIndex < clips.length - 1;

    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: canPrev ? () => _selectClip(clips[currentIndex - 1]) : null,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                Icons.chevron_left_rounded,
                size: 18,
                color: canPrev ? c.text : c.muted.withValues(alpha: 0.35),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              '${currentIndex + 1}/${clips.length}',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: c.text,
              ),
            ),
          ),
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: canNext ? () => _selectClip(clips[currentIndex + 1]) : null,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: canNext ? c.text : c.muted.withValues(alpha: 0.35),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWordDisplay(MistakeAudioClip clip, ThemeColors c) {
    final pageNum = MushafProvider.instance.getPageForAyah(clip.surah, clip.ayah);
    if (pageNum != null) {
      final page = MushafProvider.instance.getCachedPage(pageNum);
      if (page != null && !page.isDisposed) {
        for (final w in page.words) {
          if (w.surah == clip.surah &&
              w.ayah == clip.ayah &&
              (w.word - 1) == clip.wordIndex) {
            return QvpWordWidget(
              page: page,
              word: w,
              color: const Color(0xFFF43F5E),
              height: 46,
            );
          }
        }
      }
    }

    return Text(
      clip.wordText.isNotEmpty ? clip.wordText : '—',
      textDirection: TextDirection.rtl,
      style: const TextStyle(
        fontFamily: 'HafsSmart',
        fontSize: 32,
        color: Color(0xFFF43F5E),
        height: 1.35,
      ),
    );
  }

  Widget _buildUserAudioCard({
    required MistakeAudioClip clip,
    required ThemeColors c,
    required bool isId,
    required bool isAr,
    required bool isDark,
  }) {
    final mistakeService = MistakeAudioService.instance;
    const Color rose = Color(0xFFF43F5E);

    return ListenableBuilder(
      listenable: Listenable.merge([
        mistakeService.isPlayingNotifier,
        mistakeService.playingClipKeyNotifier,
        mistakeService.positionNotifier,
        mistakeService.durationNotifier,
      ]),
      builder: (context, _) {
        final bool isThisPlaying = mistakeService.isPlayingNotifier.value &&
            mistakeService.playingClipKeyNotifier.value == clip.key;
        final Duration totalDur = isThisPlaying &&
                mistakeService.durationNotifier.value.inMilliseconds > 0
            ? mistakeService.durationNotifier.value
            : Duration(milliseconds: clip.durationMs);
        final Duration pos = isThisPlaying
            ? mistakeService.positionNotifier.value
            : Duration.zero;
        final double progress = totalDur.inMilliseconds > 0
            ? (pos.inMilliseconds / totalDur.inMilliseconds).clamp(0.0, 1.0)
            : 0.0;

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: rose.withValues(alpha: isDark ? 0.12 : 0.06),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: rose.withValues(
                  alpha: isThisPlaying ? 0.70 : (isDark ? 0.30 : 0.22)),
              width: isThisPlaying ? 1.4 : 1.0,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: rose.withValues(alpha: isDark ? 0.25 : 0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.mic_rounded,
                      color: rose,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isId
                              ? 'Bacaan Kamu (Terekam)'
                              : (isAr
                                  ? 'تلاوتك المسجلة'
                                  : 'Your Recorded Recitation'),
                          style: TextStyle(
                            color: c.text,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          isId
                              ? 'Cuplikan audio saat terdeteksi keliru'
                              : (isAr
                                  ? 'مقطع الصوت عند حدوث الخطأ'
                                  : 'Audio snippet captured at mistake'),
                          style: TextStyle(
                            color: c.muted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => mistakeService.playClip(clip),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: rose,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isThisPlaying
                                  ? Icons.stop_rounded
                                  : Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 18,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              isThisPlaying
                                  ? (isId
                                      ? 'Berhenti'
                                      : (isAr ? 'إيقاف' : 'Stop'))
                                  : (isId
                                      ? 'Putar'
                                      : (isAr ? 'تشغيل' : 'Play')),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: isThisPlaying ? progress : 0.0,
                        minHeight: 5,
                        backgroundColor:
                            rose.withValues(alpha: isDark ? 0.22 : 0.15),
                        valueColor: const AlwaysStoppedAnimation<Color>(rose),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    isThisPlaying
                        ? '${_formatDuration(pos)} / ${_formatDuration(totalDur)}'
                        : _formatDuration(totalDur),
                    style: TextStyle(
                      color: c.muted,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildQariAudioCard({
    required MistakeAudioClip clip,
    required ThemeColors c,
    required bool isId,
    required bool isAr,
    required bool isDark,
  }) {
    final app = AppState.instance;
    final Color emerald = c.primary;

    return ListenableBuilder(
      listenable: Listenable.merge([
        app.isAudioPlaying,
        app.isAudioBuffering,
        app.activeAudioSurah,
        app.activeAudioAyah,
        app.activeAudioWordIndex,
      ]),
      builder: (context, _) {
        final bool isMatchingAyah =
            app.activeAudioSurah.value == clip.surah &&
                app.activeAudioAyah.value == clip.ayah;
        final bool isPlayingWord = app.isAudioPlaying.value &&
            isMatchingAyah &&
            QuranAudioService.instance.isSingleWordMode &&
            app.activeAudioWordIndex.value == clip.wordIndex;
        final bool isPlayingAyah = app.isAudioPlaying.value &&
            isMatchingAyah &&
            !QuranAudioService.instance.isSingleWordMode;
        final bool isBuffering = app.isAudioBuffering.value && isMatchingAyah;

        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: emerald.withValues(alpha: isDark ? 0.12 : 0.06),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: emerald.withValues(
                  alpha: (isPlayingWord || isPlayingAyah)
                      ? 0.70
                      : (isDark ? 0.30 : 0.22)),
              width: (isPlayingWord || isPlayingAyah) ? 1.4 : 1.0,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: emerald.withValues(alpha: isDark ? 0.25 : 0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.record_voice_over_rounded,
                      color: emerald,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isId
                              ? 'Lafal Benar (Syekh Al-Husary)'
                              : (isAr
                                  ? 'النطق الصحيح (الشيخ الحصري)'
                                  : 'Correct Pronunciation (Al-Husary)'),
                          style: TextStyle(
                            color: c.text,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          isId
                              ? 'Bandingkan makhraj & panjang bacaan'
                              : (isAr
                                  ? 'قارن المخارج والمدود بالنطق الصحيح'
                                  : 'Compare articulation and elongation'),
                          style: TextStyle(
                            color: c.muted,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _buildQariButton(
                      label: isId
                          ? (isPlayingWord ? 'Berhenti' : 'Putar Kata Ini')
                          : (isAr
                              ? (isPlayingWord ? 'إيقاف' : 'نطق الكلمة')
                              : (isPlayingWord ? 'Stop' : 'Play Word')),
                      icon: isPlayingWord
                          ? Icons.stop_rounded
                          : Icons.volume_up_rounded,
                      isActive: isPlayingWord,
                      isBuffering: isBuffering && QuranAudioService.instance.isSingleWordMode,
                      color: emerald,
                      isDark: isDark,
                      onTap: () async {
                        await MistakeAudioService.instance.stopPlayback();
                        if (isPlayingWord) {
                          await QuranAudioService.instance.stop();
                        } else {
                          await QuranAudioService.instance.playWord(
                            surah: clip.surah,
                            ayah: clip.ayah,
                            wordIndex: clip.wordIndex,
                          );
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _buildQariButton(
                      label: isId
                          ? (isPlayingAyah ? 'Berhenti' : 'Putar 1 Ayat')
                          : (isAr
                              ? (isPlayingAyah ? 'إيقاف' : 'تشغيل الآية')
                              : (isPlayingAyah ? 'Stop' : 'Play Ayah')),
                      icon: isPlayingAyah
                          ? Icons.stop_rounded
                          : Icons.menu_book_rounded,
                      isActive: isPlayingAyah,
                      isBuffering: isBuffering && !QuranAudioService.instance.isSingleWordMode,
                      color: emerald,
                      isDark: isDark,
                      isOutlined: !isPlayingAyah,
                      onTap: () async {
                        await MistakeAudioService.instance.stopPlayback();
                        if (isPlayingAyah) {
                          await QuranAudioService.instance.stop();
                        } else {
                          await QuranAudioService.instance.play(
                            surah: clip.surah,
                            ayah: clip.ayah,
                            continuous: false,
                          );
                        }
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildQariButton({
    required String label,
    required IconData icon,
    required bool isActive,
    required bool isBuffering,
    required Color color,
    required bool isDark,
    bool isOutlined = false,
    required VoidCallback onTap,
  }) {
    final bool filled = isActive || !isOutlined;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isActive
                ? color
                : (filled
                    ? color.withValues(alpha: isDark ? 0.24 : 0.14)
                    : Colors.transparent),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: color.withValues(alpha: isActive ? 1.0 : 0.45),
              width: 1.1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isBuffering)
                SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      isActive ? Colors.white : color,
                    ),
                  ),
                )
              else
                Icon(
                  icon,
                  size: 17,
                  color: isActive ? Colors.white : color,
                ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: isActive ? Colors.white : color,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
