import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Icons;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:share_plus/share_plus.dart';

import '../core/app_state.dart';
import '../core/platform_utils.dart';

enum SocialSharePlatform { youtube, tiktok, facebook }

/// Metadata for a saved screen recording stored on disk.
class SavedScreenRecording {
  final String id;
  final String title;
  final String mode; // 'reciter' | 'maglis'
  final int surah;
  final String surahName;
  final int ayah;
  final String? maglisRoomCode;
  final String fileName;
  final String filePath;
  final DateTime createdAt;
  final int durationMs;
  final int fileSizeBytes;

  const SavedScreenRecording({
    required this.id,
    required this.title,
    required this.mode,
    required this.surah,
    required this.surahName,
    required this.ayah,
    this.maglisRoomCode,
    required this.fileName,
    required this.filePath,
    required this.createdAt,
    required this.durationMs,
    required this.fileSizeBytes,
  });

  bool get isMaglis => mode == 'maglis';

  SavedScreenRecording copyWith({
    String? title,
    int? durationMs,
    int? fileSizeBytes,
  }) {
    return SavedScreenRecording(
      id: id,
      title: title ?? this.title,
      mode: mode,
      surah: surah,
      surahName: surahName,
      ayah: ayah,
      maglisRoomCode: maglisRoomCode,
      fileName: fileName,
      filePath: filePath,
      createdAt: createdAt,
      durationMs: durationMs ?? this.durationMs,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'mode': mode,
        'surah': surah,
        'surahName': surahName,
        'ayah': ayah,
        'maglisRoomCode': maglisRoomCode,
        'fileName': fileName,
        'filePath': filePath,
        'createdAt': createdAt.toIso8601String(),
        'durationMs': durationMs,
        'fileSizeBytes': fileSizeBytes,
      };

  factory SavedScreenRecording.fromJson(Map<String, dynamic> json) {
    return SavedScreenRecording(
      id: (json['id'] ?? '').toString(),
      title: (json['title'] ?? 'Ngabar Recording').toString(),
      mode: (json['mode'] ?? 'reciter').toString(),
      surah: (json['surah'] as num?)?.toInt() ?? 1,
      surahName: (json['surahName'] ?? '').toString(),
      ayah: (json['ayah'] as num?)?.toInt() ?? 1,
      maglisRoomCode: json['maglisRoomCode']?.toString(),
      fileName: (json['fileName'] ?? '').toString(),
      filePath: (json['filePath'] ?? '').toString(),
      createdAt: DateTime.tryParse((json['createdAt'] ?? '').toString()) ??
          DateTime.now(),
      durationMs: (json['durationMs'] as num?)?.toInt() ?? 0,
      fileSizeBytes: (json['fileSizeBytes'] as num?)?.toInt() ?? 0,
    );
  }

  String get formattedDuration => formatDuration(durationMs);

  String get formattedSize => formatBytes(fileSizeBytes);

  static String formatDuration(int ms) {
    final int totalSec = (ms / 1000).round().clamp(0, 86400);
    final int mins = totalSec ~/ 60;
    final int secs = totalSec % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(0)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

class _PendingRecordingMeta {
  final String id;
  final String title;
  final String mode;
  final int surah;
  final String surahName;
  final int ayah;
  final String? maglisRoomCode;
  final String fileName;
  final String filePath;
  final DateTime startedAt;

  const _PendingRecordingMeta({
    required this.id,
    required this.title,
    required this.mode,
    required this.surah,
    required this.surahName,
    required this.ayah,
    required this.maglisRoomCode,
    required this.fileName,
    required this.filePath,
    required this.startedAt,
  });
}

/// Manages hardware screen recording + persistent local storage & sharing
/// for both Solo Reciter and Majlis sessions without disturbing Sherpa-ONNX AI.
class ScreenRecordingService {
  ScreenRecordingService._() {
    _channel.setMethodCallHandler(_handleNativeCallback);
  }

  static final ScreenRecordingService instance = ScreenRecordingService._();

  static const MethodChannel _channel =
      MethodChannel('com.ngabar.app/screen_record');

  /// Soft budget indicator (500 MB) shown in storage bar.
  static const int storageSoftCapBytes = 500 * 1024 * 1024;

  final ValueNotifier<bool> isRecordingNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isStartingNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<int> elapsedSecondsNotifier = ValueNotifier<int>(0);
  final ValueNotifier<List<SavedScreenRecording>> recordingsNotifier =
      ValueNotifier<List<SavedScreenRecording>>([]);
  final ValueNotifier<int> totalBytesNotifier = ValueNotifier<int>(0);
  final ValueNotifier<SavedScreenRecording?> latestCompletedNotifier =
      ValueNotifier<SavedScreenRecording?>(null);

  bool _initialized = false;
  io.Directory? _recordingsDir;
  io.File? _indexFile;
  final List<SavedScreenRecording> _recordings = [];
  _PendingRecordingMeta? _pending;
  Timer? _elapsedTimer;

  bool get isSupported => PlatformCapabilities.isAndroid;
  bool get isRecording => isRecordingNotifier.value;
  List<SavedScreenRecording> get recordings => List.unmodifiable(_recordings);
  int get totalBytes => totalBytesNotifier.value;

  Future<void> init() async {
    if (_initialized || kIsWeb) return;
    _initialized = true;
    await _ensureStorageReady();
    await _loadAndReconcileIndex();
  }

  Future<io.Directory> _ensureStorageReady() async {
    if (_recordingsDir != null) return _recordingsDir!;
    final docs = await getApplicationDocumentsDirectory();
    final dir = io.Directory('${docs.path}/screen_recordings');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _recordingsDir = dir;
    _indexFile = io.File('${dir.path}/recordings_index.json');
    return dir;
  }

  Future<void> _loadAndReconcileIndex() async {
    try {
      final dir = await _ensureStorageReady();
      final idxFile = _indexFile!;
      final List<SavedScreenRecording> loaded = [];

      if (await idxFile.exists()) {
        final raw = await idxFile.readAsString();
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map) {
              final rec = SavedScreenRecording.fromJson(
                Map<String, dynamic>.from(item),
              );
              final f = io.File(rec.filePath);
              if (await f.exists()) {
                final size = await f.length();
                if (size > 0) {
                  loaded.add(
                    size != rec.fileSizeBytes
                        ? rec.copyWith(fileSizeBytes: size)
                        : rec,
                  );
                } else {
                  unawaited(f.delete().catchError((_) => f));
                }
              }
            }
          }
        }
      }

      // Discover any orphaned .mp4 files not in the JSON index
      final knownPaths = loaded.map((e) => e.filePath).toSet();
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is io.File) {
          final lower = entity.path.toLowerCase();
          if (lower.endsWith('.mp4') && !knownPaths.contains(entity.path)) {
            final stat = await entity.stat();
            if (stat.size > 0) {
              final name = entity.uri.pathSegments.isNotEmpty
                  ? entity.uri.pathSegments.last
                  : 'recording.mp4';
              final isMaglis = name.contains('_maglis_');
              loaded.add(
                SavedScreenRecording(
                  id: '${stat.modified.millisecondsSinceEpoch}',
                  title: isMaglis ? 'Rekaman Majlis' : 'Rekaman Tilawah',
                  mode: isMaglis ? 'maglis' : 'reciter',
                  surah: 1,
                  surahName: '',
                  ayah: 1,
                  fileName: name,
                  filePath: entity.path,
                  createdAt: stat.modified,
                  durationMs: 0,
                  fileSizeBytes: stat.size,
                ),
              );
            } else {
              unawaited(entity.delete().catchError((_) => entity));
            }
          }
        }
      }

      loaded.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      _recordings
        ..clear()
        ..addAll(loaded);
      await _persistIndex();
      _notifyStorageUpdated();
    } catch (e) {
      debugPrint('[ScreenRecordingService] Index load error: $e');
    }
  }

  Future<void> _persistIndex() async {
    try {
      await _ensureStorageReady();
      final idxFile = _indexFile;
      if (idxFile == null) return;
      final encoded = jsonEncode(_recordings.map((r) => r.toJson()).toList());
      await idxFile.writeAsString(encoded, flush: true);
    } catch (e) {
      debugPrint('[ScreenRecordingService] Persist index error: $e');
    }
  }

  void _notifyStorageUpdated() {
    recordingsNotifier.value = List.unmodifiable(_recordings);
    int total = 0;
    for (final r in _recordings) {
      total += r.fileSizeBytes;
    }
    totalBytesNotifier.value = total;
  }

  Future<dynamic> _handleNativeCallback(MethodCall call) async {
    if (call.method == 'onStateChanged') {
      final args = call.arguments as Map?;
      final bool recording = args?['isRecording'] == true;
      final String? filePath = args?['filePath'] as String?;
      final int durationMs = (args?['durationMs'] as num?)?.toInt() ?? 0;
      final String? error = args?['error'] as String?;

      if (recording) {
        _startElapsedTicker();
        isRecordingNotifier.value = true;
        isStartingNotifier.value = false;
      } else {
        _stopElapsedTicker();
        isRecordingNotifier.value = false;
        isStartingNotifier.value = false;
        elapsedSecondsNotifier.value = 0;

        if (error != null && error.isNotEmpty) {
          _pending = null;
          _showErrorBanner(error);
        } else if (filePath != null && filePath.isNotEmpty) {
          await _finalizeCompletedRecording(filePath, durationMs);
        } else {
          _pending = null;
        }
      }
    }
    return null;
  }

  void _startElapsedTicker() {
    _elapsedTimer?.cancel();
    elapsedSecondsNotifier.value = 0;
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      elapsedSecondsNotifier.value = elapsedSecondsNotifier.value + 1;
    });
  }

  void _stopElapsedTicker() {
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
  }

  Future<void> _finalizeCompletedRecording(
      String filePath, int durationMs) async {
    try {
      final file = io.File(filePath);
      if (!await file.exists()) {
        _pending = null;
        return;
      }
      final int fileSize = await file.length();
      if (fileSize <= 0) {
        unawaited(file.delete().catchError((_) => file));
        _pending = null;
        return;
      }

      final pending = _pending;
      _pending = null;
      final now = DateTime.now();
      final name = file.uri.pathSegments.isNotEmpty
          ? file.uri.pathSegments.last
          : 'ngabar_${now.millisecondsSinceEpoch}.mp4';

      final saved = SavedScreenRecording(
        id: pending?.id ?? '${now.millisecondsSinceEpoch}',
        title: pending?.title ?? 'Ngabar Recording',
        mode: pending?.mode ?? 'reciter',
        surah: pending?.surah ?? 1,
        surahName: pending?.surahName ?? '',
        ayah: pending?.ayah ?? 1,
        maglisRoomCode: pending?.maglisRoomCode,
        fileName: pending?.fileName ?? name,
        filePath: filePath,
        createdAt: pending?.startedAt ?? now,
        durationMs: durationMs,
        fileSizeBytes: fileSize,
      );

      _recordings.insert(0, saved);
      await _persistIndex();
      _notifyStorageUpdated();
      latestCompletedNotifier.value = saved;
    } catch (e) {
      debugPrint('[ScreenRecordingService] Finalize error: $e');
    }
  }

  Future<bool> startRecording({
    required bool isMaglis,
    required int surah,
    required String surahName,
    required int ayah,
    required bool isExternalMicActive,
    String? maglisRoomCode,
  }) async {
    if (!isSupported) {
      final app = AppState.instance;
      app.showBanner(AppBannerInfo(
        id: 'screen_record_unsupported',
        messageAr: 'تسجيل الشاشة متاح حالياً على أجهزة أندرويد فقط',
        messageEn: 'Screen recording is currently supported on Android devices',
        messageId: 'Rekam layar saat ini tersedia untuk perangkat Android',
        icon: Icons.videocam_off_rounded,
        isWarning: true,
      ));
      return false;
    }
    if (isRecordingNotifier.value || isStartingNotifier.value) {
      return false;
    }

    await init();
    isStartingNotifier.value = true;

    try {
      // Request notification permission nicely on Android 13+ (non-blocking)
      try {
        final notifStatus = await Permission.notification.status;
        if (notifStatus.isDenied) {
          await Permission.notification.request();
        }
      } catch (_) {}

      final dir = await _ensureStorageReady();
      final now = DateTime.now();
      final ts = now.millisecondsSinceEpoch;
      final mode = isMaglis ? 'maglis' : 'reciter';
      final fileName = 'ngabar_${mode}_s${surah}_a${ayah}_$ts.mp4';
      final filePath = '${dir.path}/$fileName';

      final cleanSurah =
          surahName.trim().isNotEmpty ? surahName.trim() : 'Surah $surah';
      final String defaultTitle = isMaglis
          ? 'Majlis${(maglisRoomCode != null && maglisRoomCode.isNotEmpty) ? ' $maglisRoomCode' : ''} • $cleanSurah:$ayah'
          : 'Tilawah • $cleanSurah:$ayah';

      _pending = _PendingRecordingMeta(
        id: '$ts',
        title: defaultTitle,
        mode: mode,
        surah: surah,
        surahName: cleanSurah,
        ayah: ayah,
        maglisRoomCode: maglisRoomCode,
        fileName: fileName,
        filePath: filePath,
        startedAt: now,
      );

      final bool? started = await _channel.invokeMethod<bool>(
        'startScreenRecord',
        {
          'outputPath': filePath,
          'captureMic': true,
          'inMaglis': isMaglis,
          'externalMicActive': isExternalMicActive,
        },
      );

      if (started != true) {
        _pending = null;
        isStartingNotifier.value = false;
        return false;
      }
      return true;
    } catch (e) {
      _pending = null;
      isStartingNotifier.value = false;
      _showErrorBanner(e.toString());
      return false;
    }
  }

  Future<void> stopRecording() async {
    if (!isSupported || !isRecordingNotifier.value) return;
    try {
      await _channel.invokeMethod<bool>('stopScreenRecord');
    } catch (e) {
      debugPrint('[ScreenRecordingService] Stop error: $e');
    }
  }

  Future<void> setExternalMicActive(
    bool active, {
    required bool inMaglis,
  }) async {
    if (!isSupported || !isRecordingNotifier.value) return;
    try {
      await _channel.invokeMethod<bool>(
        'setAudioContext',
        {
          'externalMicActive': active,
          'inMaglis': inMaglis,
        },
      );
    } catch (_) {}
  }

  /// Passively copies the 16kHz Float32 PCM stream from [AppAudioProcessor]
  /// into the native screen recorder audio mixer. Does nothing when screen recording
  /// is inactive, adding zero overhead to Sherpa-ONNX AI word recognition.
  void appendFloat32MicChunk(Float32List chunk) {
    if (!isRecordingNotifier.value || !isSupported || chunk.isEmpty) return;

    final int len = chunk.length;
    final Int16List pcm16 = Int16List(len);
    for (int i = 0; i < len; i++) {
      final int s = (chunk[i] * 32767.0).round();
      pcm16[i] = s > 32767 ? 32767 : (s < -32768 ? -32768 : s);
    }
    final Uint8List bytes = pcm16.buffer.asUint8List(
      pcm16.offsetInBytes,
      pcm16.lengthInBytes,
    );
    unawaited(
      _channel.invokeMethod<void>('appendMicPcm', {'pcm': bytes}).catchError((_) {}),
    );
  }

  String buildShareCaption(SavedScreenRecording rec) {
    final app = AppState.instance;
    final surahLabel = rec.surahName.trim().isNotEmpty
        ? rec.surahName.trim()
        : 'Surah ${rec.surah}';
    if (app.isIndonesian) {
      if (rec.isMaglis) {
        final room = (rec.maglisRoomCode != null && rec.maglisRoomCode!.isNotEmpty)
            ? ' (Majlis ${rec.maglisRoomCode})'
            : '';
        return 'Sesi Majlis Ngaji$room — QS. $surahLabel Ayat ${rec.ayah}\n'
            'Direkam dengan ngabar\n'
            '#ngabar #majlis #quran #tilawah #mengaji';
      }
      return 'Tilawah Al-Qur\'an — QS. $surahLabel Ayat ${rec.ayah}\n'
          'Direkam dengan ngabar\n'
          '#ngabar #tilawah #quran #alquran #mengaji';
    }
    if (rec.isMaglis) {
      return 'Quran Majlis Session — Surah $surahLabel, Ayah ${rec.ayah}\n'
          'Recorded with ngabar\n'
          '#ngabar #quran #majlis #recitation';
    }
    return 'Quran Recitation — Surah $surahLabel, Ayah ${rec.ayah}\n'
        'Recorded with ngabar\n'
        '#ngabar #quran #recitation #tilawah';
  }

  Future<void> copyShareCaption(SavedScreenRecording rec) async {
    final caption = buildShareCaption(rec);
    await Clipboard.setData(ClipboardData(text: caption));
    final app = AppState.instance;
    app.showBanner(AppBannerInfo(
      id: 'social_caption_copied',
      messageAr: 'تم نسخ وصف الآية للحافظة',
      messageEn: 'Verse caption copied to clipboard',
      messageId: 'Caption Surah & hashtag disalin ke clipboard',
      icon: Icons.copy_rounded,
      customDuration: const Duration(seconds: 2),
    ));
  }

  Future<Map<SocialSharePlatform, bool>> getInstalledSocialApps() async {
    if (!isSupported) {
      return const {
        SocialSharePlatform.youtube: false,
        SocialSharePlatform.tiktok: false,
        SocialSharePlatform.facebook: false,
      };
    }
    try {
      final raw = await _channel.invokeMapMethod<String, dynamic>(
        'getInstalledSocialApps',
      );
      return {
        SocialSharePlatform.youtube: raw?['youtube'] == true,
        SocialSharePlatform.tiktok: raw?['tiktok'] == true,
        SocialSharePlatform.facebook: raw?['facebook'] == true,
      };
    } catch (_) {
      return const {
        SocialSharePlatform.youtube: false,
        SocialSharePlatform.tiktok: false,
        SocialSharePlatform.facebook: false,
      };
    }
  }

  Future<void> shareToSocial(
    SavedScreenRecording rec,
    SocialSharePlatform platform,
  ) async {
    final file = io.File(rec.filePath);
    if (!await file.exists()) {
      await _loadAndReconcileIndex();
      return;
    }

    final caption = buildShareCaption(rec);
    await Clipboard.setData(ClipboardData(text: caption));

    if (isSupported) {
      try {
        final bool? launched = await _channel.invokeMethod<bool>(
          'shareToSocialPlatform',
          {
            'filePath': rec.filePath,
            'platform': platform.name,
            'caption': caption,
            'title': rec.title,
          },
        );
        if (launched == true) {
          final app = AppState.instance;
          final label = switch (platform) {
            SocialSharePlatform.youtube => 'YouTube',
            SocialSharePlatform.tiktok => 'TikTok',
            SocialSharePlatform.facebook => 'Facebook',
          };
          app.showBanner(AppBannerInfo(
            id: 'social_share_opened',
            messageAr: 'تم نسخ الوصف وفتح $label',
            messageEn: 'Caption copied — paste in $label description',
            messageId: 'Caption disalin — tinggal tempel di $label',
            icon: Icons.check_circle_outline_rounded,
            customDuration: const Duration(seconds: 3),
          ));
          return;
        }
      } catch (_) {}
    }

    // Fallback: target app not installed or OS blocked direct package target -> standard Share Sheet
    await shareRecording(rec);
  }

  Future<void> shareRecording(SavedScreenRecording rec) async {
    try {
      final file = io.File(rec.filePath);
      if (!await file.exists()) {
        await _loadAndReconcileIndex();
        return;
      }
      final caption = buildShareCaption(rec);
      await Clipboard.setData(ClipboardData(text: caption));

      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(rec.filePath, mimeType: 'video/mp4')],
          text: caption,
          subject: rec.title,
        ),
      );
    } catch (e) {
      _showErrorBanner(e.toString());
    }
  }

  Future<bool> saveToGallery(SavedScreenRecording rec) async {
    if (!isSupported) return false;
    try {
      final bool? ok = await _channel.invokeMethod<bool>(
        'saveVideoToGallery',
        {
          'filePath': rec.filePath,
          'displayName': rec.fileName,
        },
      );
      return ok == true;
    } catch (_) {
      return false;
    }
  }

  Future<void> renameRecording(String id, String newTitle) async {
    final trimmed = newTitle.trim();
    if (trimmed.isEmpty) return;
    final idx = _recordings.indexWhere((r) => r.id == id);
    if (idx < 0) return;
    _recordings[idx] = _recordings[idx].copyWith(title: trimmed);
    await _persistIndex();
    _notifyStorageUpdated();
  }

  Future<void> deleteRecording(String id) async {
    final idx = _recordings.indexWhere((r) => r.id == id);
    if (idx < 0) return;
    final target = _recordings.removeAt(idx);
    if (latestCompletedNotifier.value?.id == id) {
      latestCompletedNotifier.value = null;
    }
    try {
      final f = io.File(target.filePath);
      if (await f.exists()) {
        await f.delete();
      }
    } catch (_) {}
    await _persistIndex();
    _notifyStorageUpdated();
  }

  Future<void> clearAllRecordings() async {
    final copy = List<SavedScreenRecording>.from(_recordings);
    _recordings.clear();
    latestCompletedNotifier.value = null;
    for (final rec in copy) {
      try {
        final f = io.File(rec.filePath);
        if (await f.exists()) {
          await f.delete();
        }
      } catch (_) {}
    }
    await _persistIndex();
    _notifyStorageUpdated();
  }

  void clearLatestCompleted() {
    latestCompletedNotifier.value = null;
  }

  void _showErrorBanner(String err) {
    final app = AppState.instance;
    app.showBanner(AppBannerInfo(
      id: 'screen_record_error',
      messageAr: 'تعذر تسجيل الشاشة: $err',
      messageEn: 'Screen recording error: $err',
      messageId: 'Gagal merekam layar: $err',
      icon: Icons.videocam_off_rounded,
      isWarning: true,
    ));
  }
}
