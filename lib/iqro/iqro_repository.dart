import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'iqro_tajweed_service.dart';

/// Metadata for each Iqro volume (Jilid 1-6).
class IqroVolumeInfo {
  final int jilid;
  final int totalPages;
  final String title;
  final String subtitleId;
  final String subtitleEn;

  const IqroVolumeInfo({
    required this.jilid,
    required this.totalPages,
    required this.title,
    required this.subtitleId,
    required this.subtitleEn,
  });
}

/// A single cell/item on an Iqro page.
class IqroCellData {
  final int orderId;
  final int row;
  final int col;
  final String arabic;
  final String latin;
  final bool inQuran;
  final String? mushafArabic;

  const IqroCellData({
    required this.orderId,
    required this.row,
    required this.col,
    required this.arabic,
    required this.latin,
    this.inQuran = false,
    this.mushafArabic,
  });

  factory IqroCellData.fromJson(Map<String, dynamic> json) {
    final pos = json['position'] as Map<String, dynamic>? ?? const {};
    final arabic = (json['arabic'] as String? ?? '').trim();
    final bool rawInQuran = json['inQuran'] as bool? ?? false;
    final snippet = IqroTajweedService.instance.resolveSnippetSync(arabic);
    final bool isQuran = rawInQuran ||
        arabic.contains('○') ||
        arabic.contains('۝') ||
        arabic.contains('...') ||
        arabic.contains('…') ||
        snippet != null ||
        IqroTajweedService.instance.hasQuranSnippet(arabic);

    return IqroCellData(
      orderId: (json['order_id'] as num?)?.toInt() ?? 0,
      row: (pos['row'] as num?)?.toInt() ?? 1,
      col: (pos['col'] as num?)?.toInt() ?? 1,
      arabic: arabic,
      latin: (json['latin'] as String? ?? '').trim(),
      inQuran: isQuran,
      mushafArabic: snippet?.mushafText,
    );
  }
}

/// A single page of Iqro (from dyazincahya/iqro-json).
class IqroPageData {
  final int jilid;
  final int page;
  final String levelTitle;
  final String topicArab;
  final String topicLatin;
  final String instructionId;
  final String instructionEn;
  final String instructionAr;
  final List<IqroCellData> content;

  const IqroPageData({
    required this.jilid,
    required this.page,
    required this.levelTitle,
    required this.topicArab,
    required this.topicLatin,
    required this.instructionId,
    required this.instructionEn,
    required this.instructionAr,
    required this.content,
  });

  /// Groups cells by row number in ascending row order, with cells ordered by col.
  List<List<IqroCellData>> get rows {
    final Map<int, List<IqroCellData>> grouped = {};
    for (final cell in content) {
      grouped.putIfAbsent(cell.row, () => []).add(cell);
    }
    final sortedKeys = grouped.keys.toList()..sort();
    return [
      for (final r in sortedKeys)
        (grouped[r]!..sort((a, b) => a.col.compareTo(b.col))),
    ];
  }
}

/// Lazy-loaded repository for bundled Iqro JSON data (Jilid 1-6).
/// Loaded only when Iqro mode is accessed, keeping zero memory overhead in Mushaf mode.
class IqroRepository {
  IqroRepository._();
  static final IqroRepository instance = IqroRepository._();

  static const List<IqroVolumeInfo> volumes = [
    IqroVolumeInfo(
      jilid: 1,
      totalPages: 32,
      title: "Iqro' 1",
      subtitleId: 'Huruf Hijaiyah berharakat Fathah',
      subtitleEn: 'Hijaiyah letters with Fathah',
    ),
    IqroVolumeInfo(
      jilid: 2,
      totalPages: 30,
      title: "Iqro' 2",
      subtitleId: 'Huruf bersambung & bacaan panjang (Mad)',
      subtitleEn: 'Connected letters & Mad elongation',
    ),
    IqroVolumeInfo(
      jilid: 3,
      totalPages: 30,
      title: "Iqro' 3",
      subtitleId: 'Harakat Kasrah, Dammah & Mad Thabi\'i',
      subtitleEn: 'Kasrah, Dammah & natural elongation',
    ),
    IqroVolumeInfo(
      jilid: 4,
      totalPages: 30,
      title: "Iqro' 4",
      subtitleId: 'Tanwin, Sukun & Qalqalah',
      subtitleEn: 'Tanwin, Sukun & Qalqalah',
    ),
    IqroVolumeInfo(
      jilid: 5,
      totalPages: 30,
      title: "Iqro' 5",
      subtitleId: 'Alif Lam, Tasydid & Idgham',
      subtitleEn: 'Alif Lam, Shaddah & Idgham',
    ),
    IqroVolumeInfo(
      jilid: 6,
      totalPages: 30,
      title: "Iqro' 6",
      subtitleId: 'Ikhfa, Waqaf & bacaan bertajwid lengkap',
      subtitleEn: 'Ikhfa, Waqaf & full Tajweed practice',
    ),
  ];

  Map<String, dynamic>? _rawRoot;
  final Map<String, IqroPageData> _pageCache = {};

  Future<void> _ensureLoaded() async {
    if (_rawRoot != null) return;
    await IqroTajweedService.instance.ensureLoaded();
    final jsonStr = await rootBundle.loadString('assets/iqro/iqro_data.json');
    _rawRoot = json.decode(jsonStr) as Map<String, dynamic>;
  }

  int pageCountFor(int jilid) {
    final idx = jilid.clamp(1, 6) - 1;
    return volumes[idx].totalPages;
  }

  Future<IqroPageData?> getPage(int jilid, int page) async {
    await _ensureLoaded();
    final key = '$jilid-$page';
    final cached = _pageCache[key];
    if (cached != null) return cached;

    final jilidMap = _rawRoot?[jilid.toString()] as Map<String, dynamic>?;
    final pageJson = jilidMap?[page.toString()] as Map<String, dynamic>?;
    if (pageJson == null) return null;

    final topic = pageJson['topic'] as Map<String, dynamic>? ?? const {};
    final rawContent = pageJson['content'] as List<dynamic>? ?? const [];
    final cells = rawContent
        .whereType<Map<String, dynamic>>()
        .map(IqroCellData.fromJson)
        .where((c) => c.arabic.isNotEmpty)
        .toList();

    final parsed = IqroPageData(
      jilid: jilid,
      page: page,
      levelTitle: pageJson['level_title'] as String? ?? "IQRO' $jilid",
      topicArab: (topic['arab'] as String? ?? '').trim(),
      topicLatin: (topic['latin'] as String? ?? '').trim(),
      instructionId: (pageJson['instruction_id'] as String? ?? '').trim(),
      instructionEn: (pageJson['instruction_en'] as String? ?? '').trim(),
      instructionAr: (pageJson['instruction_ar'] as String? ?? '').trim(),
      content: cells,
    );
    _pageCache[key] = parsed;
    return parsed;
  }
}
