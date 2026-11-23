import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../core/app_state.dart';
import 'dialog_base.dart';

// ══════════════════════════════════════════════════════════════════════════════
// 1. PERMISSION REASON & PROMPT DIALOG
// ══════════════════════════════════════════════════════════════════════════════

enum PermissionReason { tracking, voiceSearch }

/// Dialog prompting user to grant microphone permissions.
class PermissionDialog extends StatelessWidget {
  final PermissionReason reason;

  const PermissionDialog({
    super.key,
    required this.reason,
  });

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    final isId = app.isIndonesian;

    final title = isId ? 'Izin Mikrofon Diperlukan' : 'Permission Required';
    final message = isId
        ? (reason == PermissionReason.tracking
            ? 'Aplikasi membutuhkan akses mikrofon untuk mendeteksi bacaan Al-Qur’an secara real-time. Silakan aktifkan di Pengaturan.'
            : 'Aplikasi membutuhkan akses mikrofon untuk pencarian suara. Silakan aktifkan di Pengaturan.')
        : (reason == PermissionReason.tracking
            ? 'Microphone access is needed for recitation tracking. Please enable it in Settings.'
            : 'Microphone access is needed for Voice Search. Please enable it in Settings.');

    return AppDialog(
      heroIcon: const AppDialogHeroIcon(
        icon: Icons.mic_off_rounded,
      ),
      title: title,
      subtitle: message,
      primaryAction: AppDialogActionItem(
        label: isId ? 'Buka Pengaturan' : 'Settings',
        onPressed: () {
          Navigator.pop(context);
          openAppSettings();
        },
      ),
      secondaryAction: AppDialogActionItem(
        label: isId ? 'Batal' : 'Cancel',
        onPressed: () => Navigator.pop(context),
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════════
// 2. AI MODEL DOWNLOAD CONSENT DIALOG
// ══════════════════════════════════════════════════════════════════════════════

/// Bilingual dialog asking for user consent before downloading the ~72MB AI speech model on Web.
class ModelDownloadDialog extends StatelessWidget {
  const ModelDownloadDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    final isId = app.isIndonesian;

    final title = isId ? 'Unduh Model Suara AI' : 'Download AI Voice Model';
    final message = isId
        ? 'Pelacakan tilawah membutuhkan model pengenalan suara (~72MB) yang diunduh sekali agar dapat bekerja sepenuhnya secara offline.'
        : 'Voice tracking requires downloading the speech model (~72MB) once to work offline.';

    final bannerText = isId ? 'Ukuran unduhan: ~71 MB' : 'Download size: ~71 MB';

    return AppDialog(
      heroIcon: const AppDialogHeroIcon(
        icon: Icons.cloud_download_rounded,
        iconSize: 36,
      ),
      title: title,
      subtitle: message,
      banner: AppDialogInfoBanner(
        icon: Icons.data_usage_rounded,
        text: bannerText,
      ),
      primaryAction: AppDialogActionItem(
        label: isId ? 'Unduh Sekarang' : 'Download',
        onPressed: () => Navigator.pop(context, true),
      ),
      secondaryAction: AppDialogActionItem(
        label: isId ? 'Batal' : 'Cancel',
        onPressed: () => Navigator.pop(context, false),
      ),
    );
  }
}

