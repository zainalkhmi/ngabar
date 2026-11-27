import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/app_state.dart';
import '../core/subscription_service.dart';
import '../ui/widgets/dialogs/dialog_base.dart';
import '../ui/widgets/dialogs/subscription_paywall_sheet.dart';
import 'iqro_controller.dart';
import 'iqro_progress_service.dart';
import 'iqro_repository.dart';

/// Pro book-cover grid bottom sheet allowing the user to pick Iqro Jilid (1-6)
/// and Page, or return to Mushaf mode.
class IqroPickerSheet extends StatefulWidget {
  const IqroPickerSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: DialogTokens.barrierColor,
      elevation: 0,
      builder: (_) => const IqroPickerSheet(),
    );
  }

  @override
  State<IqroPickerSheet> createState() => _IqroPickerSheetState();
}

class _IqroPickerSheetState extends State<IqroPickerSheet> {
  late int _selectedJilid;

  static const List<Color> _bookColors = [
    Color(0xFF1740AF), // Jilid 1: Royal Blue
    Color(0xFF056E47), // Jilid 2: Emerald Green
    Color(0xFFB31217), // Jilid 3: Crimson Red
    Color(0xFF7012D4), // Jilid 4: Royal Purple
    Color(0xFFD96B08), // Jilid 5: Warm Orange
    Color(0xFF076D6A), // Jilid 6: Deep Teal
  ];

  @override
  void initState() {
    super.initState();
    _selectedJilid = AppState.instance.iqroJilid;
    IqroProgressService.instance.ensureLoaded();
  }

  Future<void> _openIqroPage(int jilid, int page) async {
    HapticFeedback.selectionClick();
    if (jilid >= 3 && !SubscriptionService.instance.isPremium) {
      await SubscriptionPaywallSheet.show(context);
      return;
    }
    final app = AppState.instance;
    await app.setIqroPosition(jilid, page);
    await app.setIqroMode(true);
    await IqroController.instance.loadPage(jilid, page);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    final selectedVol = IqroRepository.volumes[_selectedJilid - 1];
    final maxPages = selectedVol.totalPages;
    final activeBookColor = _bookColors[_selectedJilid - 1];

    return AppBottomSheet(
      maxHeightFactor: 0.88,
      extraListenable: Listenable.merge([
        app.iqroModeNotifier,
        IqroProgressService.instance,
        SubscriptionService.instance.isPremiumNotifier,
      ]),
      headerBuilder: (context, c, isAr, isDark) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color:
                      activeBookColor.withValues(alpha: isDark ? 0.25 : 0.14),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  Icons.auto_stories_rounded,
                  size: 19,
                  color: activeBookColor,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  app.isIndonesian
                      ? "Pilih Buku Iqro' (Jilid 1–6)"
                      : "Select Iqro' Book (1–6)",
                  style: TextStyle(
                    fontFamily: 'cairo',
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                    color: c.text,
                  ),
                ),
              ),
              if (app.isIqroMode)
                TextButton.icon(
                  onPressed: () async {
                    HapticFeedback.selectionClick();
                    await app.setIqroMode(false);
                    if (context.mounted) Navigator.of(context).pop();
                  },
                  icon: const Icon(
                    Icons.menu_book_rounded,
                    size: 16,
                    color: Color(0xFF10B981),
                  ),
                  label: Text(
                    app.isIndonesian ? 'Mushaf' : 'Mushaf',
                    style: const TextStyle(
                      fontFamily: 'cairo',
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF10B981),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
      builder: (context, c, isAr, isDark) {
        final progress = IqroProgressService.instance;
        final weakLetters = progress.topWeakLetters(limit: 5);
        final isPremium = SubscriptionService.instance.isPremium;
        return Column(
          children: [
            // 3x2 Book Cover Grid (all 6 jilids visible)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: Column(
                children: [
                  Row(
                    children: [
                      for (int i = 0; i < 3; i++) ...[
                        if (i > 0) const SizedBox(width: 8),
                        Expanded(
                          child: _IqroBookTile(
                            jilid: i + 1,
                            totalPages: IqroRepository.volumes[i].totalPages,
                            passedPages: progress.passedCountFor(
                              i + 1,
                              IqroRepository.volumes[i].totalPages,
                            ),
                            showProBadge: !isPremium && (i + 1) >= 3,
                            color: _bookColors[i],
                            isSelected: _selectedJilid == i + 1,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() => _selectedJilid = i + 1);
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      for (int i = 3; i < 6; i++) ...[
                        if (i > 3) const SizedBox(width: 8),
                        Expanded(
                          child: _IqroBookTile(
                            jilid: i + 1,
                            totalPages: IqroRepository.volumes[i].totalPages,
                            passedPages: progress.passedCountFor(
                              i + 1,
                              IqroRepository.volumes[i].totalPages,
                            ),
                            showProBadge: !isPremium,
                            color: _bookColors[i],
                            isSelected: _selectedJilid == i + 1,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() => _selectedJilid = i + 1);
                            },
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),

            // Weak letters analytics strip (if any recorded mistakes)
            if (weakLetters.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
                child: Row(
                  children: [
                    Text(
                      'Perlu Latihan:',
                      style: TextStyle(
                        fontFamily: 'cairo',
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: c.textSecondary,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final w in weakLetters)
                              Container(
                                margin: const EdgeInsets.only(right: 6),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEF4444)
                                      .withValues(alpha: isDark ? 0.2 : 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: const Color(0xFFEF4444)
                                        .withValues(alpha: 0.4),
                                  ),
                                ),
                                child: Text(
                                  '${w.letter} (${w.mistakes}x)',
                                  style: TextStyle(
                                    fontFamily: 'HafsSmart',
                                    fontSize: 13,
                                    color: isDark
                                        ? const Color(0xFFFCA5A5)
                                        : const Color(0xFF991B1B),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            if (!isPremium && _selectedJilid >= 3)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                child: GestureDetector(
                  onTap: () => SubscriptionPaywallSheet.show(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF0E7490), Color(0xFF10B981)],
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.star_rounded,
                          size: 16,
                          color: Color(0xFFFACC15),
                        ),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            "Upgrade PRO untuk akses penuh Ujian & AI Iqro' 3–6",
                            style: TextStyle(
                              fontFamily: 'cairo',
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 16,
                          color: Colors.white,
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // Compact page section header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
              child: Row(
                children: [
                  Text(
                    app.isIndonesian
                        ? "Halaman — Iqro' $_selectedJilid"
                        : "Pages — Iqro' $_selectedJilid",
                    style: TextStyle(
                      fontFamily: 'cairo',
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: c.text,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      app.isIndonesian
                          ? selectedVol.subtitleId
                          : selectedVol.subtitleEn,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: isAr ? TextAlign.left : TextAlign.right,
                      style: TextStyle(
                        fontFamily: 'cairo',
                        fontSize: 11,
                        color: c.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Scrollable Page grid
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                physics: const BouncingScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 6,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 1.30,
                ),
                itemCount: maxPages,
                itemBuilder: (context, idx) {
                  final pageNum = idx + 1;
                  final isCurrent = app.isIqroMode &&
                      app.iqroJilid == _selectedJilid &&
                      app.iqroPage == pageNum;
                  final isPassed =
                      progress.isPagePassed(_selectedJilid, pageNum);
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _openIqroPage(_selectedJilid, pageNum),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: isCurrent
                                ? activeBookColor
                                : (isPassed
                                    ? const Color(0xFF10B981)
                                        .withValues(alpha: isDark ? 0.18 : 0.10)
                                    : (isDark
                                        ? Colors.white.withValues(alpha: 0.05)
                                        : Colors.black
                                            .withValues(alpha: 0.035))),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: isCurrent
                                  ? activeBookColor
                                  : (isPassed
                                      ? const Color(0xFF10B981)
                                          .withValues(alpha: 0.6)
                                      : (isDark
                                          ? Colors.white.withValues(alpha: 0.12)
                                          : Colors.black
                                              .withValues(alpha: 0.08))),
                              width: isCurrent ? 1.6 : 1.0,
                            ),
                            boxShadow: isCurrent
                                ? [
                                    BoxShadow(
                                      color: activeBookColor
                                          .withValues(alpha: 0.35),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ]
                                : null,
                          ),
                          child: Text(
                            '$pageNum',
                            style: TextStyle(
                              fontFamily: 'cairo',
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: isCurrent ? Colors.white : c.text,
                            ),
                          ),
                        ),
                        if (isPassed)
                          const Positioned(
                            top: -4,
                            right: -4,
                            child: Icon(
                              Icons.stars_rounded,
                              size: 14,
                              color: Color(0xFFFACC15),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _IqroBookTile extends StatelessWidget {
  final int jilid;
  final int totalPages;
  final int passedPages;
  final bool showProBadge;
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  const _IqroBookTile({
    required this.jilid,
    required this.totalPages,
    this.passedPages = 0,
    this.showProBadge = false,
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color spineColor = Color.lerp(color, Colors.black, 0.28)!;
    const Color gold = Color(0xFFFACC15);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 170),
        height: 88,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Color.lerp(color, Colors.white, 0.08)!,
              color,
            ],
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? gold : Colors.white.withValues(alpha: 0.20),
            width: isSelected ? 2.2 : 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: isSelected ? 0.42 : 0.20),
              blurRadius: isSelected ? 10 : 5,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Row(
            children: [
              // Book spine strip on left
              Container(
                width: 7,
                color: spineColor,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(6, 6, 6, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Top row: JILID X pill + selected check
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              'JILID $jilid',
                              style: const TextStyle(
                                fontFamily: 'cairo',
                                fontSize: 7.5,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                          if (isSelected)
                            const Icon(
                              Icons.check_circle_rounded,
                              size: 12,
                              color: gold,
                            )
                          else if (showProBadge)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 0.5,
                              ),
                              decoration: BoxDecoration(
                                color: gold,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'PRO',
                                style: TextStyle(
                                  fontFamily: 'cairo',
                                  fontSize: 6.5,
                                  fontWeight: FontWeight.w900,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                            ),
                        ],
                      ),
                      const Spacer(),
                      // Center Arabic Title
                      Text(
                        'إِقْرَأْ $jilid',
                        textDirection: TextDirection.rtl,
                        style: const TextStyle(
                          fontFamily: 'HafsSmart',
                          fontSize: 19,
                          color: Colors.white,
                          height: 1.0,
                          shadows: [
                            Shadow(
                              color: Colors.black45,
                              blurRadius: 4,
                              offset: Offset(0, 1),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      // Bottom: Passed progress or Total pages tag
                      Text(
                        passedPages > 0
                            ? '$passedPages/$totalPages Lulus'
                            : '$totalPages Hal',
                        style: TextStyle(
                          fontFamily: 'cairo',
                          fontSize: 8.5,
                          fontWeight: FontWeight.w600,
                          color: passedPages > 0
                              ? gold
                              : Colors.white.withValues(alpha: 0.85),
                        ),
                      ),
                    ],
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
