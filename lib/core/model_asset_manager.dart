import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'platform_utils.dart';
import 'package:recite_quran/recite_quran.dart';

/// Manages pre-extraction and verification of the on-device Zipformer ASR model
/// and token vocabulary assets.
///
/// Features:
/// - Atomic extraction via unique temp files to prevent partial write crashes
/// - Concurrency protection so multiple background/foreground callers share one Future
/// - Cleans up legacy stale `.tmp` files
/// - Validates exact byte size of the quantized INT8 model
class ModelAssetManager {
  ModelAssetManager._();
  static final ModelAssetManager instance = ModelAssetManager._();

  static const String modelFileName = 'zipformer_p_arabic_v3.int8.onnx';
  static const String tokensFileName = 'tokens.txt';
  static const String prefix = 'v2_zipformer_';
  static const int expectedModelSize = 72705392;

  Completer<void>? _extractionCompleter;

  /// Ensures neural model and tokens assets are cleanly extracted to application support directory.
  Future<void> ensureModelExtracted() async {
    if (PlatformCapabilities.isWeb) return;

    if (_extractionCompleter != null) {
      return _extractionCompleter!.future;
    }
    _extractionCompleter = Completer<void>();

    try {
      final Directory docDir = await getApplicationSupportDirectory();
      if (!await docDir.exists()) {
        await docDir.create(recursive: true);
      }

      final targetModelFile = File('${docDir.path}/$prefix$modelFileName');
      final targetTokensFile = File('${docDir.path}/$prefix$tokensFileName');

      // Clean up legacy stale .tmp file if any was left behind
      final legacyTmp = File('${targetModelFile.path}.tmp');
      if (await legacyTmp.exists()) {
        try {
          await legacyTmp.delete();
        } catch (_) {}
      }

      // 1. Verify model file
      bool modelReady = false;
      if (await targetModelFile.exists()) {
        final len = await targetModelFile.length();
        if (len == expectedModelSize) {
          modelReady = true;
        } else {
          // Incomplete or corrupt file from previous aborted write
          try {
            await targetModelFile.delete();
          } catch (_) {}
        }
      }

      if (!modelReady) {
        DebugLogger.logSimple('ASR', '📦 Extracting model asset ($expectedModelSize bytes)...');
        ByteData data;
        try {
          data = await rootBundle.load('assets/model/$modelFileName');
        } catch (_) {
          data = await rootBundle.load('packages/recite_quran/assets/model/$modelFileName');
        }

        final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);

        // Write to a unique temp file first
        final uniqueTmp = File('${targetModelFile.path}.tmp_${DateTime.now().millisecondsSinceEpoch}');
        await uniqueTmp.writeAsBytes(bytes, flush: true);

        // Validate length before atomic rename
        final writtenLen = await uniqueTmp.length();
        if (writtenLen != bytes.length) {
          try {
            await uniqueTmp.delete();
          } catch (_) {}
          throw Exception('Model write failed: expected ${bytes.length} bytes, got $writtenLen');
        }

        // Atomic rename: this ensures targetModelFile appears complete in a single inode operation
        await uniqueTmp.rename(targetModelFile.path);
        DebugLogger.logSimple('ASR', '✅ Model asset extracted and verified successfully.');
      }

      // 2. Verify tokens file
      bool tokensReady = false;
      if (await targetTokensFile.exists()) {
        final len = await targetTokensFile.length();
        if (len > 100) {
          tokensReady = true;
        } else {
          try {
            await targetTokensFile.delete();
          } catch (_) {}
        }
      }

      if (!tokensReady) {
        ByteData data;
        try {
          data = await rootBundle.load('packages/recite_quran/assets/model/$tokensFileName');
        } catch (_) {
          data = await rootBundle.load('assets/model/$tokensFileName');
        }

        final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
        final uniqueTmp = File('${targetTokensFile.path}.tmp_${DateTime.now().millisecondsSinceEpoch}');
        await uniqueTmp.writeAsBytes(bytes, flush: true);
        await uniqueTmp.rename(targetTokensFile.path);
      }

      _extractionCompleter!.complete();
    } catch (e, st) {
      DebugLogger.logSimple('ASR', '❌ Model extraction failed: $e');
      _extractionCompleter!.completeError(e, st);
      _extractionCompleter = null; // Allow retry on failure
      rethrow;
    }
  }
}
