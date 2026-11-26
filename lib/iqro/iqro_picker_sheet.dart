import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/app_state.dart';
import 'iqro_controller.dart';
import 'iqro_repository.dart';

/// Pro icon-first bottom sheet allowing the user to pick Iqro Jilid (1-6)
/// and Page, or return to Mushaf mode.
class IqroPickerSheet extends StatefulWidget {
  const IqroPickerSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const IqroPickerSheet(),
    );
  }

  @override
  State<IqroPickerSheet> createState() => _IqroPickerSheetState();
}

class _IqroPickerSheetState extends State<IqroPickerSheet> {
  late int _selectedJilid;

  static const List<IconData> _jilidIcons = [
    Icons.looks_one_rounded,
    Icons.looks_two_rounded,
    Icons.looks_3_rounded,
    Icons.looks_4_rounded,
    Icons.looks_5_rounded,
    Icons.looks_6_rounded,
  ];

  @override
  void initState() {
    super.initState();
    _selectedJilid = AppState.instance.iqroJilid;
  }

  Future<void> _openIqroPage(int jilid, int page) async {
    HapticFeedback.selectionClick();
    final app = AppState.instance;
    await app.setIqroPosition(jilid, page);
    await app.setIqroMode(true);
    await IqroController.instance.loadPage(jilid, page);
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    final c = app.colors;
    final isDark = app.isDarkMode;
    final selectedVol = IqroRepository.volumes[_selectedJilid - 1];
    final maxPages = selectedVol.totalPages;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.78,
      ),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(color: c.border.withValues(alpha: 0.5)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: c.textSecondary.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981)
                          .withValues(alpha: isDark ? 0.2 : 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      Icons.auto_stories_rounded,
                      size: 20,
                      color: isDark
                          ? const Color(0xFF34D399)
                          : const Color(0xFF059669),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      "Iqro' 1–6",
                      style: TextStyle(
                        fontFamily: 'cairo',
                        fontSize: 16.5,
                        fontWeight: FontWeight.w800,
                        color: c.text,
                      ),
                    ),
                  ),
                  if (app.isIqroMode)
                    TextButton.icon(
                      onPressed: () async {
                        await app.setIqroMode(false);
                        if (context.mounted) Navigator.of(context).pop();
                      },
                      icon: const Icon(
                        Icons.menu_book_rounded,
                        size: 16,
                        color: Color(0xFF10B981),
                      ),
                      label: const Text(
                        'Mushaf',
                        style: TextStyle(
                          fontFamily: 'cairo',
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF10B981),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // Pro 6-column Icon-only Jilid 1-6 selector
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  for (int idx = 0; idx < 6; idx++) ...[
                    if (idx > 0) const SizedBox(width: 8),
                    Expanded(
                      child: _JilidIconTile(
                        jilid: idx + 1,
                        icon: _jilidIcons[idx],
                        isSelected: _selectedJilid == idx + 1,
                        isDark: isDark,
                        c: c,
                        onTap: () {
                          HapticFeedback.selectionClick();
                          setState(() => _selectedJilid = idx + 1);
                        },
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Compact active Jilid info strip
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 10, 16, 8),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: c.bg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: c.border.withValues(alpha: 0.45)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981)
                          .withValues(alpha: isDark ? 0.22 : 0.14),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      selectedVol.title,
                      style: TextStyle(
                        fontFamily: 'cairo',
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: isDark
                            ? const Color(0xFF34D399)
                            : const Color(0xFF047857),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      selectedVol.subtitleId,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'cairo',
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: c.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$maxPages hal',
                    style: TextStyle(
                      fontFamily: 'cairo',
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: c.textSecondary,
                    ),
                  ),
                ],
              ),
            ),

            // Page grid
            Flexible(
              child: GridView.builder(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
                shrinkWrap: true,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 6,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 1.25,
                ),
                itemCount: maxPages,
                itemBuilder: (context, idx) {
                  final pageNum = idx + 1;
                  final isCurrent = app.isIqroMode &&
                      app.iqroJilid == _selectedJilid &&
                      app.iqroPage == pageNum;
                  return GestureDetector(
                    onTap: () => _openIqroPage(_selectedJilid, pageNum),
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isCurrent ? const Color(0xFF10B981) : c.bg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isCurrent
                              ? const Color(0xFF10B981)
                              : c.border.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Text(
                        '$pageNum',
                        style: TextStyle(
                          fontFamily: 'cairo',
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: isCurrent ? Colors.white : c.text,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _JilidIconTile extends StatelessWidget {
  final int jilid;
  final IconData icon;
  final bool isSelected;
  final bool isDark;
  final ThemeColors c;
  final VoidCallback onTap;

  const _JilidIconTile({
    required this.jilid,
    required this.icon,
    required this.isSelected,
    required this.isDark,
    required this.c,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const Color activeColor = Color(0xFF10B981);
    return Tooltip(
      message: "Iqro' $jilid",
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          height: 52,
          decoration: BoxDecoration(
            gradient: isSelected
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      activeColor,
                      activeColor.withValues(alpha: 0.82),
                    ],
                  )
                : null,
            color: isSelected ? null : c.bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected
                  ? activeColor
                  : c.border.withValues(alpha: 0.55),
              width: isSelected ? 1.5 : 1.0,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: activeColor.withValues(alpha: isDark ? 0.35 : 0.28),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                    ),
                  ]
                : null,
          ),
          child: Center(
            child: Icon(
              icon,
              size: 28,
              color: isSelected
                  ? Colors.white
                  : (isDark ? const Color(0xFFCBD5E1) : const Color(0xFF475569)),
            ),
          ),
        ),
      ),
    );
  }
}
