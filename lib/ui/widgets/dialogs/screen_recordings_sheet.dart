import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../audio/screen_recording_service.dart';
import '../../../core/app_state.dart';
import '../../../core/platform_utils.dart';
import 'dialog_base.dart';
import 'live_stream_sheet.dart';

enum _RecordingFilter { all, reciter, maglis }

class ScreenRecordingsSheet extends StatefulWidget {
  final VoidCallback? onStartRecordTap;

  const ScreenRecordingsSheet({
    super.key,
    this.onStartRecordTap,
  });

  static Future<void> show(
    BuildContext context, {
    VoidCallback? onStartRecordTap,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: DialogTokens.barrierColor,
      elevation: 0,
      builder: (_) => ScreenRecordingsSheet(
        onStartRecordTap: onStartRecordTap,
      ),
    );
  }

  @override
  State<ScreenRecordingsSheet> createState() => _ScreenRecordingsSheetState();
}

class _ScreenRecordingsSheetState extends State<ScreenRecordingsSheet> {
  _RecordingFilter _filter = _RecordingFilter.all;

  @override
  void initState() {
    super.initState();
    unawaited(ScreenRecordingService.instance.init());
  }

  String _formatDateTime(DateTime dt, bool isId) {
    final now = DateTime.now();
    final sameDay =
        now.year == dt.year && now.month == dt.month && now.day == dt.day;
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    if (sameDay) {
      return isId ? 'Hari ini, $hh:$mm' : 'Today, $hh:$mm';
    }
    final dd = dt.day.toString().padLeft(2, '0');
    final mo = dt.month.toString().padLeft(2, '0');
    return '$dd/$mo/${dt.year} $hh:$mm';
  }

  Future<void> _confirmDelete(
    BuildContext context,
    SavedScreenRecording rec,
    ThemeColors c,
    bool isId,
  ) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      barrierColor: DialogTokens.barrierColor,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        title: Text(
          isId ? 'Hapus Rekaman?' : 'Delete Recording?',
          style: TextStyle(color: c.text, fontWeight: FontWeight.w700),
        ),
        content: Text(
          isId
              ? 'File "${rec.title}" (${rec.formattedSize}) akan dihapus permanen dari penyimpanan aplikasi.'
              : '"${rec.title}" (${rec.formattedSize}) will be permanently removed from app storage.',
          style: TextStyle(color: c.textSecondary, fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(isId ? 'Batal' : 'Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFE11D48),
            ),
            child: Text(isId ? 'Hapus' : 'Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ScreenRecordingService.instance.deleteRecording(rec.id);
    }
  }

  Future<void> _confirmClearAll(
    BuildContext context,
    ThemeColors c,
    bool isId,
  ) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      barrierColor: DialogTokens.barrierColor,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        title: Text(
          isId ? 'Bersihkan Semua Rekaman?' : 'Clear All Recordings?',
          style: TextStyle(color: c.text, fontWeight: FontWeight.w700),
        ),
        content: Text(
          isId
              ? 'Seluruh video rekaman layar di penyimpanan aplikasi akan dihapus permanen.'
              : 'All screen recordings stored in app storage will be permanently deleted.',
          style: TextStyle(color: c.textSecondary, fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(isId ? 'Batal' : 'Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFFE11D48),
            ),
            child: Text(isId ? 'Hapus Semua' : 'Delete All'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ScreenRecordingService.instance.clearAllRecordings();
    }
  }

  Future<void> _showRenameDialog(
    BuildContext context,
    SavedScreenRecording rec,
    ThemeColors c,
    bool isId,
  ) async {
    final ctrl = TextEditingController(text: rec.title);
    final String? newName = await showDialog<String>(
      context: context,
      barrierColor: DialogTokens.barrierColor,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        title: Text(
          isId ? 'Ubah Nama Rekaman' : 'Rename Recording',
          style: TextStyle(color: c.text, fontWeight: FontWeight.w700),
        ),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 60,
          style: TextStyle(color: c.text),
          decoration: InputDecoration(
            hintText: isId ? 'Judul rekaman' : 'Recording title',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(isId ? 'Batal' : 'Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text),
            child: Text(isId ? 'Simpan' : 'Save'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (newName != null && newName.trim().isNotEmpty) {
      await ScreenRecordingService.instance.renameRecording(rec.id, newName);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sr = ScreenRecordingService.instance;
    return AppBottomSheet(
      maxHeightFactor: 0.84,
      extraListenable: Listenable.merge([
        sr.recordingsNotifier,
        sr.totalBytesNotifier,
        sr.isRecordingNotifier,
        sr.elapsedSecondsNotifier,
      ]),
      headerBuilder: (context, c, isAr, isDark) {
        final isId = AppState.instance.isIndonesian;
        final bool isRec = sr.isRecordingNotifier.value;
        final int count = sr.recordingsNotifier.value.length;
        final String totalFormatted =
            SavedScreenRecording.formatBytes(sr.totalBytesNotifier.value);

        return AppModalHeader(
          title: isId ? 'Rekaman Layar & Storage' : 'Screen Recordings & Storage',
          subtitle: isId
              ? '$count video tersimpan · $totalFormatted'
              : '$count saved videos · $totalFormatted',
          leading: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFE11D48)
                  .withValues(alpha: isDark ? 0.18 : 0.10),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFFE11D48)
                    .withValues(alpha: isDark ? 0.40 : 0.24),
              ),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.video_library_rounded,
              color: Color(0xFFE11D48),
              size: 20,
            ),
          ),
          actions: [
            if (PlatformCapabilities.isAndroid) ...[
              GestureDetector(
                onTap: () {
                  Navigator.of(context).pop();
                  LiveStreamSheet.show(context);
                },
                child: Container(
                  margin: const EdgeInsets.only(right: 6),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                  decoration: BoxDecoration(
                    color: sr.isLiveStreamingNotifier.value
                        ? const Color(0xFFE11D48)
                        : const Color(0xFF2563EB)
                            .withValues(alpha: isDark ? 0.22 : 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: sr.isLiveStreamingNotifier.value
                          ? const Color(0xFFE11D48)
                          : const Color(0xFF2563EB).withValues(alpha: 0.42),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.sensors_rounded,
                        size: 13,
                        color: sr.isLiveStreamingNotifier.value
                            ? Colors.white
                            : const Color(0xFF2563EB),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Live',
                        style: TextStyle(
                          color: sr.isLiveStreamingNotifier.value
                              ? Colors.white
                              : const Color(0xFF2563EB),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (widget.onStartRecordTap != null)
              GestureDetector(
                onTap: () {
                  Navigator.of(context).pop();
                  widget.onStartRecordTap!.call();
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: isRec
                        ? const Color(0xFFE11D48)
                        : const Color(0xFF10B981)
                            .withValues(alpha: isDark ? 0.22 : 0.14),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: isRec
                          ? const Color(0xFFE11D48)
                          : const Color(0xFF10B981).withValues(alpha: 0.45),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isRec
                            ? Icons.stop_rounded
                            : Icons.fiber_manual_record_rounded,
                        size: 13,
                        color: isRec ? Colors.white : const Color(0xFF10B981),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isRec
                            ? (isId ? 'Stop' : 'Stop')
                            : (isId ? 'Rekam' : 'Record'),
                        style: TextStyle(
                          color: isRec ? Colors.white : const Color(0xFF10B981),
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
      builder: (context, c, isAr, isDark) {
        final isId = AppState.instance.isIndonesian;
        final all = sr.recordingsNotifier.value;
        final int totalBytes = sr.totalBytesNotifier.value;
        final double usedFraction =
            (totalBytes / ScreenRecordingService.storageSoftCapBytes)
                .clamp(0.0, 1.0);

        final filtered = switch (_filter) {
          _RecordingFilter.all => all,
          _RecordingFilter.reciter => all.where((r) => !r.isMaglis).toList(),
          _RecordingFilter.maglis => all.where((r) => r.isMaglis).toList(),
        };

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Storage usage card
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 10),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.045)
                      : Colors.black.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.black.withValues(alpha: 0.06),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.sd_storage_rounded,
                          size: 16,
                          color: c.primary,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            isId
                                ? 'Penyimpanan Lokal: ${SavedScreenRecording.formatBytes(totalBytes)} / 500 MB'
                                : 'Local Storage: ${SavedScreenRecording.formatBytes(totalBytes)} / 500 MB',
                            style: TextStyle(
                              color: c.text,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        if (all.isNotEmpty)
                          GestureDetector(
                            onTap: () => _confirmClearAll(context, c, isId),
                            child: Text(
                              isId ? 'Bersihkan' : 'Clear All',
                              style: const TextStyle(
                                color: Color(0xFFE11D48),
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: usedFraction,
                        minHeight: 5,
                        backgroundColor: isDark
                            ? Colors.white.withValues(alpha: 0.08)
                            : Colors.black.withValues(alpha: 0.07),
                        valueColor: AlwaysStoppedAnimation<Color>(
                          usedFraction > 0.85
                              ? const Color(0xFFE11D48)
                              : const Color(0xFF10B981),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Filter chips
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 10),
              child: Row(
                children: [
                  _buildFilterChip(
                    label: isId ? 'Semua (${all.length})' : 'All (${all.length})',
                    selected: _filter == _RecordingFilter.all,
                    isDark: isDark,
                    c: c,
                    onTap: () => setState(() => _filter = _RecordingFilter.all),
                  ),
                  const SizedBox(width: 8),
                  _buildFilterChip(
                    label: isId ? 'Tilawah' : 'Reciter',
                    selected: _filter == _RecordingFilter.reciter,
                    isDark: isDark,
                    c: c,
                    onTap: () =>
                        setState(() => _filter = _RecordingFilter.reciter),
                  ),
                  const SizedBox(width: 8),
                  _buildFilterChip(
                    label: 'Majlis',
                    selected: _filter == _RecordingFilter.maglis,
                    isDark: isDark,
                    c: c,
                    onTap: () =>
                        setState(() => _filter = _RecordingFilter.maglis),
                  ),
                ],
              ),
            ),

            // List or empty state
            if (filtered.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 34),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 58,
                      height: 58,
                      decoration: BoxDecoration(
                        color: c.primary.withValues(alpha: isDark ? 0.14 : 0.09),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.videocam_rounded,
                        size: 28,
                        color: c.primary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      isId
                          ? 'Belum ada rekaman layar tersimpan'
                          : 'No screen recordings saved yet',
                      style: TextStyle(
                        color: c.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      isId
                          ? 'Tekan ikon rekam layar saat tilawah (Reciter) atau di alat Majlis untuk merekam & membagikan bacaanmu.'
                          : 'Tap the screen record icon during Reciter mode or inside Majlis tools to capture and share.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: c.textSecondary,
                        fontSize: 12.2,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              )
            else
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (ctx, i) {
                    final rec = filtered[i];
                    return _buildRecordingCard(context, rec, c, isDark, isId);
                  },
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool selected,
    required bool isDark,
    required ThemeColors c,
    required VoidCallback onTap,
  }) {
    const Color emerald = Color(0xFF10B981);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? emerald.withValues(alpha: isDark ? 0.22 : 0.14)
              : (isDark
                  ? Colors.white.withValues(alpha: 0.05)
                  : Colors.black.withValues(alpha: 0.04)),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? emerald.withValues(alpha: 0.6)
                : (isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.06)),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? emerald : c.textSecondary,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildRecordingCard(
    BuildContext context,
    SavedScreenRecording rec,
    ThemeColors c,
    bool isDark,
    bool isId,
  ) {
    final Color badgeColor =
        rec.isMaglis ? const Color(0xFFF59E0B) : const Color(0xFF10B981);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.05)
            : Colors.black.withValues(alpha: 0.025),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.09)
              : Colors.black.withValues(alpha: 0.06),
        ),
      ),
      child: Row(
        children: [
          // Play thumbnail button
          GestureDetector(
            onTap: () => RecordingPreviewDialog.show(context, recording: rec),
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: rec.isMaglis
                      ? const [Color(0xFFD97706), Color(0xFFB45309)]
                      : const [Color(0xFF10B981), Color(0xFF059669)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.play_arrow_rounded,
                color: Colors.white,
                size: 28,
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Metadata
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => RecordingPreviewDialog.show(context, recording: rec),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: badgeColor.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          rec.isMaglis ? 'MAJLIS' : 'RECITER',
                          style: TextStyle(
                            color: badgeColor,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        rec.formattedDuration,
                        style: TextStyle(
                          color: c.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '· ${rec.formattedSize}',
                        style: TextStyle(
                          color: c.textSecondary,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    rec.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: c.text,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _formatDateTime(rec.createdAt, isId),
                    style: TextStyle(
                      color: c.textSecondary.withValues(alpha: 0.8),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Quick Share button (YouTube / TikTok / Facebook / Share Sheet)
          IconButton(
            tooltip: isId ? 'Bagikan ke Sosmed' : 'Share to Social',
            onPressed: () => _SocialShareSheet.show(context, rec),
            icon: const Icon(
              Icons.share_rounded,
              size: 20,
              color: Color(0xFF10B981),
            ),
          ),

          // More options (Gallery, Rename, Delete)
          PopupMenuButton<String>(
            icon: Icon(Icons.more_vert_rounded, size: 20, color: c.textSecondary),
            color: c.surface,
            onSelected: (action) async {
              switch (action) {
                case 'gallery':
                  final ok =
                      await ScreenRecordingService.instance.saveToGallery(rec);
                  if (context.mounted) {
                    AppState.instance.showBanner(AppBannerInfo(
                      id: 'saved_gallery',
                      messageAr: ok ? 'تم الحفظ في المعرض' : 'تعذر الحفظ في المعرض',
                      messageEn: ok
                          ? 'Saved to Movies/Ngabar gallery'
                          : 'Could not save to gallery',
                      messageId: ok
                          ? 'Disimpan ke Galeri (Movies/Ngabar)'
                          : 'Gagal menyimpan ke galeri',
                      icon: ok
                          ? Icons.check_circle_rounded
                          : Icons.error_outline_rounded,
                      isWarning: !ok,
                    ));
                  }
                  break;
                case 'rename':
                  await _showRenameDialog(context, rec, c, isId);
                  break;
                case 'delete':
                  await _confirmDelete(context, rec, c, isId);
                  break;
              }
            },
            itemBuilder: (_) => [
              if (PlatformCapabilities.isAndroid)
                PopupMenuItem(
                  value: 'gallery',
                  child: Row(
                    children: [
                      Icon(Icons.download_rounded, size: 18, color: c.text),
                      const SizedBox(width: 8),
                      Text(
                        isId ? 'Simpan ke Galeri' : 'Save to Gallery',
                        style: TextStyle(color: c.text, fontSize: 13),
                      ),
                    ],
                  ),
                ),
              PopupMenuItem(
                value: 'rename',
                child: Row(
                  children: [
                    Icon(Icons.edit_rounded, size: 18, color: c.text),
                    const SizedBox(width: 8),
                    Text(
                      isId ? 'Ubah Nama' : 'Rename',
                      style: TextStyle(color: c.text, fontSize: 13),
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    const Icon(Icons.delete_outline_rounded,
                        size: 18, color: Color(0xFFE11D48)),
                    const SizedBox(width: 8),
                    Text(
                      isId ? 'Hapus' : 'Delete',
                      style: const TextStyle(
                        color: Color(0xFFE11D48),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// In-app video preview dialog using native Android [VideoView] PlatformView
/// so users can inspect recordings and share/save immediately.
class RecordingPreviewDialog extends StatefulWidget {
  final SavedScreenRecording recording;

  const RecordingPreviewDialog({
    super.key,
    required this.recording,
  });

  static Future<void> show(
    BuildContext context, {
    required SavedScreenRecording recording,
  }) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.78),
      builder: (_) => RecordingPreviewDialog(recording: recording),
    );
  }

  @override
  State<RecordingPreviewDialog> createState() => _RecordingPreviewDialogState();
}

class _RecordingPreviewDialogState extends State<RecordingPreviewDialog> {
  MethodChannel? _playerChannel;
  Timer? _pollTimer;
  bool _prepared = false;
  bool _isPlaying = false;
  int _durationMs = 0;
  int _positionMs = 0;
  double _aspectRatio = 9 / 16;

  @override
  void initState() {
    super.initState();
    _durationMs = widget.recording.durationMs;
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _playerChannel?.setMethodCallHandler(null);
    super.dispose();
  }

  void _onPlatformViewCreated(int viewId) {
    final ch = MethodChannel('com.ngabar.app/video_player_$viewId');
    _playerChannel = ch;
    ch.setMethodCallHandler((call) async {
      if (!mounted) return;
      if (call.method == 'onPrepared') {
        final args = call.arguments as Map?;
        final int dur = (args?['durationMs'] as num?)?.toInt() ?? _durationMs;
        final int w = (args?['width'] as num?)?.toInt() ?? 9;
        final int h = (args?['height'] as num?)?.toInt() ?? 16;
        setState(() {
          _prepared = true;
          if (dur > 0) _durationMs = dur;
          if (w > 0 && h > 0) _aspectRatio = w / h;
        });
        await _togglePlayPause(forcePlay: true);
      } else if (call.method == 'onCompleted') {
        _pollTimer?.cancel();
        setState(() {
          _isPlaying = false;
          _positionMs = _durationMs;
        });
      }
    });
  }

  Future<void> _togglePlayPause({bool forcePlay = false}) async {
    final ch = _playerChannel;
    if (ch == null || !_prepared) return;
    if (!forcePlay && _isPlaying) {
      await ch.invokeMethod('pause');
      _pollTimer?.cancel();
      if (mounted) setState(() => _isPlaying = false);
    } else {
      if (_positionMs >= _durationMs && _durationMs > 0) {
        await ch.invokeMethod('seekTo', {'positionMs': 0});
      }
      await ch.invokeMethod('play');
      if (mounted) setState(() => _isPlaying = true);
      _pollTimer?.cancel();
      _pollTimer = Timer.periodic(const Duration(milliseconds: 250), (_) async {
        if (!mounted || _playerChannel == null) return;
        try {
          final int? pos = await _playerChannel!.invokeMethod<int>('getPosition');
          if (pos != null && mounted) {
            setState(() => _positionMs = pos.clamp(0, _durationMs > 0 ? _durationMs : pos));
          }
        } catch (_) {}
      });
    }
  }

  Future<void> _seekTo(int ms) async {
    final ch = _playerChannel;
    if (ch == null || !_prepared) return;
    setState(() => _positionMs = ms);
    await ch.invokeMethod('seekTo', {'positionMs': ms});
  }

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    final c = app.colors;
    final isDark = app.isDarkMode;
    final isId = app.isIndonesian;
    final rec = widget.recording;

    return Dialog(
      backgroundColor: isDark ? const Color(0xFF101620) : Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 440,
          maxHeight: MediaQuery.sizeOf(context).height * 0.86,
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: (rec.isMaglis
                              ? const Color(0xFFF59E0B)
                              : const Color(0xFF10B981))
                          .withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      rec.isMaglis ? 'MAJLIS' : 'RECITER',
                      style: TextStyle(
                        color: rec.isMaglis
                            ? const Color(0xFFF59E0B)
                            : const Color(0xFF10B981),
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      rec.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: c.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close_rounded, color: c.textSecondary),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Video viewport
              Flexible(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: AspectRatio(
                    aspectRatio: _aspectRatio.clamp(0.45, 1.8),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        if (PlatformCapabilities.isAndroid)
                          AndroidView(
                            viewType: 'com.ngabar.app/video_player',
                            creationParams: {'path': rec.filePath},
                            creationParamsCodec: const StandardMessageCodec(),
                            onPlatformViewCreated: _onPlatformViewCreated,
                          )
                        else
                          Container(
                            color: Colors.black,
                            alignment: Alignment.center,
                            child: Text(
                              rec.fileName,
                              style: const TextStyle(color: Colors.white70),
                            ),
                          ),
                        Positioned.fill(
                          child: GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onTap: () => _togglePlayPause(),
                            child: AnimatedOpacity(
                              opacity: _isPlaying ? 0.0 : 1.0,
                              duration: const Duration(milliseconds: 180),
                              child: Center(
                                child: Container(
                                  width: 58,
                                  height: 58,
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.58),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    Icons.play_arrow_rounded,
                                    color: Colors.white,
                                    size: 36,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // Seek bar
              if (PlatformCapabilities.isAndroid) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _togglePlayPause(),
                      icon: Icon(
                        _isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        color: c.primary,
                      ),
                    ),
                    Text(
                      SavedScreenRecording.formatDuration(_positionMs),
                      style: TextStyle(
                        color: c.textSecondary,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Expanded(
                      child: Slider(
                        value: _durationMs > 0
                            ? (_positionMs / _durationMs).clamp(0.0, 1.0)
                            : 0.0,
                        activeColor: const Color(0xFF10B981),
                        onChanged: _prepared && _durationMs > 0
                            ? (v) => _seekTo((v * _durationMs).round())
                            : null,
                      ),
                    ),
                    Text(
                      SavedScreenRecording.formatDuration(_durationMs),
                      style: TextStyle(
                        color: c.textSecondary,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ] else
                const SizedBox(height: 12),

              // Direct Social Share strip (YouTube, TikTok, Facebook + Copy Caption)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.04)
                      : Colors.black.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.black.withValues(alpha: 0.06),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.campaign_rounded,
                          size: 14,
                          color: c.textSecondary,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            isId
                                ? 'Upload Cepat (Caption otomatis disalin)'
                                : 'Quick Post (Auto-caption copied)',
                            style: TextStyle(
                              color: c.textSecondary,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        InkWell(
                          borderRadius: BorderRadius.circular(8),
                          onTap: () => ScreenRecordingService.instance
                              .copyShareCaption(rec),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.copy_rounded,
                                  size: 13,
                                  color: c.primary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  isId ? 'Salin Caption' : 'Copy Caption',
                                  style: TextStyle(
                                    color: c.primary,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _SocialQuickButton(
                            label: 'YouTube',
                            icon: Icons.smart_display_rounded,
                            color: const Color(0xFFFF0033),
                            onTap: () => ScreenRecordingService.instance
                                .shareToSocial(rec, SocialSharePlatform.youtube),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: _SocialQuickButton(
                            label: 'TikTok',
                            icon: Icons.music_note_rounded,
                            color: isDark
                                ? const Color(0xFFFE2C55)
                                : const Color(0xFF0F172A),
                            onTap: () => ScreenRecordingService.instance
                                .shareToSocial(rec, SocialSharePlatform.tiktok),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: _SocialQuickButton(
                            label: 'Facebook',
                            icon: Icons.facebook_rounded,
                            color: const Color(0xFF1877F2),
                            onTap: () => ScreenRecordingService.instance
                                .shareToSocial(rec, SocialSharePlatform.facebook),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // Bottom actions: Share Others + Save Gallery + Delete
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () =>
                          ScreenRecordingService.instance.shareRecording(rec),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.share_rounded, size: 18),
                      label: Text(isId ? 'Share Lainnya' : 'More Apps'),
                    ),
                  ),
                  if (PlatformCapabilities.isAndroid) ...[
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final ok = await ScreenRecordingService.instance
                            .saveToGallery(rec);
                        if (context.mounted) {
                          AppState.instance.showBanner(AppBannerInfo(
                            id: 'preview_saved_gallery',
                            messageAr: ok ? 'تم الحفظ في المعرض' : 'تعذر الحفظ',
                            messageEn: ok
                                ? 'Saved to Movies/Ngabar'
                                : 'Could not save to gallery',
                            messageId: ok
                                ? 'Disimpan ke Galeri (Movies/Ngabar)'
                                : 'Gagal menyimpan ke galeri',
                            icon: ok
                                ? Icons.check_circle_rounded
                                : Icons.error_outline_rounded,
                            isWarning: !ok,
                          ));
                        }
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: c.text,
                        side: BorderSide(color: c.border),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.download_rounded, size: 18),
                      label: Text(isId ? 'Galeri' : 'Gallery'),
                    ),
                  ],
                  const SizedBox(width: 6),
                  IconButton(
                    tooltip: isId ? 'Hapus' : 'Delete',
                    onPressed: () async {
                      await ScreenRecordingService.instance
                          .deleteRecording(rec.id);
                      if (context.mounted) {
                        Navigator.of(context).pop();
                      }
                    },
                    icon: const Icon(
                      Icons.delete_outline_rounded,
                      color: Color(0xFFE11D48),
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

class _SocialQuickButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _SocialQuickButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.32)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 11.2,
                    fontWeight: FontWeight.w800,
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

class _SocialShareSheet extends StatefulWidget {
  final SavedScreenRecording recording;

  const _SocialShareSheet({required this.recording});

  static Future<void> show(
    BuildContext context,
    SavedScreenRecording recording,
  ) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: DialogTokens.barrierColor,
      elevation: 0,
      builder: (_) => _SocialShareSheet(recording: recording),
    );
  }

  @override
  State<_SocialShareSheet> createState() => _SocialShareSheetState();
}

class _SocialShareSheetState extends State<_SocialShareSheet> {
  Map<SocialSharePlatform, bool>? _installed;

  @override
  void initState() {
    super.initState();
    unawaited(_loadInstalled());
  }

  Future<void> _loadInstalled() async {
    final res = await ScreenRecordingService.instance.getInstalledSocialApps();
    if (mounted) {
      setState(() => _installed = res);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sr = ScreenRecordingService.instance;
    final rec = widget.recording;
    final caption = sr.buildShareCaption(rec);

    return AppBottomSheet(
      maxHeightFactor: 0.72,
      headerBuilder: (context, c, isAr, isDark) {
        final isId = AppState.instance.isIndonesian;
        return AppModalHeader(
          title: isId ? 'Bagikan Video Tilawah' : 'Share Recitation Video',
          subtitle: rec.title,
          leading: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFF10B981)
                  .withValues(alpha: isDark ? 0.18 : 0.11),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFF10B981)
                    .withValues(alpha: isDark ? 0.38 : 0.24),
              ),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.share_rounded,
              color: Color(0xFF10B981),
              size: 20,
            ),
          ),
        );
      },
      builder: (context, c, isAr, isDark) {
        final isId = AppState.instance.isIndonesian;
        final installed = _installed;
        final ytInstalled = installed?[SocialSharePlatform.youtube];
        final ttInstalled = installed?[SocialSharePlatform.tiktok];
        final fbInstalled = installed?[SocialSharePlatform.facebook];

        return Padding(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Auto-generated caption card
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.04)
                      : Colors.black.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.black.withValues(alpha: 0.06),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.subtitles_rounded,
                          size: 15,
                          color: c.primary,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            isId
                                ? 'Caption & Hashtag Otomatis'
                                : 'Auto Caption & Hashtags',
                            style: TextStyle(
                              color: c.text,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          onPressed: () => sr.copyShareCaption(rec),
                          icon: const Icon(Icons.copy_rounded, size: 14),
                          label: Text(
                            isId ? 'Salin' : 'Copy',
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      caption,
                      style: TextStyle(
                        color: c.textSecondary,
                        fontSize: 11.8,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              Text(
                isId
                    ? 'Pilih Platform (caption otomatis disalin ke clipboard)'
                    : 'Choose Platform (caption auto-copied to clipboard)',
                style: TextStyle(
                  color: c.textSecondary,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),

              Row(
                children: [
                  Expanded(
                    child: _SocialPlatformTile(
                      label: 'YouTube',
                      subtitle: ytInstalled == false
                          ? (isId ? 'Via Share' : 'Share')
                          : 'Shorts / Video',
                      icon: Icons.smart_display_rounded,
                      color: const Color(0xFFFF0033),
                      isDark: isDark,
                      c: c,
                      onTap: () {
                        Navigator.of(context).pop();
                        unawaited(
                          sr.shareToSocial(rec, SocialSharePlatform.youtube),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _SocialPlatformTile(
                      label: 'TikTok',
                      subtitle: ttInstalled == false
                          ? (isId ? 'Via Share' : 'Share')
                          : 'Post Video',
                      icon: Icons.music_note_rounded,
                      color: isDark
                          ? const Color(0xFFFE2C55)
                          : const Color(0xFF0F172A),
                      isDark: isDark,
                      c: c,
                      onTap: () {
                        Navigator.of(context).pop();
                        unawaited(
                          sr.shareToSocial(rec, SocialSharePlatform.tiktok),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _SocialPlatformTile(
                      label: 'Facebook',
                      subtitle: fbInstalled == false
                          ? (isId ? 'Via Share' : 'Share')
                          : 'Reels / Feed',
                      icon: Icons.facebook_rounded,
                      color: const Color(0xFF1877F2),
                      isDark: isDark,
                      c: c,
                      onTap: () {
                        Navigator.of(context).pop();
                        unawaited(
                          sr.shareToSocial(rec, SocialSharePlatform.facebook),
                        );
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop();
                        unawaited(sr.shareRecording(rec));
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: c.text,
                        side: BorderSide(color: c.border),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.apps_rounded, size: 18),
                      label: Text(
                        isId
                            ? 'Aplikasi Lain (WA, IG, Telegram)'
                            : 'Other Apps',
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
}

class _SocialPlatformTile extends StatelessWidget {
  final String label;
  final String subtitle;
  final IconData icon;
  final Color color;
  final bool isDark;
  final ThemeColors c;
  final VoidCallback onTap;

  const _SocialPlatformTile({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.isDark,
    required this.c,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: isDark ? 0.14 : 0.08),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: color.withValues(alpha: isDark ? 0.35 : 0.24),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: isDark ? 0.22 : 0.14),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(icon, size: 20, color: color),
              ),
              const SizedBox(height: 8),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: c.text,
                  fontSize: 12.2,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: c.textSecondary,
                  fontSize: 10.2,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

