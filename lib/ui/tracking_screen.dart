import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import '../core/highlighting_controller.dart';
import '../audio/mistake_audio_service.dart';
import '../audio/quran_timing_service.dart';
import '../audio/quran_audio_service.dart';
import '../audio/quran_download_service.dart';
import '../audio/camcorder_sound_helper.dart';
import '../audio/screen_recording_service.dart';
import '../core/platform_utils.dart';
import '../core/subscription_service.dart';
import 'widgets/dialogs/dialog_service.dart';
import 'widgets/dialogs/subscription_paywall_sheet.dart';
import '../core/app_state.dart';
import 'widgets/mic_bar.dart';
import '../mushaf/mushaf_view.dart';
import '../verse_list/verse_list_view.dart';
import '../maglis/maglis_controller.dart';
import '../iqro/iqro_audio_service.dart';
import '../iqro/iqro_controller.dart';
import '../iqro/iqro_view.dart';
import '../iqro/iqro_picker_sheet.dart';

/// Main interactive screen for real-time recitation tracking and reading.
/// Supports high-performance vector Mushaf and dedicated Verse List modes.
class TrackingScreen extends StatefulWidget {
  final HighlightingController controller;
  final bool isRecording;
  final bool isVoiceSearching;
  final String voiceSearchText;
  final ValueListenable<String>? voiceSearchTextNotifier;
  final VoidCallback onToggleRecord;
  final VoidCallback onVoiceSearchToggle;
  final bool isLoadingEngine;
  final ValueNotifier<bool>? isVoiceSearchLoading;
  final VoiceSearchController? voiceSearchController;
  final void Function(int surah, int ayah)? onSelectVoiceCandidate;
  final ValueChanged<bool>? onVoiceSearchHoldChanged;
  final VoidCallback onClearBuffer;

  const TrackingScreen({
    super.key,
    required this.controller,
    required this.isRecording,
    required this.isVoiceSearching,
    this.voiceSearchText = '',
    this.voiceSearchTextNotifier,
    this.voiceSearchController,
    this.onSelectVoiceCandidate,
    this.onVoiceSearchHoldChanged,
    required this.onToggleRecord,
    required this.onVoiceSearchToggle,
    this.isLoadingEngine = false,
    this.isVoiceSearchLoading,
    required this.onClearBuffer,
  });

  @override
  State<TrackingScreen> createState() => _TrackingScreenState();
}

class _TrackingScreenState extends State<TrackingScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  static const MethodChannel _lifecycleChannel =
      MethodChannel('com.ngabar.app/audio_lifecycle');

  final ValueNotifier<String> _voiceSearchNotifier = ValueNotifier('');
  final GlobalKey<VerseListViewState> _verseListKey =
      GlobalKey<VerseListViewState>();
  final ValueNotifier<bool> _isAutoScrolling = ValueNotifier<bool>(false);
  late final ValueNotifier<int> _surahNotifier;

  AppBannerInfo? _lastBanner;
  int? _lastAyah;
  int? _lastSurah;
  Timer? _autoTalqinTimer;
  int _lastProgressWordKey = -1;
  int _lastTalqinWordKey = -1;
  late final Listenable _screenThemeLanguageListenable;
  late final Listenable _bottomBarListenable;

  @override
  void initState() {
    super.initState();
    final app = AppState.instance;
    _surahNotifier = ValueNotifier<int>(_effectiveSurah);
    _screenThemeLanguageListenable = Listenable.merge([
      app.themeNotifier,
      app.languageNotifier,
      app.mushafModeNotifier,
      app.iqroModeNotifier,
    ]);
    _bottomBarListenable = Listenable.merge([
      app.themeNotifier,
      app.languageNotifier,
      app.blurModeNotifier,
      app.modeNotifier,
      app.iqroModeNotifier,
      app.iqroPositionNotifier,
      app.autoTalqinNotifier,
      _surahNotifier,
      MaglisController.instance.sessionListenable,
      ScreenRecordingService.instance.isRecordingNotifier,
    ]);
    if (!PlatformCapabilities.isWeb) {
      WidgetsBinding.instance.addObserver(this);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    }
    widget.controller.addListener(_onControllerUpdate);
    widget.controller.activeAyah.addListener(_onActiveAyahChanged);
    AppState.instance.mushafModeNotifier.addListener(_onMushafModeChanged);
    AppState.instance.currentMushafPage.addListener(_onMushafPageChanged);

    // Warm up Surah timings and Ayah 1 audio in memory/disk in the background for zero-latency instant play
    unawaited(QuranTimingService.instance
        .ensureSurahLoaded(widget.controller.targetSurah));
    if (!PlatformCapabilities.isWeb) {
      unawaited(QuranAudioService.ensureAyahDownloaded(
          widget.controller.targetSurah, 1));
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (PlatformCapabilities.isWeb) return;

    final bool isDesktop = PlatformCapabilities.isDesktop;

    if (state == AppLifecycleState.detached) {
      QuranAudioService.instance.stop();
      if (widget.isRecording) widget.onToggleRecord();
      if (widget.isVoiceSearching) widget.onVoiceSearchToggle();
      return;
    }

    if (!isDesktop) {
      if (state == AppLifecycleState.resumed) {
        // Re-assert immersive sticky fullscreen mode whenever app regains focus or is resumed
        SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
      } else if (state == AppLifecycleState.paused ||
          state == AppLifecycleState.inactive ||
          state == AppLifecycleState.hidden) {
        if (widget.isRecording || QuranAudioService.instance.isSingleWordMode) {
          QuranAudioService.instance.stop();
        } else if (state == AppLifecycleState.paused) {
          // TODO(playstore-fgs): While FOREGROUND_SERVICE_MEDIA_PLAYBACK is disabled,
          // allow audio on screen-off/lock (like v1.2.0+22) and stop if user minimized app.
          if (defaultTargetPlatform == TargetPlatform.android) {
            unawaited(_checkAndStopAudioIfMinimized());
          } else if (defaultTargetPlatform != TargetPlatform.iOS) {
            QuranAudioService.instance.stop();
          }
        }
        // Microphone recording and voice search are suspended.
        if (widget.isRecording) {
          widget.onToggleRecord();
        }
        if (widget.isVoiceSearching) {
          widget.onVoiceSearchToggle();
        }
      }
    }
  }

  Future<void> _checkAndStopAudioIfMinimized() async {
    try {
      final isOffOrLocked =
          await _lifecycleChannel.invokeMethod<bool>('isScreenOffOrLocked') ??
              false;
      if (!isOffOrLocked) {
        await QuranAudioService.instance.stop();
      }
    } catch (_) {
      await QuranAudioService.instance.stop();
    }
  }

  @override
  void dispose() {
    AppState.instance.stopVerseAudio();
    if (!PlatformCapabilities.isWeb) {
      WidgetsBinding.instance.removeObserver(this);
    }
    widget.controller.removeListener(_onControllerUpdate);
    widget.controller.activeAyah.removeListener(_onActiveAyahChanged);
    AppState.instance.mushafModeNotifier.removeListener(_onMushafModeChanged);
    AppState.instance.currentMushafPage.removeListener(_onMushafPageChanged);
    _voiceSearchNotifier.dispose();
    _isAutoScrolling.dispose();
    _surahNotifier.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(TrackingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      _surahNotifier.value = widget.controller.targetSurah;
    }
    if (widget.isRecording && !oldWidget.isRecording) {
      AppState.instance.dismissBanner();
      final int targetAyah =
          widget.controller.currentMatchedVerse?.verse.ayah ??
              widget.controller.activeAyah.value ??
              1;
      _lastAyah = targetAyah;
      _lastTalqinWordKey = -1;
      _scheduleAutoTalqinCheck(forceReset: true);
    } else if (!widget.isRecording && oldWidget.isRecording) {
      _autoTalqinTimer?.cancel();
      _autoTalqinTimer = null;
    }

    if (widget.isVoiceSearching && !oldWidget.isVoiceSearching) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          DialogService.showVoiceSearch(
            context,
            onStop: widget.onVoiceSearchToggle,
            isLoading: widget.isVoiceSearchLoading,
            asrTextNotifier:
                widget.voiceSearchTextNotifier ?? _voiceSearchNotifier,
            searchResultNotifier: widget.voiceSearchController?.currentResult,
            onSelectCandidate: widget.onSelectVoiceCandidate,
            onHoldChanged: widget.onVoiceSearchHoldChanged,
          );
        }
      });
    } else if (!widget.isVoiceSearching && oldWidget.isVoiceSearching) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      });
    }
  }

  void _scheduleAutoTalqinCheck({bool forceReset = false}) {
    final app = AppState.instance;
    if (!widget.isRecording ||
        app.isIqroMode ||
        !app.autoTalqinEnabled ||
        MaglisController.instance.inSession) {
      _autoTalqinTimer?.cancel();
      return;
    }

    final int s = widget.controller.targetSurah > 0
        ? widget.controller.targetSurah
        : app.lastSurah;
    final int a = widget.controller.activeAyah.value ?? app.lastAyah;
    final int w = widget.controller.activeWordIndex ?? 0;
    final int key = QuranCoordinate.packWordKey(s, a, w);

    if (!forceReset && key == _lastProgressWordKey && _autoTalqinTimer != null) {
      return;
    }
    _lastProgressWordKey = key;
    if (forceReset || key != _lastTalqinWordKey) {
      _lastTalqinWordKey = -1;
    }

    _autoTalqinTimer?.cancel();
    _autoTalqinTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted ||
          !widget.isRecording ||
          !AppState.instance.autoTalqinEnabled ||
          QuranAudioService.instance.isPlaying) {
        return;
      }

      int targetS = widget.controller.targetSurah > 0
          ? widget.controller.targetSurah
          : AppState.instance.lastSurah;
      int targetA =
          widget.controller.activeAyah.value ?? AppState.instance.lastAyah;
      int nextW = (widget.controller.activeWordIndex ?? -1) + 1;

      final verse = widget.controller.repository.getVerse(targetS, targetA);
      if (verse != null && nextW >= verse.uthmaniWords.length) {
        final maxAyahs = QuranMetadata.getAyahCount(targetS);
        if (targetA < maxAyahs) {
          targetA++;
          nextW = 0;
        } else if (targetS < 114) {
          targetS++;
          targetA = 1;
          nextW = 0;
        }
      }

      final int talqinKey =
          QuranCoordinate.packWordKey(targetS, targetA, nextW);
      if (talqinKey == _lastTalqinWordKey) return;
      _lastTalqinWordKey = talqinKey;

      unawaited(QuranAudioService.instance.playWord(
        surah: targetS,
        ayah: targetA,
        wordIndex: nextW,
      ));
    });
  }

  void _onControllerUpdate() {
    _scheduleAutoTalqinCheck();
    if (widget.controller.targetSurah != _lastSurah) {
      final newSurah = widget.controller.targetSurah;
      _surahNotifier.value = newSurah;
      void applyUpdate() {
        if (!mounted) return;
        setState(() {
          _lastSurah = newSurah;
          _lastAyah = null;
        });
      }

      if (SchedulerBinding.instance.schedulerPhase ==
          SchedulerPhase.persistentCallbacks) {
        SchedulerBinding.instance.addPostFrameCallback((_) => applyUpdate());
      } else {
        applyUpdate();
      }
    }
  }

  void _onActiveAyahChanged() {
    if (QuranAudioService.instance.isSingleWordMode) return;

    final active = widget.controller.activeAyah.value;
    if (active != null && active != _lastAyah) {
      _lastAyah = active;
      AppState.instance.saveLastPosition(widget.controller.targetSurah, active);
    }
  }

  void _onMushafModeChanged() {
    _isAutoScrolling.value = false;
    final bool isMushaf = AppState.instance.isMushafMode;
    if (isMushaf) {
      final int currentSurah = widget.controller.targetSurah;
      final int currentAyah =
          widget.controller.activeAyah.value ?? AppState.instance.lastAyah;
      final mappedPage =
          MushafView.getPageForAyah(currentSurah, currentAyah) ??
              MushafView.getPageForAyah(currentSurah, 1);
      if (mappedPage != null) {
        AppState.instance.saveMushafPage(mappedPage);
      }
    } else {
      final int targetSurah = _effectiveSurah;
      if (widget.controller.targetSurah != targetSurah) {
        widget.controller.setTargetSurah(
          targetSurah,
          preserveOtherSurahStates: true,
          clearTargetSurah: false,
        );
      }
    }
    _surahNotifier.value = _effectiveSurah;
  }

  void _onMushafPageChanged() {
    if (AppState.instance.isMushafMode) {
      final newSurah = _effectiveSurah;
      if (_surahNotifier.value != newSurah) {
        _surahNotifier.value = newSurah;
      }
    }
  }

  int get _effectiveSurah {
    if (AppState.instance.isMushafMode) {
      final page = AppState.instance.currentMushafPage.value;
      final activeAyah = widget.controller.activeAyah.value;
      final activeSurah = widget.controller.targetSurah;
      if (activeAyah != null &&
          MushafView.isAyahOnPage(
            pageNumber: page,
            surah: activeSurah,
            ayah: activeAyah,
          )) {
        return activeSurah;
      }
      final dominant = MushafView.getDominantSurahOnPage(page);
      if (dominant != null) {
        return dominant;
      }
      final first = MushafView.getFirstAyahOnPage(page);
      if (first != null) {
        return first.$1;
      }
    }
    return widget.controller.targetSurah;
  }

  void _showSurahPicker() {
    DialogService.showSurahPicker(
      context,
      current: _effectiveSurah,
      controller: widget.controller,
      isRecording: widget.isRecording,
      isVoiceSearching: widget.isVoiceSearching,
      onToggleRecord: widget.onToggleRecord,
      onVoiceSearchToggle: widget.onVoiceSearchToggle,
      onPick: (n, {ayah}) async {
          QuranAudioService.instance.stop();
          if (widget.isRecording) {
            widget.onToggleRecord();
          }
          if (Navigator.of(context).canPop()) {
            Navigator.pop(context);
          }
          if (!mounted) return;

          final targetAyah = ayah ?? 1;
          await widget.controller.setTargetSurah(
            n,
            preserveOtherSurahStates: true,
            clearTargetSurah: false,
          );
          widget.controller.setManualAyah(n, targetAyah);
          AppState.instance.saveLastPosition(n, targetAyah);
          final mappedPage =
              MushafView.getPageForAyah(n, targetAyah);
          if (mappedPage != null) {
            AppState.instance.saveMushafPage(mappedPage);
          }
          unawaited(QuranTimingService.instance.ensureSurahLoaded(n));
          unawaited(QuranAudioService.ensureAyahDownloaded(n, 1));

          setState(() {
            _lastAyah = null;
          });
        },
    );
  }

  void _showSettingsDialog() {
    DialogService.showSettings(context);
  }

  void _showSpeedSelectionDialog() {
    DialogService.showSpeedSelection(
      context,
      onSpeedSelected: () => AppState.instance.setHasChosenAutoScrollSpeed(true),
    );
  }

  Future<void> _toggleScreenRecording() async {
    final sr = ScreenRecordingService.instance;
    if (sr.isRecordingNotifier.value) {
      await sr.stopRecording();
      return;
    }
    final app = AppState.instance;
    final maglis = MaglisController.instance;
    final int surah = _effectiveSurah;
    final String surahName = _getSurahName(surah, app.isArabic);
    final int ayah = widget.controller.activeAyah.value ?? app.lastAyah;

    await sr.startRecording(
      isMaglis: maglis.inSession,
      surah: surah,
      surahName: surahName,
      ayah: ayah,
      isExternalMicActive: widget.isRecording || widget.isVoiceSearching,
      maglisRoomCode: maglis.inSession ? maglis.roomCode : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final safeLeft = MediaQuery.paddingOf(context).left;
    final double pageLabelLeft = safeLeft + 16.0;
    final app = AppState.instance;

    return ListenableBuilder(
      listenable: _screenThemeLanguageListenable,
      builder: (context, child) {
        final c = app.colors;

        return PopScope(
          canPop: !app.isIqroMode,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop && app.isIqroMode) {
              IqroAudioService.instance.stop();
              app.setIqroMode(false);
            }
          },
          child: Directionality(
            textDirection: app.isArabic ? TextDirection.rtl : TextDirection.ltr,
            child: Scaffold(
              resizeToAvoidBottomInset: false,
              backgroundColor: c.bg,
              body: ValueListenableBuilder<bool>(
                valueListenable: _isAutoScrolling,
                child: Positioned.fill(child: _buildVerseContent(c, app)),
                builder: (context, isAutoScrolling, verseContentChild) {
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      // Main Verse Content (Mushaf View or Verse List View - preserved across auto-scroll toggles)
                      if (verseContentChild != null) verseContentChild,

                      // Accessible Hands-Free / Auto-Talqin Top Control Strip
                      if (!app.isIqroMode)
                        ValueListenableBuilder<bool>(
                          valueListenable: app.autoTalqinNotifier,
                          builder: (context, isTalqinOn, _) {
                            if (!isTalqinOn) return const SizedBox.shrink();
                            final topPad = MediaQuery.of(context).padding.top;
                            return Positioned(
                              top: topPad + 8,
                              left: 14,
                              right: 14,
                              child: Semantics(
                                button: true,
                                label: widget.isRecording
                                    ? 'Auto-Talqin aktif. Ketuk untuk jeda rekaman, ketuk dua kali untuk dengar kata berikutnya.'
                                    : 'Auto-Talqin siap. Ketuk untuk mulai membaca tanpa melihat mushaf.',
                                child: GestureDetector(
                                  onTap: () {
                                    CamcorderSoundHelper.instance
                                        .playRecordChime(
                                      isStart: !widget.isRecording,
                                    );
                                    widget.onToggleRecord();
                                  },
                                  onDoubleTap: () {
                                    final int s =
                                        widget.controller.targetSurah > 0
                                            ? widget.controller.targetSurah
                                            : app.lastSurah;
                                    final int a =
                                        widget.controller.activeAyah.value ??
                                            app.lastAyah;
                                    final int nextW =
                                        (widget.controller.activeWordIndex ??
                                                -1) +
                                            1;
                                    unawaited(
                                        QuranAudioService.instance.playWord(
                                      surah: s,
                                      ayah: a,
                                      wordIndex: nextW.clamp(0, 200),
                                    ));
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 10,
                                    ),
                                    decoration: BoxDecoration(
                                      color: (widget.isRecording
                                              ? const Color(0xFF065F46)
                                              : const Color(0xFF0F172A))
                                          .withValues(alpha: 0.90),
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: const Color(0xFF10B981)
                                            .withValues(alpha: 0.7),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.hearing_rounded,
                                          color: Color(0xFF34D399),
                                          size: 20,
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            widget.isRecording
                                                ? 'Auto-Talqin Aktif • Ketuk: Jeda | Ketuk 2x: Bantu Kata'
                                                : 'Mode Auto-Talqin • Ketuk di sini untuk Mulai Baca',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontFamily: 'cairo',
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700,
                                              color: Colors.white,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),

                      // Bottom Action Bar (Unified Glassmorphic Command Dock)
                      // Disappears during auto-scroll for zero-distraction teleprompter reading!
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.easeOutCubic,
                        bottom: (!app.isIqroMode && !app.isMushafMode && isAutoScrolling) ? -90.0 : 0,
                        left: 0,
                        right: 0,
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 220),
                          opacity: (!app.isIqroMode && !app.isMushafMode && isAutoScrolling) ? 0.0 : 1.0,
                          child: IgnorePointer(
                            ignoring: !app.isIqroMode && !app.isMushafMode && isAutoScrolling,
                          child: AnimatedBuilder(
                            animation: _bottomBarListenable,
                            builder: (context, _) {
                              final effectiveSurah = _effectiveSurah;
                              final surahName =
                                  _getSurahName(effectiveSurah, app.isArabic);
                              final maglis = MaglisController.instance;
                              final int peerCount = maglis.participantCount;

                              return BottomActionBar(
                                key: const ValueKey('unified_dock_bar'),
                                isRecording: widget.isRecording,
                                isLoadingEngine: widget.isLoadingEngine,
                                c: c,
                                onMic: () {
                                  app.dismissBanner();
                                  CamcorderSoundHelper.instance.playRecordChime(
                                    isStart: !widget.isRecording,
                                  );
                                  if (widget.isVoiceSearching) {
                                    widget.onVoiceSearchToggle();
                                  } else {
                                    widget.onToggleRecord();
                                  }
                                },
                                isBlur: app.isBlurMode,
                                onToggleBlur: () {
                                  app.toggleBlurMode();
                                  if (app.isBlurMode) {
                                    app.showBlurBanner(true);
                                  } else {
                                    app.dismissBanner();
                                  }
                                },
                                isTajweed: app.currentMode == AppMode.tajweed,
                                onToggleTajweed: () {
                                  final bool newIsTajweed =
                                      app.currentMode != AppMode.tajweed;
                                  if (newIsTajweed &&
                                      !SubscriptionService.instance.isPremium) {
                                    SubscriptionPaywallSheet.show(context);
                                    return;
                                  }
                                  if (newIsTajweed) {
                                    app.setMode(AppMode.tajweed);
                                    widget.controller.setTajweedMode(true);
                                    app.showTajweedBanner();
                                  } else {
                                    app.setMode(AppMode.wordChecker);
                                    widget.controller.setTajweedMode(false);
                                    app.dismissTajweedBanner();
                                  }
                                },
                                surahName: app.isIqroMode
                                    ? "Iqro' ${app.iqroJilid} • ${app.iqroPage}"
                                    : surahName,
                                onSurahTap: app.isIqroMode
                                    ? () => IqroPickerSheet.show(context)
                                    : _showSurahPicker,
                                isIqroMode: app.isIqroMode,
                                onIqroTap: () {
                                  app.dismissBanner();
                                  IqroPickerSheet.show(context);
                                },
                                isAutoTalqin: app.autoTalqinEnabled,
                                onToggleAutoTalqin: () {
                                  final next = !app.autoTalqinEnabled;
                                  app.setAutoTalqinEnabled(next);
                                  SemanticsService.sendAnnouncement(
                                    View.of(context),
                                    next
                                        ? 'Auto-Talqin aktif. Ketuk dua kali untuk mulai atau jeda.'
                                        : 'Auto-Talqin dimatikan.',
                                    TextDirection.ltr,
                                  );
                                  if (next) {
                                    _scheduleAutoTalqinCheck(forceReset: true);
                                  }
                                },
                                onSettingsTap: () {
                                  _showSettingsDialog();
                                },
                                isVoiceSearching: widget.isVoiceSearching,
                                onVoiceSearchTap: () {
                                  app.dismissBanner();
                                  widget.onVoiceSearchToggle();
                                },
                                isScreenRecording: ScreenRecordingService
                                    .instance.isRecordingNotifier.value,
                                onScreenRecordTap: () {
                                  app.dismissBanner();
                                  if (!ScreenRecordingService
                                          .instance.isRecordingNotifier.value &&
                                      !SubscriptionService.instance.isPremium) {
                                    SubscriptionPaywallSheet.show(context);
                                    return;
                                  }
                                  unawaited(_toggleScreenRecording());
                                },
                                onOpenRecordingsTap: () {
                                  DialogService.showScreenRecordings(
                                    context,
                                    onStartRecordTap: () =>
                                        unawaited(_toggleScreenRecording()),
                                  );
                                },
                                onPlayReciteTap: () async {
                                  if (app.isIqroMode) {
                                    final iqroAudio = IqroAudioService.instance;
                                    if (iqroAudio.isPlaying) {
                                      await iqroAudio.stop();
                                      return;
                                    }
                                    final page =
                                        IqroController.instance.currentPageData;
                                    if (page != null && page.content.isNotEmpty) {
                                      final idx = IqroController
                                          .instance.activeIndex
                                          .clamp(0, page.content.length - 1);
                                      final cell = page.content[idx];
                                      await iqroAudio.speakArabic(
                                        cell.arabic,
                                        latinText: cell.latin,
                                      );
                                    }
                                    return;
                                  }
                                  final player = QuranAudioService.instance;
                                  if (player.isPlayingNotifier.value) {
                                    await player.pause();
                                  } else {
                                    final curSurah = effectiveSurah;
                                    final curAyah = widget.controller.activeAyah.value ?? app.lastAyah;
                                    await player.play(
                                      surah: curSurah,
                                      ayah: curAyah,
                                      continuous: true,
                                    );
                                  }
                                },
                                isInMaglis: maglis.inSession,
                                maglisRoomCode: maglis.roomCode,
                                maglisPeerCount: peerCount,
                                isRemoteReciting: maglis.isRemoteReciting,
                                onMaglisChatTap: () {
                                  DialogService.showMaglisChat(context);
                                },
                                onMaglisTap: () async {
                                  app.recordMaglisTap();
                                  if (!app.hasSeenMaglisExplanation) {
                                    await DialogService.showMaglisExplanation(context);
                                    if (context.mounted) {
                                      DialogService.showMaglisEntry(context);
                                    }
                                  } else {
                                    DialogService.showMaglisEntry(context);
                                  }
                                },
                                onMaglisExitTap: () async {
                                  if (widget.isRecording) {
                                    widget.onToggleRecord();
                                  }
                                  app.exitMaglisSession();
                                  await maglis.leaveSession();
                                  app.showBanner(AppBannerInfo(
                                    id: 'maglis_left',
                                    messageAr: 'تمت مغادرة المجلس بنجاح',
                                    messageEn: 'Left Majlis session',
                                    messageId: 'Berhasil keluar dari sesi Majlis',
                                    icon: Icons.exit_to_app_rounded,
                                  ));
                                },
                              );
                            },
                          ),
                        ),
                      ),
                    ),

                    // Auto-Scroll / Pause button in Verse List mode (occupies the exact spot as Page Number in Mushaf layout)
                    if (!app.isIqroMode && !app.isMushafMode && !widget.isRecording && !widget.isVoiceSearching)
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 280),
                        curve: Curves.easeOutCubic,
                        left: pageLabelLeft - 13.0,
                        bottom: isAutoScrolling ? (bottom + 18.0 - 13.0) : (bottom + 60.0 - 13.0),
                        child: _AutoScrollFloatingButton(
                          isAutoScrolling: isAutoScrolling,
                          c: c,
                          app: app,
                          onTap: () {
                            _verseListKey.currentState?.toggleAutoScroll();
                          },
                          onLongPress: _showSpeedSelectionDialog,
                        ),
                      ),

                    // Floating Status Pills (Majlis Room Pill + Mistake Comparison Pill)
                    if (!widget.isVoiceSearching)
                      _buildFloatingStatusPills(c, app, bottom, pageLabelLeft),

                    // Modern Floating Slide-Up Banner (Scoped listener prevents full screen rebuilds)
                    ValueListenableBuilder<AppBannerInfo?>(
                      valueListenable: app.bannerNotifier,
                      builder: (context, activeBanner, _) =>
                          _buildModernBottomBanner(c, app, bottom, activeBanner),
                    ),

                    // Floating Download Progress Pill (appears when download dialog is minimized)
                    _buildMinimizedDownloadPill(c, app, bottom),
                  ],
                );
              },
            ),
          ),
        ),
        );
      },
    );
  }

  /// Floating compact pills sitting cleanly in the bottom safe margin above the dock:
  /// - Mistake Comparison Pill (when mistake snippets were captured)
  /// - Majlis Room Status Pill (when in an active Majlis session)
  Widget _buildFloatingStatusPills(
      ThemeColors c, AppState app, double bottom, double pageLabelLeft) {
    final safeRight = MediaQuery.paddingOf(context).right;
    final maglis = MaglisController.instance;
    final sr = ScreenRecordingService.instance;

    return ListenableBuilder(
      listenable: Listenable.merge([
        MistakeAudioService.instance.clipCountNotifier,
        maglis,
        app.bannerNotifier,
        sr.isRecordingNotifier,
        sr.elapsedSecondsNotifier,
        sr.latestCompletedNotifier,
        sr.isLiveStreamingNotifier,
        sr.liveStatusNotifier,
        sr.liveElapsedSecondsNotifier,
        sr.liveBitrateKbpsNotifier,
      ]),
      builder: (context, _) {
        if (app.bannerNotifier.value != null) {
          return const SizedBox.shrink();
        }

        final clips = MistakeAudioService.instance.clips;
        final bool showMistakePill =
            !widget.isRecording && clips.isNotEmpty;
        final bool showMaglisPill = maglis.inSession;
        final bool showLivePill = sr.isLiveStreamingNotifier.value;
        final bool showScreenRecPill =
            !showLivePill && sr.isRecordingNotifier.value;
        final SavedScreenRecording? completedRec =
            (!showScreenRecPill && !showLivePill)
                ? sr.latestCompletedNotifier.value
                : null;

        if (!showMistakePill &&
            !showMaglisPill &&
            !showLivePill &&
            !showScreenRecPill &&
            completedRec == null) {
          return const SizedBox.shrink();
        }

        final bool isDark = app.isDarkMode;
        final bool isId = app.isIndonesian;
        final bool isAr = app.isArabic;

        final Color pillBg =
            isDark ? const Color(0xF2121923) : const Color(0xFCFFFFFF);
        final List<BoxShadow> pillShadow = [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.38 : 0.08),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ];

        Widget? mistakeWidget;
        if (showMistakePill) {
          final Color rose =
              isDark ? const Color(0xFFFB7185) : const Color(0xFFE11D48);
          final int count = clips.length;
          final String label = showMaglisPill
              ? (isId ? '$count Koreksi' : '$count Clips')
              : (isId
                  ? '$count Rekaman Salah • Bandingkan'
                  : (isAr
                      ? '${QuranTypography.toArabicDigits(count)} خطأ • مقارنة'
                      : '$count Mistakes • Compare'));

          mistakeWidget = Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: () {
                DialogService.showMistakeCompare(
                  context,
                  clip: clips.last,
                );
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                decoration: BoxDecoration(
                  color: pillBg,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: rose.withValues(alpha: isDark ? 0.45 : 0.32),
                    width: 1.0,
                  ),
                  boxShadow: pillShadow,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.compare_arrows_rounded,
                      size: 14.5,
                      color: rose,
                    ),
                    const SizedBox(width: 5.5),
                    Text(
                      label,
                      style: TextStyle(
                        color:
                            isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        Widget? maglisWidget;
        if (showMaglisPill) {
          final String rawCode = maglis.roomCode;
          final String userName = app.maglisUserName.trim();
          final String primaryText =
              userName.isNotEmpty ? userName : (rawCode.isEmpty ? '----' : rawCode);
          final int peerCount =
              maglis.participantCount > 0 ? maglis.participantCount : 1;
          final bool activeRecite =
              maglis.isRemoteReciting || widget.isRecording;
          final Color emerald =
              isDark ? const Color(0xFF10B981) : const Color(0xFF059669);
          final Color nameColor = userName.isNotEmpty
              ? (isDark ? const Color(0xFF34D399) : const Color(0xFF047857))
              : (isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A));

          maglisWidget = Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: () {
                if (rawCode.isNotEmpty) {
                  Clipboard.setData(ClipboardData(text: rawCode));
                  app.showBanner(
                    AppBannerInfo(
                      id: 'maglis_code_copied',
                      messageAr: 'تم نسخ رمز المجلس: $rawCode',
                      messageEn: 'Majlis code copied: $rawCode',
                      messageId: 'Kode Majlis disalin: $rawCode',
                      icon: Icons.copy_rounded,
                      customDuration: const Duration(seconds: 2),
                    ),
                  );
                }
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: pillBg,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: activeRecite
                        ? emerald.withValues(alpha: isDark ? 0.55 : 0.38)
                        : (isDark
                            ? Colors.white.withValues(alpha: 0.14)
                            : const Color(0xFFCBD5E1).withValues(alpha: 0.85)),
                    width: 1.0,
                  ),
                  boxShadow: pillShadow,
                ),
                child: Directionality(
                  textDirection: TextDirection.ltr,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Halo live status dot
                      Container(
                        width: 13,
                        height: 13,
                        decoration: BoxDecoration(
                          color: emerald.withValues(alpha: isDark ? 0.22 : 0.16),
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Container(
                          width: 6.5,
                          height: 6.5,
                          decoration: BoxDecoration(
                            color: emerald,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6.5),
                      Text(
                        primaryText,
                        style: TextStyle(
                          fontFamily: 'cairo',
                          color: nameColor,
                          fontWeight: FontWeight.w800,
                          fontSize: 12.2,
                          letterSpacing: userName.isNotEmpty ? 0.4 : 0.6,
                          height: 1.1,
                        ),
                      ),
                      if (maglis.isHost) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF059669), Color(0xFF0D9488)],
                            ),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'USTADZ',
                            style: TextStyle(
                              fontSize: 8.2,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: 0.5,
                              height: 1.0,
                            ),
                          ),
                        ),
                      ],
                      Container(
                        width: 1,
                        height: 12,
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.16)
                            : const Color(0xFFCBD5E1),
                      ),
                      Icon(
                        Icons.people_alt_rounded,
                        size: 13.5,
                        color: isDark
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF64748B),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$peerCount',
                        style: TextStyle(
                          color: isDark
                              ? const Color(0xFFE2E8F0)
                              : const Color(0xFF1E293B),
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        Widget? screenRecWidget;
        if (showLivePill) {
          final liveStatus = sr.liveStatusNotifier.value;
          final int secs = sr.liveElapsedSecondsNotifier.value;
          final int kbps = sr.liveBitrateKbpsNotifier.value;
          final String timeStr =
              SavedScreenRecording.formatDuration(secs * 1000);
          final bool isConnecting = liveStatus == LiveStreamStatus.connecting;
          final String label = isConnecting
              ? (isId ? 'MENGHUBUNGKAN...' : 'CONNECTING...')
              : (kbps > 0 ? 'LIVE $timeStr · $kbps kbps' : 'LIVE $timeStr');
          screenRecWidget = Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: () {
                final int surah = _effectiveSurah;
                DialogService.showLiveStream(
                  context,
                  surah: surah,
                  surahName: _getSurahName(surah, app.isArabic),
                  ayah: widget.controller.activeAyah.value ?? app.lastAyah,
                  isExternalMicActive:
                      widget.isRecording || widget.isVoiceSearching,
                );
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                decoration: BoxDecoration(
                  color: isConnecting
                      ? const Color(0xFFD97706)
                      : const Color(0xFFE11D48),
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: (isConnecting
                              ? const Color(0xFFD97706)
                              : const Color(0xFFE11D48))
                          .withValues(alpha: 0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.sensors_rounded,
                      size: 14,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      label,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        } else if (showScreenRecPill) {
          final int secs = sr.elapsedSecondsNotifier.value;
          final String timeStr =
              SavedScreenRecording.formatDuration(secs * 1000);
          screenRecWidget = Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: () => unawaited(_toggleScreenRecording()),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFE11D48),
                  borderRadius: BorderRadius.circular(22),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFE11D48).withValues(alpha: 0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'REC $timeStr',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Icon(
                      Icons.stop_rounded,
                      size: 14,
                      color: Colors.white,
                    ),
                  ],
                ),
              ),
            ),
          );
        } else if (completedRec != null) {
          final Color emerald =
              isDark ? const Color(0xFF10B981) : const Color(0xFF059669);
          screenRecWidget = Container(
            padding: const EdgeInsets.fromLTRB(10, 5, 6, 5),
            decoration: BoxDecoration(
              color: pillBg,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: emerald.withValues(alpha: isDark ? 0.50 : 0.35),
                width: 1.0,
              ),
              boxShadow: pillShadow,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: () {
                    sr.clearLatestCompleted();
                    DialogService.showRecordingPreview(
                      context,
                      recording: completedRec,
                    );
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.play_circle_filled_rounded,
                        size: 16,
                        color: emerald,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        isId
                            ? 'Video Tersimpan • Putar/Share'
                            : 'Saved • Play/Share',
                        style: TextStyle(
                          color: isDark
                              ? const Color(0xFFF8FAFC)
                              : const Color(0xFF0F172A),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () => sr.shareRecording(completedRec),
                  child: Icon(
                    Icons.share_rounded,
                    size: 14.5,
                    color: emerald,
                  ),
                ),
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: () => sr.clearLatestCompleted(),
                  child: Icon(
                    Icons.close_rounded,
                    size: 15,
                    color: isDark
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          );
        }

        final List<Widget> pills = [
          if (screenRecWidget != null) screenRecWidget,
          if (maglisWidget != null) maglisWidget,
          if (mistakeWidget != null) mistakeWidget,
        ];

        return Positioned(
          bottom: bottom + 68,
          left: pageLabelLeft + 36,
          right: safeRight + 52,
          child: Align(
            alignment: Alignment.center,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.center,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (int i = 0; i < pills.length; i++) ...[
                    if (i > 0) const SizedBox(width: 8),
                    pills[i],
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Floating pill shown when Quran audio download is minimized.
  Widget _buildMinimizedDownloadPill(
      ThemeColors c, AppState app, double bottom) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        QuranDownloadService.instance.isDownloading,
        QuranDownloadService.instance.isMinimized,
        QuranDownloadService.instance.progress,
      ]),
      builder: (context, _) {
        final isDownloading = QuranDownloadService.instance.isDownloading.value;
        final isMinimized = QuranDownloadService.instance.isMinimized.value;
        if (!isDownloading || !isMinimized) {
          return const SizedBox.shrink();
        }

        final progress = QuranDownloadService.instance.progress.value;
        final percent = (progress * 100).toInt();
        final isAr = app.isArabic;
        final isDark = app.isDarkMode;

        return Positioned(
          bottom: bottom + 12,
          left: 16,
          right: 16,
          child: Center(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: () => AudioDownloadDialog.show(context),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E293B) : Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: c.primary.withValues(alpha: isDark ? 0.40 : 0.25),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black
                            .withValues(alpha: isDark ? 0.35 : 0.12),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          value: progress.clamp(0.0, 1.0),
                          valueColor: AlwaysStoppedAnimation<Color>(c.primary),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        isAr
                            ? 'جاري تحميل التلاوة: ${QuranTypography.toArabicDigits(percent)}٪'
                            : 'Downloading Audio: $percent%',
                        style: TextStyle(
                          fontFamily: 'cairo',
                          color: c.text,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(Icons.open_in_full_rounded,
                          size: 14, color: c.muted),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String _getSurahName(int surahNum, bool isArabic) {
    final metadata = widget.controller.repository.surahMetadata;
    if (surahNum >= 1 && surahNum <= metadata.length) {
      final s = metadata[surahNum - 1];
      return isArabic ? s.surahName : s.surahNameEn;
    }
    final verse1 = widget.controller.repository.getVerse(surahNum, 1);
    return isArabic ? (verse1?.surahName ?? '') : (verse1?.surahNameEn ?? '');
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Modern Floating Slide-Up Banner (Slides UP from bottom toolbar for all notices)
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildModernBottomBanner(
      ThemeColors c, AppState app, double bottom, AppBannerInfo? activeBanner) {
    final bool isDark = app.isDarkMode;
    final bool isAr = app.isArabic;
    final bool isVisible = activeBanner != null;

    if (activeBanner != null) {
      _lastBanner = activeBanner;
    }
    final banner = activeBanner ?? _lastBanner;
    if (banner == null) {
      return const SizedBox.shrink();
    }

    final Color accentColor;
    if (banner.customColor != null) {
      accentColor = banner.customColor!(c, isDark);
    } else if (banner.isWarning) {
      accentColor = isDark ? const Color(0xFFF59E0B) : const Color(0xFFD97706);
    } else {
      accentColor = c.primary;
    }

    final Color iconColor =
        (banner.isWarning && isDark) ? const Color(0xFFFBBF24) : accentColor;
    final String message = banner.resolve(app);

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      bottom: isVisible ? (bottom + 78) : (bottom + 16),
      left: 16,
      right: 16,
      child: IgnorePointer(
        ignoring: !isVisible,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 240),
          opacity: isVisible ? 1.0 : 0.0,
          child: RepaintBoundary(
            child: Center(
              child: GestureDetector(
                onTap: () {
                  app.dismissBanner();
                },
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 460),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: isDark ? c.surfaceHigh : c.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: accentColor.withValues(alpha: isDark ? 0.38 : 0.30),
                      width: 1.1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color:
                            Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
                        blurRadius: 14,
                        offset: const Offset(0, -3),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color:
                              accentColor.withValues(alpha: isDark ? 0.20 : 0.12),
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(
                            color: accentColor.withValues(
                                alpha: isDark ? 0.42 : 0.32),
                            width: 0.8,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          banner.icon,
                          color: iconColor,
                          size: 16,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          message,
                          style: TextStyle(
                            color: c.text,
                            height: 1.35,
                            fontWeight: FontWeight.w600,
                            fontSize: 12.5,
                          ),
                          textAlign: isAr ? TextAlign.right : TextAlign.left,
                          textDirection:
                              isAr ? TextDirection.rtl : TextDirection.ltr,
                        ),
                      ),
                      if (banner.onActionTap != null &&
                          banner.resolveActionLabel(app) != null) ...[
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: () {
                            final cb = banner.onActionTap;
                            app.dismissBanner();
                            cb?.call(context);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: accentColor.withValues(
                                  alpha: isDark ? 0.24 : 0.14),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: accentColor.withValues(
                                    alpha: isDark ? 0.50 : 0.36),
                                width: 0.9,
                              ),
                            ),
                            child: Text(
                              banner.resolveActionLabel(app)!,
                              style: TextStyle(
                                color: isDark
                                    ? const Color(0xFFFDE68A)
                                    : accentColor,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVerseContent(ThemeColors c, AppState app) {
    if (app.isIqroMode) {
      return IqroView(
        key: const ValueKey('iqro_view_main'),
        c: c,
        isRecording: widget.isRecording,
        onExitIqro: () => app.setIqroMode(false),
      );
    }

    if (app.isMushafMode) {
      return MushafView(
        key: const ValueKey('mushaf_view_main'),
        controller: widget.controller,
        isRecording: widget.isRecording,
        showBottomPageNumber: true,
      );
    }

    return RepaintBoundary(
      key: const ValueKey('verse_list_boundary'),
      child: VerseListView(
        key: _verseListKey,
        controller: widget.controller,
        isRecording: widget.isRecording,
        onToggleRecord: widget.onToggleRecord,
        onAutoScrollChanged: (scrolling) {
          _isAutoScrolling.value = scrolling;
        },
      ),
    );
  }
}

/// Floating tactical button occupying the exact spot where the Mushaf page number sits.
/// - In idle state: displays speed label (e.g. 1.0x) with scroll chevron; tap starts scroll, hold sets speed.
/// - During auto-scroll: transforms smoothly into a Pause button; tap stops auto-scroll.
class _AutoScrollFloatingButton extends StatefulWidget {
  final bool isAutoScrolling;
  final ThemeColors c;
  final AppState app;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _AutoScrollFloatingButton({
    required this.isAutoScrolling,
    required this.c,
    required this.app,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  State<_AutoScrollFloatingButton> createState() =>
      _AutoScrollFloatingButtonState();
}

class _AutoScrollFloatingButtonState extends State<_AutoScrollFloatingButton> {
  bool _isDown = false;

  @override
  Widget build(BuildContext context) {
    final isDark = widget.app.isDarkMode;
    final isScroll = widget.isAutoScrolling;

    // Matches the styling and color semantics of the mic bar buttons (like community/maglis button)
    final Color bgColor = isScroll
        ? const Color(0xFF10B981).withValues(alpha: isDark ? 0.22 : 0.15)
        : (isDark ? const Color(0xFF1B2430) : const Color(0xFFF1F5F9));

    final Color borderColor = isScroll
        ? const Color(0xFF10B981).withValues(alpha: isDark ? 0.75 : 0.60)
        : (isDark
            ? Colors.white.withValues(alpha: 0.10)
            : Colors.black.withValues(alpha: 0.08));

    final Color iconColor = isScroll
        ? (isDark ? const Color(0xFF10B981) : const Color(0xFF059699))
        : (isDark ? const Color(0xFFE2E8F0) : const Color(0xFF1E293B));

    return GestureDetector(
      onTapDown: (_) => setState(() => _isDown = true),
      onTapUp: (_) => setState(() => _isDown = false),
      onTapCancel: () => setState(() => _isDown = false),
      onTap: () {
        widget.onTap();
      },
      onLongPress: () {
        widget.onLongPress();
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 56,
        height: 56,
        color: Colors.transparent,
        alignment: Alignment.center,
        child: AnimatedScale(
          scale: _isDown ? 0.90 : 1.0,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: borderColor,
                width: isScroll ? 1.2 : 1.0,
              ),
            ),
            alignment: Alignment.center,
            child: Icon(
              isScroll
                  ? Icons.pause_rounded
                  : Icons.keyboard_double_arrow_down_rounded,
              size: 16.5,
              color: iconColor,
            ),
          ),
        ),
      ),
    );
  }
}
