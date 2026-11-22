import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../../core/app_state.dart';

/// Modal dialog pemindai QR Code untuk bergabung ke dalam Maglis secara instan.
class MaglisQrScannerDialog extends StatefulWidget {
  final bool isId;

  const MaglisQrScannerDialog({super.key, required this.isId});

  static Future<String?> show(BuildContext context, {required bool isId}) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MaglisQrScannerDialog(isId: isId),
    );
  }

  @override
  State<MaglisQrScannerDialog> createState() => _MaglisQrScannerDialogState();
}

class _MaglisQrScannerDialogState extends State<MaglisQrScannerDialog> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
  );

  bool _hasDetected = false;
  final TextEditingController _manualCtrl = TextEditingController();

  @override
  void dispose() {
    _manualCtrl.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleBarcode(BarcodeCapture capture) {
    if (_hasDetected) return;

    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue ?? '';
      // Ekstrak 5 angka kode maglis baik dari teks mentah maupun URL link
      final match = RegExp(r'\b\d{5}\b').firstMatch(raw);
      if (match != null) {
        _hasDetected = true;
        final code = match.group(0)!;
        Navigator.of(context).pop(code);
        break;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = AppState.instance.isDarkMode;
    final isId = widget.isId;
    const emeraldPrimary = Color(0xFF10B981);

    final isDesktop = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux ||
            defaultTargetPlatform == TargetPlatform.macOS);

    return Container(
      height: MediaQuery.of(context).size.height * 0.78,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          // Header Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.qr_code_scanner_rounded,
                      color: emeraldPrimary,
                      size: 22,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      isId ? 'Pindai Kode QR Majlis' : 'Scan Majlis QR Code',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Area Kamera Scanner atau Fallback Desktop
          Expanded(
            child: isDesktop
                ? _buildDesktopFallback(isDark, isId, emeraldPrimary)
                : Stack(
                    alignment: Alignment.center,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: MobileScanner(
                          controller: _controller,
                          onDetect: _handleBarcode,
                          errorBuilder: (context, error) {
                            return _buildCameraError(
                                isDark, isId, emeraldPrimary, error);
                          },
                        ),
                      ),

                      // Overlay Bingkai Pemindai (Scan Window)
                      Container(
                        width: 240,
                        height: 240,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: emeraldPrimary,
                            width: 3.0,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: emeraldPrimary.withValues(alpha: 0.25),
                              blurRadius: 16,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                      ),

                      // Kontrol Kamera (Senter & Balik Kamera)
                      Positioned(
                        bottom: 24,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.65),
                            borderRadius: BorderRadius.circular(30),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.flash_on_rounded,
                                    color: Colors.white, size: 20),
                                onPressed: () => _controller.toggleTorch(),
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                icon: const Icon(Icons.flip_camera_ios_rounded,
                                    color: Colors.white, size: 20),
                                onPressed: () => _controller.switchCamera(),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
          ),

          // Petunjuk di Bagian Bawah
          Padding(
            padding: const EdgeInsets.all(20),
            child: Text(
              isId
                  ? 'Arahkan kamera ke kode QR di layar perangkat teman'
                  : 'Point camera at the QR code on peer\'s screen',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopFallback(
      bool isDark, bool isId, Color emeraldPrimary) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.camera_alt_outlined,
                size: 48,
                color: isDark ? Colors.white54 : Colors.black45),
            const SizedBox(height: 16),
            Text(
              isId
                  ? 'Kamera pemindai tidak tersedia di desktop'
                  : 'Camera scanner unavailable on desktop',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              isId
                  ? 'Masukkan 5 digit kode Majlis secara langsung di bawah ini:'
                  : 'Enter the 5-digit Majlis code directly below:',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                color: isDark ? Colors.white60 : Colors.black54,
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: 220,
              child: TextField(
                controller: _manualCtrl,
                keyboardType: TextInputType.number,
                maxLength: 5,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 4,
                ),
                decoration: InputDecoration(
                  counterText: '',
                  hintText: '12345',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 14),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: emeraldPrimary,
              ),
              onPressed: () {
                final txt = _manualCtrl.text.trim();
                if (txt.length == 5) {
                  Navigator.of(context).pop(txt);
                }
              },
              child: Text(isId ? 'Gunakan Kode' : 'Use Code'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraError(
      bool isDark, bool isId, Color emeraldPrimary, dynamic error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.videocam_off_rounded,
                size: 42, color: Colors.orange),
            const SizedBox(height: 14),
            Text(
              isId
                  ? 'Izin kamera diperlukan untuk memindai'
                  : 'Camera permission required for scanning',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
