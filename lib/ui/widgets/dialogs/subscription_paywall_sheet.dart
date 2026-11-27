import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/app_state.dart';
import '../../../core/subscription_service.dart';

/// Tarteel-inspired Premium Paywall sheet with Google Play Billing
/// (Android/iOS) and QRIS fallback (Web / direct APK).
class SubscriptionPaywallSheet extends StatefulWidget {
  const SubscriptionPaywallSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const SubscriptionPaywallSheet(),
    );
  }

  @override
  State<SubscriptionPaywallSheet> createState() =>
      _SubscriptionPaywallSheetState();
}

class _SubscriptionPaywallSheetState extends State<SubscriptionPaywallSheet> {
  bool _isYearly = true;
  bool _showQrisFallback = false;

  Future<void> _onSubscribeTap() async {
    HapticFeedback.mediumImpact();
    final sub = SubscriptionService.instance;
    final productId = _isYearly
        ? SubscriptionService.yearlyProductId
        : SubscriptionService.monthlyProductId;

    final launchedStore = await sub.purchaseStorePlan(productId);
    if (!launchedStore && mounted) {
      setState(() => _showQrisFallback = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sub = SubscriptionService.instance;
    final app = AppState.instance;
    final isDark = app.isDarkMode;

    return ListenableBuilder(
      listenable: Listenable.merge([
        sub,
        sub.isPremiumNotifier,
        sub.isBusyNotifier,
      ]),
      builder: (context, _) {
        final yearlyProd = sub.productFor(SubscriptionService.yearlyProductId);
        final monthlyProd =
            sub.productFor(SubscriptionService.monthlyProductId);

        final yearlyPrice = yearlyProd?.price ?? 'Rp 199.000';
        final monthlyPrice = monthlyProd?.price ?? 'Rp 29.000';
        final isBusy = sub.isBusyNotifier.value;

        return Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.92,
          ),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0B1118) : const Color(0xFFF8FAFC),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Top Tarteel-style emerald/teal gradient hero banner
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(22, 16, 22, 22),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFF0E7490),
                          Color(0xFF10B981),
                        ],
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Center(
                          child: Container(
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.4),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Row(
                                    children: [
                                      Text(
                                        'UPGRADE KE\nPREMIUM',
                                        style: TextStyle(
                                          fontFamily: 'cairo',
                                          fontSize: 22,
                                          height: 1.15,
                                          fontWeight: FontWeight.w900,
                                          color: Colors.white,
                                        ),
                                      ),
                                      SizedBox(width: 8),
                                      Icon(
                                        Icons.star_rounded,
                                        color: Color(0xFFFACC15),
                                        size: 28,
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'HAFALKAN & NGAJI\nLEBIH BANYAK',
                                    style: TextStyle(
                                      fontFamily: 'cairo',
                                      fontSize: 13.5,
                                      height: 1.2,
                                      fontWeight: FontWeight.w700,
                                      color:
                                          Colors.white.withValues(alpha: 0.92),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.16),
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.bolt_rounded,
                                size: 44,
                                color: Color(0xFFA7F3D0),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
                    child: _showQrisFallback
                        ? _buildQrisFallback(
                            isDark: isDark,
                            price: _isYearly ? yearlyPrice : monthlyPrice,
                            planLabel:
                                _isYearly ? 'Tahunan (1 Tahun)' : 'Bulanan',
                            sub: sub,
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                "Ngabar Premium membantu Anda menghafal, murojaah Al-Qur'an, dan belajar Iqro' lebih cepat dan akurat!",
                                style: TextStyle(
                                  fontFamily: 'cairo',
                                  fontSize: 13,
                                  height: 1.4,
                                  color: isDark
                                      ? const Color(0xFFCBD5E1)
                                      : const Color(0xFF475569),
                                ),
                              ),
                              const SizedBox(height: 14),

                              // Annual Plan Card (Hemat 43% - Paling Hemat)
                              _PlanCard(
                                headerText: 'Hemat 43% - Ditagih Tahunan',
                                headerActiveColor: const Color(0xFF34D399),
                                isSelected: _isYearly,
                                isDark: isDark,
                                badgeText: 'Paling Hemat',
                                strikePrice: 'Rp 348.000',
                                mainPrice: '$yearlyPrice Per Tahun',
                                subPrice: 'Rp 16.583 Per Bulan',
                                onTap: () => setState(() => _isYearly = true),
                              ),
                              const SizedBox(height: 12),

                              // Monthly Plan Card
                              _PlanCard(
                                headerText: 'Ditagih Bulanan',
                                headerActiveColor: const Color(0xFF34D399),
                                isSelected: !_isYearly,
                                isDark: isDark,
                                mainPrice: '$monthlyPrice Per Bulan',
                                onTap: () => setState(() => _isYearly = false),
                              ),

                              const SizedBox(height: 14),

                              // Premium Benefits summary
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? const Color(0xFF131C26)
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: isDark
                                        ? Colors.white.withValues(alpha: 0.08)
                                        : Colors.black.withValues(alpha: 0.06),
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    _BenefitRow(
                                      text:
                                          'Deteksi Tajwid AI Real-Time & Evaluasi Suara',
                                      isDark: isDark,
                                    ),
                                    const SizedBox(height: 6),
                                    _BenefitRow(
                                      text:
                                          'Rekam Layar & YouTube Live Connect',
                                      isDark: isDark,
                                    ),
                                    const SizedBox(height: 6),
                                    _BenefitRow(
                                      text:
                                          "Iqro' 3–6 AI, Mode Ujian & Buat Room Majlis",
                                      isDark: isDark,
                                    ),
                                  ],
                                ),
                              ),

                              if (sub.lastError != null) ...[
                                const SizedBox(height: 10),
                                Text(
                                  sub.lastError!,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontFamily: 'cairo',
                                    fontSize: 12,
                                    color: Color(0xFFEF4444),
                                  ),
                                ),
                              ],

                              const SizedBox(height: 14),
                              Center(
                                child: Text(
                                  sub.storeAvailable
                                      ? 'Batalkan kapan saja melalui Play Store'
                                      : 'Pembayaran via Play Store / QRIS Instan',
                                  style: TextStyle(
                                    fontFamily: 'cairo',
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: isDark
                                        ? const Color(0xFFE2E8F0)
                                        : const Color(0xFF334155),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),

                              // Primary Gradient LANGGANAN CTA
                              GestureDetector(
                                onTap: isBusy ? null : _onSubscribeTap,
                                child: Container(
                                  height: 50,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      colors: [
                                        Color(0xFF38BDF8),
                                        Color(0xFF34D399),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(25),
                                    boxShadow: [
                                      BoxShadow(
                                        color: const Color(0xFF10B981)
                                            .withValues(alpha: 0.35),
                                        blurRadius: 12,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: isBusy
                                      ? const SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.5,
                                            color: Colors.black87,
                                          ),
                                        )
                                      : const Text(
                                          'LANGGANAN',
                                          style: TextStyle(
                                            fontFamily: 'cairo',
                                            fontSize: 15.5,
                                            fontWeight: FontWeight.w900,
                                            color: Color(0xFF0F172A),
                                            letterSpacing: 0.8,
                                          ),
                                        ),
                                ),
                              ),

                              const SizedBox(height: 6),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  if (sub.storeAvailable)
                                    TextButton(
                                      onPressed:
                                          isBusy ? null : sub.restorePurchases,
                                      child: Text(
                                        'Pulihkan',
                                        style: TextStyle(
                                          fontFamily: 'cairo',
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w700,
                                          color: isDark
                                              ? const Color(0xFF94A3B8)
                                              : const Color(0xFF64748B),
                                        ),
                                      ),
                                    ),
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(context).pop(),
                                    child: Text(
                                      'LAIN KALI',
                                      style: TextStyle(
                                        fontFamily: 'cairo',
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w800,
                                        color: isDark
                                            ? Colors.white
                                            : const Color(0xFF1E293B),
                                      ),
                                    ),
                                  ),
                                ],
                              ),

                              Text(
                                'Pembayaran akan ditagih setelah mengonfirmasi pembelian. Langganan bulanan atau tahunan dapat dibatalkan kapan saja hingga 24 jam sebelum perpanjangan.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontFamily: 'cairo',
                                  fontSize: 10.5,
                                  height: 1.35,
                                  color: isDark
                                      ? const Color(0xFF64748B)
                                      : const Color(0xFF94A3B8),
                                ),
                              ),
                            ],
                          ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildQrisFallback({
    required bool isDark,
    required String price,
    required String planLabel,
    required SubscriptionService sub,
  }) {
    return Column(
      children: [
        Text(
          'Pembayaran QRIS — $planLabel',
          style: TextStyle(
            fontFamily: 'cairo',
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: isDark ? Colors.white : const Color(0xFF0F172A),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Total: $price',
          style: const TextStyle(
            fontFamily: 'cairo',
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Color(0xFF10B981),
          ),
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Image.asset(
            'assets/qris.png',
            width: 220,
            height: 220,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Icon(
              Icons.qr_code_2_rounded,
              size: 140,
              color: Color(0xFF10B981),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Scan QRIS di atas melalui GoPay, OVO, DANA, ShopeePay, atau Mobile Banking. Setelah pembayaran berhasil, ketuk tombol konfirmasi.',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily: 'cairo',
            fontSize: 11.5,
            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => setState(() => _showQrisFallback = false),
                child: const Text(
                  'Kembali',
                  style: TextStyle(fontFamily: 'cairo'),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.white,
                ),
                onPressed: () async {
                  final id = _isYearly
                      ? SubscriptionService.yearlyProductId
                      : SubscriptionService.monthlyProductId;
                  await sub.activateWithCode(id);
                  if (mounted) Navigator.of(context).pop();
                },
                child: const Text(
                  'Konfirmasi Bayar',
                  style: TextStyle(
                    fontFamily: 'cairo',
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _PlanCard extends StatelessWidget {
  final String headerText;
  final Color headerActiveColor;
  final bool isSelected;
  final bool isDark;
  final String? badgeText;
  final String? strikePrice;
  final String mainPrice;
  final String? subPrice;
  final VoidCallback onTap;

  const _PlanCard({
    required this.headerText,
    required this.headerActiveColor,
    required this.isSelected,
    required this.isDark,
    this.badgeText,
    this.strikePrice,
    required this.mainPrice,
    this.subPrice,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = isSelected
        ? headerActiveColor
        : (isDark
            ? Colors.white.withValues(alpha: 0.14)
            : Colors.black.withValues(alpha: 0.12));

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF131C26) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor, width: isSelected ? 1.8 : 1.0),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected
                    ? headerActiveColor
                    : (isDark
                        ? const Color(0xFF475569)
                        : const Color(0xFFCBD5E1)),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(12)),
              ),
              child: Text(
                headerText,
                style: TextStyle(
                  fontFamily: 'cairo',
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: isSelected
                      ? const Color(0xFF0F172A)
                      : (isDark ? Colors.white : const Color(0xFF1E293B)),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Icon(
                    isSelected
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_off_rounded,
                    color: isSelected
                        ? headerActiveColor
                        : (isDark
                            ? const Color(0xFF64748B)
                            : const Color(0xFF94A3B8)),
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (strikePrice != null)
                          Text(
                            strikePrice!,
                            style: TextStyle(
                              fontFamily: 'cairo',
                              fontSize: 12.5,
                              decoration: TextDecoration.lineThrough,
                              color: isDark
                                  ? const Color(0xFF94A3B8)
                                  : const Color(0xFF64748B),
                            ),
                          ),
                        Text(
                          mainPrice,
                          style: TextStyle(
                            fontFamily: 'cairo',
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            color: isDark
                                ? Colors.white
                                : const Color(0xFF0F172A),
                          ),
                        ),
                        if (subPrice != null)
                          Text(
                            subPrice!,
                            style: TextStyle(
                              fontFamily: 'cairo',
                              fontSize: 12.5,
                              color: isDark
                                  ? const Color(0xFFCBD5E1)
                                  : const Color(0xFF475569),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (badgeText != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFACC15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        badgeText!,
                        style: const TextStyle(
                          fontFamily: 'cairo',
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF0F172A),
                        ),
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

class _BenefitRow extends StatelessWidget {
  final String text;
  final bool isDark;

  const _BenefitRow({required this.text, required this.isDark});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(
          Icons.check_circle_rounded,
          size: 16,
          color: Color(0xFF10B981),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontFamily: 'cairo',
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color:
                  isDark ? const Color(0xFFE2E8F0) : const Color(0xFF334155),
            ),
          ),
        ),
      ],
    );
  }
}
