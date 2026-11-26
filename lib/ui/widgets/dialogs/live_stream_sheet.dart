import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../audio/screen_recording_service.dart';
import '../../../core/app_state.dart';
import '../../../core/highlighting_controller.dart' show QuranMetadata;
import '../../../maglis/maglis_controller.dart';
import 'dialog_base.dart';

class LiveStreamSheet extends StatefulWidget {
  final int surah;
  final String surahName;
  final int ayah;
  final bool isExternalMicActive;

  const LiveStreamSheet({
    super.key,
    required this.surah,
    required this.surahName,
    required this.ayah,
    required this.isExternalMicActive,
  });

  static Future<void> show(
    BuildContext context, {
    int? surah,
    String? surahName,
    int? ayah,
    bool isExternalMicActive = false,
  }) {
    final app = AppState.instance;
    final s = surah ?? app.lastSurah;
    final sName = (surahName != null && surahName.isNotEmpty)
        ? surahName
        : (app.isArabic
            ? QuranMetadata.getSurahNameArabic(s)
            : 'Surah $s');
    final a = ayah ?? app.lastAyah;

    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: DialogTokens.barrierColor,
      elevation: 0,
      builder: (_) => LiveStreamSheet(
        surah: s,
        surahName: sName,
        ayah: a,
        isExternalMicActive: isExternalMicActive,
      ),
    );
  }

  @override
  State<LiveStreamSheet> createState() => _LiveStreamSheetState();
}

class _LiveStreamSheetState extends State<LiveStreamSheet> {
  late LiveStreamPlatform _platform;
  late LiveEncoderProfile _encoderProfile;
  late bool _youtubeUseTls;
  late TextEditingController _customUrlCtrl;
  late TextEditingController _streamKeyCtrl;
  bool _obscureKey = true;
  bool _configLoaded = false;

  @override
  void initState() {
    super.initState();
    final sr = ScreenRecordingService.instance;
    _platform = sr.livePlatform;
    _encoderProfile = sr.liveEncoderProfile;
    _youtubeUseTls = sr.liveYoutubeUseTls;
    _customUrlCtrl = TextEditingController(text: sr.liveCustomUrl);
    _streamKeyCtrl = TextEditingController(text: sr.liveStreamKey);
    unawaited(_ensureInit());
  }

  Future<void> _ensureInit() async {
    final sr = ScreenRecordingService.instance;
    await sr.init();
    if (!mounted || _configLoaded) return;
    _configLoaded = true;
    setState(() {
      _platform = sr.livePlatform;
      _encoderProfile = sr.liveEncoderProfile;
      _youtubeUseTls = sr.liveYoutubeUseTls;
      if (_customUrlCtrl.text != sr.liveCustomUrl) {
        _customUrlCtrl.text = sr.liveCustomUrl;
      }
      if (_streamKeyCtrl.text != sr.liveStreamKey) {
        _streamKeyCtrl.text = sr.liveStreamKey;
      }
    });
  }

  @override
  void dispose() {
    _customUrlCtrl.dispose();
    _streamKeyCtrl.dispose();
    super.dispose();
  }

  Future<void> _pasteStreamKey() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final txt = (data?.text ?? '').trim();
    if (txt.isNotEmpty && mounted) {
      setState(() {
        _streamKeyCtrl.text = txt;
      });
    }
  }

  Future<void> _startLive() async {
    final sr = ScreenRecordingService.instance;
    final maglis = MaglisController.instance;
    final ok = await sr.startLiveStream(
      platform: _platform,
      encoderProfile: _encoderProfile,
      youtubeUseTls: _youtubeUseTls,
      customUrl: _customUrlCtrl.text,
      streamKey: _streamKeyCtrl.text,
      isMaglis: maglis.inSession,
      isExternalMicActive: widget.isExternalMicActive,
    );
    if (ok && mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final sr = ScreenRecordingService.instance;

    return AppBottomSheet(
      maxHeightFactor: 0.88,
      extraListenable: Listenable.merge([
        sr.isLiveStreamingNotifier,
        sr.liveStatusNotifier,
        sr.liveBitrateKbpsNotifier,
        sr.liveDroppedFramesNotifier,
        sr.liveElapsedSecondsNotifier,
        sr.liveErrorNotifier,
        sr.isStartingNotifier,
      ]),
      headerBuilder: (context, c, isAr, isDark) {
        final isId = AppState.instance.isIndonesian;
        final isLive = sr.isLiveStreamingNotifier.value;

        return AppModalHeader(
          title: isId ? 'Live Streaming (RTMP)' : 'Live Streaming (RTMP)',
          subtitle: isLive
              ? (isId
                  ? 'Siaran langsung aktif • AI tetap aman'
                  : 'Broadcast active • AI-safe mode')
              : (isId
                  ? 'YouTube Live & Facebook Live dengan encoder ringan AI-safe'
                  : 'YouTube Live & Facebook Live with AI-safe encoder'),
          leading: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFE11D48)
                  .withValues(alpha: isDark ? 0.18 : 0.11),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFFE11D48)
                    .withValues(alpha: isDark ? 0.38 : 0.24),
              ),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.sensors_rounded,
              color: Color(0xFFE11D48),
              size: 20,
            ),
          ),
        );
      },
      builder: (context, c, isAr, isDark) {
        final isId = AppState.instance.isIndonesian;
        final isLive = sr.isLiveStreamingNotifier.value;
        final status = sr.liveStatusNotifier.value;
        final kbps = sr.liveBitrateKbpsNotifier.value;
        final dropped = sr.liveDroppedFramesNotifier.value;
        final elapsedSec = sr.liveElapsedSecondsNotifier.value;
        final err = sr.liveErrorNotifier.value;
        final starting = sr.isStartingNotifier.value;
        final maglis = MaglisController.instance;

        if (isLive) {
          return _buildLiveActiveBody(
            c: c,
            isDark: isDark,
            isId: isId,
            status: status,
            kbps: kbps,
            dropped: dropped,
            elapsedSec: elapsedSec,
            maglis: maglis,
            sr: sr,
          );
        }

        final serverPreview = sr.serverUrlFor(
          _platform,
          youtubeTls: _youtubeUseTls,
        );

        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (err != null && err.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE11D48).withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFFE11D48).withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.error_outline_rounded,
                        size: 18,
                        color: Color(0xFFE11D48),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          err,
                          style: const TextStyle(
                            color: Color(0xFFE11D48),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Platform selector
              Text(
                isId ? 'Platform Tujuan' : 'Target Platform',
                style: TextStyle(
                  color: c.text,
                  fontSize: 12.2,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              AppSegmentedPillSelector(
                labels: const ['YouTube', 'Facebook', 'Custom'],
                selected: _platform.index,
                c: c,
                onSelected: (idx) {
                  setState(() {
                    _platform = LiveStreamPlatform.values[idx];
                  });
                },
              ),
              const SizedBox(height: 12),

              // Server RTMP URL
              if (_platform == LiveStreamPlatform.custom) ...[
                Text(
                  'Server RTMP / RTMPS URL',
                  style: TextStyle(
                    color: c.text,
                    fontSize: 12.2,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _customUrlCtrl,
                  style: TextStyle(color: c.text, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'rtmps://a.rtmps.youtube.com/live2',
                    hintStyle: TextStyle(color: c.muted, fontSize: 12.5),
                    filled: true,
                    fillColor: isDark
                        ? Colors.white.withValues(alpha: 0.04)
                        : Colors.black.withValues(alpha: 0.03),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 11,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: c.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: c.border.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                ),
              ] else ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.04)
                        : Colors.black.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.black.withValues(alpha: 0.06),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _platform == LiveStreamPlatform.youtube
                            ? Icons.smart_display_rounded
                            : Icons.facebook_rounded,
                        size: 18,
                        color: _platform == LiveStreamPlatform.youtube
                            ? const Color(0xFFFF0033)
                            : const Color(0xFF1877F2),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              isId ? 'Server Ingest' : 'Ingest Server',
                              style: TextStyle(
                                color: c.muted,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              serverPreview,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: c.text,
                                fontSize: 11.8,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_platform == LiveStreamPlatform.youtube)
                        GestureDetector(
                          onTap: () => setState(
                            () => _youtubeUseTls = !_youtubeUseTls,
                          ),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981)
                                  .withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              _youtubeUseTls ? 'RTMPS' : 'RTMP',
                              style: const TextStyle(
                                color: Color(0xFF10B981),
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),

              // Stream Key input
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Stream Key',
                      style: TextStyle(
                        color: c.text,
                        fontSize: 12.2,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    onPressed: _pasteStreamKey,
                    icon: const Icon(Icons.content_paste_rounded, size: 14),
                    label: Text(
                      isId ? 'Tempel' : 'Paste',
                      style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              TextField(
                controller: _streamKeyCtrl,
                obscureText: _obscureKey,
                style: TextStyle(color: c.text, fontSize: 13),
                decoration: InputDecoration(
                  hintText: _platform == LiveStreamPlatform.youtube
                      ? 'xxxx-xxxx-xxxx-xxxx-xxxx'
                      : 'FB-xxxxxxxxxxxx...',
                  hintStyle: TextStyle(color: c.muted, fontSize: 12.5),
                  filled: true,
                  fillColor: isDark
                      ? Colors.white.withValues(alpha: 0.04)
                      : Colors.black.withValues(alpha: 0.03),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 11,
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureKey
                          ? Icons.visibility_off_rounded
                          : Icons.visibility_rounded,
                      size: 18,
                      color: c.muted,
                    ),
                    onPressed: () =>
                        setState(() => _obscureKey = !_obscureKey),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: c.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: c.border.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _platform == LiveStreamPlatform.youtube
                    ? (isId
                        ? 'Ambil Stream Key di YouTube Studio → Go Live → Stream Settings.'
                        : 'Copy Stream Key from YouTube Studio → Go Live.')
                    : (_platform == LiveStreamPlatform.facebook
                        ? (isId
                            ? 'Ambil Kunci Streaming di Facebook Live Producer → Perangkat Lunak Streaming.'
                            : 'Copy Stream Key from Facebook Live Producer → Streaming Software.')
                        : (isId
                            ? 'Masukkan URL server RTMP/RTMPS dan Stream Key platform tujuan.'
                            : 'Enter target RTMP/RTMPS server URL and Stream Key.')),
                style: TextStyle(
                  color: c.textSecondary,
                  fontSize: 11,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 14),

              // Lightweight Encoder Profile selector
              Text(
                isId
                    ? 'Opsi Encoder (Keamanan AI Sherpa-ONNX)'
                    : 'Encoder Profile (AI Performance)',
                style: TextStyle(
                  color: c.text,
                  fontSize: 12.2,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              _buildProfileCard(
                profile: LiveEncoderProfile.aiSafeLight,
                title: isId
                    ? 'Ringan • Aman untuk AI (Rekomendasi)'
                    : 'Light • AI-Safe (Recommended)',
                specs: '540p · 20 fps · 1.2 Mbps · Audio 64 kbps',
                description: isId
                    ? 'Beban CPU/GPU rendah & anti-panas. AI pengenal ayat & suara mic tetap responsif tanpa lag.'
                    : 'Low CPU/GPU & thermal load so Sherpa-ONNX AI stays fast.',
                badge: isId ? 'AMAN AI' : 'AI SAFE',
                accent: const Color(0xFF10B981),
                c: c,
                isDark: isDark,
              ),
              const SizedBox(height: 8),
              _buildProfileCard(
                profile: LiveEncoderProfile.balancedHd,
                title: isId ? 'HD Seimbang (720p)' : 'Balanced HD (720p)',
                specs: '720p · 24 fps · 2.2 Mbps · Audio 96 kbps',
                description: isId
                    ? 'Resolusi lebih tajam untuk HP flagship & jaringan Wi-Fi cepat.'
                    : 'Sharper 720p output for flagship devices & fast Wi-Fi.',
                accent: const Color(0xFF2563EB),
                c: c,
                isDark: isDark,
              ),
              const SizedBox(height: 14),

              // Copy stream title + Start Live CTA
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: () => sr.copyLiveStreamMeta(
                      isMaglis: maglis.inSession,
                      surah: widget.surah,
                      surahName: widget.surahName,
                      ayah: widget.ayah,
                      maglisRoomCode:
                          maglis.inSession ? maglis.roomCode : null,
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: c.text,
                      side: BorderSide(color: c.border),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 13,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: const Icon(Icons.copy_rounded, size: 17),
                    label: Text(isId ? 'Salin Judul' : 'Copy Title'),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: starting ? null : _startLive,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFE11D48),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.sensors_rounded, size: 19),
                      label: Text(
                        starting
                            ? (isId ? 'Mempersiapkan...' : 'Starting...')
                            : (isId ? 'Mulai Live Sekarang' : 'Go Live Now'),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
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

  Widget _buildLiveActiveBody({
    required ThemeColors c,
    required bool isDark,
    required bool isId,
    required LiveStreamStatus status,
    required int kbps,
    required int dropped,
    required int elapsedSec,
    required MaglisController maglis,
    required ScreenRecordingService sr,
  }) {
    final bool isConnected = status == LiveStreamStatus.live;
    final String timeStr =
        SavedScreenRecording.formatDuration(elapsedSec * 1000);
    final String profileLabel =
        sr.liveEncoderProfile == LiveEncoderProfile.aiSafeLight
            ? 'Ringan • Aman AI (540p 20fps)'
            : 'HD Seimbang (720p 24fps)';

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 6, 18, 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFE11D48)
                  .withValues(alpha: isDark ? 0.14 : 0.08),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFFE11D48).withValues(alpha: 0.35),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: isConnected
                            ? const Color(0xFFE11D48)
                            : const Color(0xFFF59E0B),
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isConnected
                            ? (isId ? 'SEDANG LIVE' : 'LIVE NOW')
                            : (isId
                                ? 'MENGHUBUNGKAN KE SERVER...'
                                : 'CONNECTING...'),
                        style: TextStyle(
                          color: isConnected
                              ? const Color(0xFFE11D48)
                              : const Color(0xFFF59E0B),
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    Text(
                      timeStr,
                      style: TextStyle(
                        color: c.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _statPill(
                      Icons.speed_rounded,
                      '$kbps kbps',
                      c,
                      isDark,
                    ),
                    _statPill(
                      Icons.memory_rounded,
                      profileLabel,
                      c,
                      isDark,
                    ),
                    if (dropped > 0)
                      _statPill(
                        Icons.network_check_rounded,
                        'Drop: $dropped',
                        c,
                        isDark,
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: () => sr.copyLiveStreamMeta(
                  isMaglis: maglis.inSession,
                  surah: widget.surah,
                  surahName: widget.surahName,
                  ayah: widget.ayah,
                  maglisRoomCode: maglis.inSession ? maglis.roomCode : null,
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: c.text,
                  side: BorderSide(color: c.border),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 13,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: const Icon(Icons.copy_rounded, size: 17),
                label: Text(isId ? 'Salin Judul' : 'Copy Title'),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () async {
                    await sr.stopLiveStream();
                    if (mounted) Navigator.of(context).pop();
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFE11D48),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.stop_circle_rounded, size: 19),
                  label: Text(
                    isId ? 'Hentikan Live' : 'Stop Live',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statPill(
    IconData icon,
    String text,
    ThemeColors c,
    bool isDark,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.08)
            : Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: c.textSecondary),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: c.text,
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileCard({
    required LiveEncoderProfile profile,
    required String title,
    required String specs,
    required String description,
    String? badge,
    required Color accent,
    required ThemeColors c,
    required bool isDark,
  }) {
    final bool selected = _encoderProfile == profile;
    return GestureDetector(
      onTap: () => setState(() => _encoderProfile = profile),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: isDark ? 0.14 : 0.08)
              : (isDark
                  ? Colors.white.withValues(alpha: 0.03)
                  : Colors.black.withValues(alpha: 0.02)),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? accent
                : (isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.08)),
            width: selected ? 1.4 : 1.0,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              selected
                  ? Icons.radio_button_checked_rounded
                  : Icons.radio_button_off_rounded,
              size: 19,
              color: selected ? accent : c.muted,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            color: c.text,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (badge != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            badge,
                            style: TextStyle(
                              color: accent,
                              fontSize: 9.5,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    specs,
                    style: TextStyle(
                      color: accent,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    description,
                    style: TextStyle(
                      color: c.textSecondary,
                      fontSize: 11,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
