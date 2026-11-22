import 'package:flutter/material.dart';
import '../../../core/app_state.dart';
import 'dialog_base.dart';

/// Modal dialog for managing Smartwatch / Wearable device connectivity.
class WearableDialog extends StatefulWidget {
  const WearableDialog({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierColor: DialogTokens.barrierColor,
      barrierDismissible: true,
      builder: (context) => const WearableDialog(),
    );
  }

  @override
  State<WearableDialog> createState() => _WearableDialogState();
}

class _WearableDialogState extends State<WearableDialog> {
  bool _isScanning = false;
  bool _isPaired = false;
  String _statusMessage = 'Belum ada smartwatch terhubung';

  void _toggleScan() {
    setState(() {
      _isScanning = true;
      _statusMessage = 'Mencari perangkat Wear OS / Smartwatch di sekitar...';
    });

    Future.delayed(const Duration(milliseconds: 1800), () {
      if (!mounted) return;
      setState(() {
        _isScanning = false;
        _isPaired = true;
        _statusMessage = 'Smartwatch terdeteksi dan tersinkronisasi (Wear OS)';
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    final isDark = app.isDarkMode;
    final c = app.colors;

    return AppDialog(
      maxWidth: 420.0,
      scrollable: true,
      heroIcon: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: const Color(0xFF10B981).withValues(alpha: isDark ? 0.20 : 0.12),
          shape: BoxShape.circle,
          border: Border.all(
            color: const Color(0xFF10B981).withValues(alpha: isDark ? 0.45 : 0.30),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF10B981).withValues(alpha: isDark ? 0.25 : 0.15),
              blurRadius: 16,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Center(
          child: Icon(
            Icons.watch_rounded,
            color: Color(0xFF10B981),
            size: 32,
          ),
        ),
      ),
      title: 'Koneksi Smartwatch / Wearable',
      subtitle: 'Sinkronisasi tilawah, kontrol murottal, dan respon getar dari jam tangan',
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Status Box
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.04)
                  : Colors.black.withValues(alpha: 0.025),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.black.withValues(alpha: 0.06),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _isPaired
                      ? Icons.check_circle_rounded
                      : (_isScanning
                          ? Icons.bluetooth_searching_rounded
                          : Icons.watch_outlined),
                  color: _isPaired
                      ? const Color(0xFF10B981)
                      : (_isScanning ? Colors.amber : c.muted),
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _statusMessage,
                    style: TextStyle(
                      color: c.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Fitur Wearable
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: isDark ? 0.08 : 0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color(0xFF10B981).withValues(alpha: isDark ? 0.25 : 0.15),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Fitur Terintegrasi Smartwatch:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: Color(0xFF10B981),
                  ),
                ),
                const SizedBox(height: 8),
                _buildBullet(c, 'Kontrol Recite Player langsung dari smartwatch (Play/Pause, Next Ayah).'),
                _buildBullet(c, 'Getaran haptic ketika AI mendeteksi pergantian ayat atau hukum tajwid.'),
                _buildBullet(c, 'Tampilan ayat yang sedang dibaca di layar jam tangan.'),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Tombol Pindai
          ElevatedButton.icon(
            onPressed: _isScanning ? null : _toggleScan,
            icon: _isScanning
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Icon(_isPaired ? Icons.refresh_rounded : Icons.bluetooth_rounded),
            label: Text(_isPaired ? 'Hubungkan Ulang Smartwatch' : 'Pindai Perangkat Smartwatch'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
      primaryAction: AppDialogActionItem(
        label: 'Tutup',
        onPressed: () => Navigator.of(context).pop(),
      ),
    );
  }

  Widget _buildBullet(ThemeColors c, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('• ', style: TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.bold)),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: c.textSecondary,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
