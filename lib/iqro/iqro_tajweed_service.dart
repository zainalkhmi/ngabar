import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Tajweed rule classification model adhering to Tarteel QUL tajweed_words specifications
/// and traditional Iqro' curriculum (Iqro' 4, 5, 6).
class IqroTajweedRule {
  final String id;
  final String nameId;
  final String nameAr;
  final String nameEn;
  final String descriptionId;
  final String descriptionEn;
  final int badgeColorValue; // e.g., 0xFF10B981, 0xFF8B5CF6
  final int minDurationMs; // Minimum acoustic duration (ms) for harakat/ghunnah

  const IqroTajweedRule({
    required this.id,
    required this.nameId,
    required this.nameAr,
    required this.nameEn,
    required this.descriptionId,
    required this.descriptionEn,
    required this.badgeColorValue,
    required this.minDurationMs,
  });
}

/// Service providing Tajweed rule detection and authentic Qari word audio lookup
/// powered by QuranCDN / Tarteel QUL audio files.
class IqroTajweedService {
  IqroTajweedService._();
  static final IqroTajweedService instance = IqroTajweedService._();

  // Cached directory for downloaded authentic Quran word audio
  Directory? _audioCacheDir;

  /// Known Tajweed rules defined in accordance with QUL specifications.
  static const IqroTajweedRule ghunnah = IqroTajweedRule(
    id: 'ghunnah',
    nameId: 'Ghunnah Musyaddadah',
    nameAr: 'غُنَّةٌ مُشَدَّدَةٌ',
    nameEn: 'Ghunnah',
    descriptionId: 'Dengungkan nun/mim bertasydid ditahan 2 harakat.',
    descriptionEn: 'Nasalize and hold Noon/Meem with Shaddah for 2 counts.',
    badgeColorValue: 0xFF10B981, // Emerald green
    minDurationMs: 400,
  );

  static const IqroTajweedRule qalqalah = IqroTajweedRule(
    id: 'qalqalah',
    nameId: 'Qalqalah',
    nameAr: 'قَلْقَلَةٌ',
    nameEn: 'Qalqalah',
    descriptionId: 'Pantulkan bunyi huruf Qof, Tho, Ba, Jim, Dal saat sukun.',
    descriptionEn: 'Echo/bounce the sound of Qaf, Ta, Ba, Jeem, Dal on Sukun.',
    badgeColorValue: 0xFF0EA5E9, // Sky blue
    minDurationMs: 150,
  );

  static const IqroTajweedRule ikhfa = IqroTajweedRule(
    id: 'ikhfa',
    nameId: 'Ikhfa Haqiqi',
    nameAr: 'إِخْفَاءٌ حَقِيقِيٌّ',
    nameEn: 'Ikhfa Haqiqi',
    descriptionId: 'Samarkan nun mati/tanwin ke huruf ikhfa dengan dengung.',
    descriptionEn: 'Hide noon sakinah/tanween into ikhfa letter with nasalization.',
    badgeColorValue: 0xFF8B5CF6, // Purple
    minDurationMs: 380,
  );

  static const IqroTajweedRule idghamBighunnah = IqroTajweedRule(
    id: 'idgham_bighunnah',
    nameId: 'Idgham Bighunnah',
    nameAr: 'إِدْغَامٌ بِغُنَّةٍ',
    nameEn: 'Idgham Bi Ghunnah',
    descriptionId: 'Leburkan nun sukun/tanwin ke Ya, Nun, Mim, Waw dengan dengung.',
    descriptionEn: 'Merge noon/tanween into Ya, Noon, Meem, Waw with ghunnah.',
    badgeColorValue: 0xFFEC4899, // Pink
    minDurationMs: 380,
  );

  static const IqroTajweedRule idghamBilaghunnah = IqroTajweedRule(
    id: 'idgham_bilaghunnah',
    nameId: 'Idgham Bilaghunnah',
    nameAr: 'إِدْغَامٌ بِلَا غُنَّةٍ',
    nameEn: 'Idgham Bila Ghunnah',
    descriptionId: 'Leburkan nun sukun/tanwin ke Lam atau Ra tanpa dengung.',
    descriptionEn: 'Merge noon/tanween into Lam or Ra without ghunnah.',
    badgeColorValue: 0xFFF97316, // Orange
    minDurationMs: 200,
  );

  static const IqroTajweedRule iqlab = IqroTajweedRule(
    id: 'iqlab',
    nameId: 'Iqlab',
    nameAr: 'إِقْلَابٌ',
    nameEn: 'Iqlab',
    descriptionId: 'Ganti bunyi nun sukun/tanwin menjadi mim bertasydid/dengung.',
    descriptionEn: 'Convert noon sakin/tanween into meem sound with nasalization.',
    badgeColorValue: 0xFF6366F1, // Indigo
    minDurationMs: 380,
  );

  static const IqroTajweedRule madFari = IqroTajweedRule(
    id: 'mad_fari',
    nameId: "Mad Far'i (Panjang)",
    nameAr: 'مَدٌّ فَرْعِيٌّ',
    nameEn: "Mad Far'i",
    descriptionId: 'Panjangkan 4 - 6 harakat tanda mad alis (~).',
    descriptionEn: 'Elongate 4 to 6 counts for Madd sign (~).',
    badgeColorValue: 0xFFEF4444, // Red
    minDurationMs: 500,
  );

  static const IqroTajweedRule madThabii = IqroTajweedRule(
    id: 'mad_thabii',
    nameId: "Mad Thabi'i",
    nameAr: 'مَدٌّ طَبِيعِيٌّ',
    nameEn: "Mad Thabi'i",
    descriptionId: 'Panjangkan 2 harakat (alif/waw/ya sukun setelah harakat sejenis).',
    descriptionEn: 'Elongate 2 counts naturally.',
    badgeColorValue: 0xFFF59E0B, // Amber
    minDurationMs: 300,
  );

  static const IqroTajweedRule alifLamSyamsiyah = IqroTajweedRule(
    id: 'alif_lam_syamsiyah',
    nameId: 'Alif Lam Syamsiyah',
    nameAr: 'أَلْ شَمْسِيَّةٌ',
    nameEn: 'Idgham Syamsi',
    descriptionId: 'Lam dilebur langsung ke huruf syamsiyah bertasydid.',
    descriptionEn: 'Alif Lam merged directly into the solar letter with shaddah.',
    badgeColorValue: 0xFF059669, // Forest green
    minDurationMs: 200,
  );

  static const IqroTajweedRule alifLamQamariyah = IqroTajweedRule(
    id: 'alif_lam_qamariyah',
    nameId: 'Alif Lam Qamariyah',
    nameAr: 'أَلْ قَمَرِيَّةٌ',
    nameEn: 'Idzhar Qamari',
    descriptionId: 'Bunyi Lam dibaca jelas (idzhar) berharakat sukun.',
    descriptionEn: 'Clear pronunciation of letter Lam with sukun.',
    badgeColorValue: 0xFF0284C7, // Cyan blue
    minDurationMs: 200,
  );

  /// Heuristically detects the most prominent Tajweed rule present in an Iqro Arabic cell.
  IqroTajweedRule? detectRule(String arabicText) {
    if (arabicText.isEmpty) return null;

    // 1. Mad Far'i (Maddah mark ~ / U+0653 or dagger alif with mad)
    if (arabicText.contains('\u0653') ||
        arabicText.contains('~') ||
        arabicText.contains('ۤ')) {
      return madFari;
    }

    // 2. Ghunnah Musyaddadah: Noon with Shaddah (نّ) or Meem with Shaddah (مّ)
    if (RegExp(r'[نnm]\u0651|[مm]\u0651').hasMatch(arabicText)) {
      return ghunnah;
    }

    // 3. Iqlab: Small Meem high (U+06E2 ۠, U+06ED ۭ) or Noon Sakinah followed by Ba
    if (arabicText.contains('\u06E2') ||
        arabicText.contains('\u06ED') ||
        RegExp(r'ن[\u0652\s]*ب|[\u064B\u064C\u064D][\s]*ب').hasMatch(arabicText)) {
      return iqlab;
    }

    // 4. Qalqalah: Ba, Jim, Dal, Ta, Qaf with sukun or at end of word
    // huruf qalqalah: [قطبجد] (Qaf, Tho, Ba, Jim, Dal)
    if (RegExp(r'[قطبجد][\u0652\u06E1]').hasMatch(arabicText)) {
      return qalqalah;
    }

    // 5. Idgham Bighunnah: Noon sukun / tanwin followed by [ينمو]
    if (RegExp(r'(?:ن[\u0652\s]*|[\u064B\u064C\u064D][\s]*)[ينمو]').hasMatch(arabicText)) {
      return idghamBighunnah;
    }

    // 6. Idgham Bilaghunnah: Noon sukun / tanwin followed by [لر]
    if (RegExp(r'(?:ن[\u0652\s]*|[\u064B\u064C\u064D][\s]*)[لر]').hasMatch(arabicText)) {
      return idghamBilaghunnah;
    }

    // 7. Ikhfa: Noon sukun / tanwin followed by 15 ikhfa letters:
    // ت ث ج د ذ ز س ش ص ض ط ظ ف ق ك
    if (RegExp(r'(?:ن[\u0652\s]*|[\u064B\u064C\u064D][\s]*)[تثجدذزسشصضطظفقك]').hasMatch(arabicText)) {
      return ikhfa;
    }

    // 8. Alif Lam Syamsiyah vs Qamariyah
    if (RegExp(r'^(?:ال|ٱل)[تثدذرزسشصضطظلن]').hasMatch(arabicText) &&
        arabicText.contains('\u0651')) {
      return alifLamSyamsiyah;
    }
    if (RegExp(r'^(?:ال|ٱل)[ابغحجكخفهع]').hasMatch(arabicText) ||
        arabicText.startsWith('الْ') ||
        arabicText.startsWith('ٱلْ')) {
      return alifLamQamariyah;
    }

    // 9. Mad Thabi'i: Alif after fathah, Waw sukun after dhommah, Ya sukun after kasrah
    if (RegExp(r'[\u064E]ا|[\u064F]و[\u0652]?|[\u0650]ي[\u0652]?|[\u0670]').hasMatch(arabicText)) {
      return madThabii;
    }

    return null;
  }

  /// In-memory lookup map of frequently used Quranic words in Iqro' to QuranCDN WBW audio.
  /// Format: 'normalized_arabic': 'surah_ayah_word'
  static final Map<String, String> _knownWbwAudioMap = {
    // Al-Fatihah
    'بِسْمِ': '001_001_001',
    'اللَّهِ': '001_001_002',
    'الرَّحْمَٰنِ': '001_001_003',
    'الرَّحِيمِ': '001_001_004',
    'الْحَمْدُ': '001_002_001',
    'لِلَّهِ': '001_002_002',
    'رَبِّ': '001_002_003',
    'الْعَالَمِينَ': '001_002_004',
    'مَالِكِ': '001_004_001',
    'يَوْمِ': '001_004_002',
    'الدِّينِ': '001_004_003',
    'إِيَّاكَ': '001_005_001',
    'نَعْبُدُ': '001_005_002',
    'وَإِيَّاكَ': '001_005_003',
    'نَسْتَعِينُ': '001_005_004',
    'اهْدِنَا': '001_006_001',
    'الصِّرَاطَ': '001_006_002',
    'الْمُسْتَقِيمَ': '001_006_003',
    'صِرَاطَ': '001_007_001',
    'الَّذِينَ': '001_007_002',
    'أَنْعَمْتَ': '001_007_003',
    'عَلَيْهِمْ': '001_007_004',
    'غَيْرِ': '001_007_005',
    'الْمَغْضُوبِ': '001_007_006',
    'وَلَا': '001_007_008',
    'الضَّالِّينَ': '001_007_009',
    // Al-Ikhlas
    'قُلْ': '112_001_001',
    'هُوَ': '112_001_002',
    'أَحَدٌ': '112_001_004',
    'الصَّمَدُ': '112_002_002',
    'لَمْ': '112_003_001',
    'يَلِدْ': '112_003_002',
    'وَلَمْ': '112_003_003',
    'يُولَدْ': '112_003_004',
    'يَكُنْ': '112_004_002',
    'لَهُ': '112_004_003',
    'كُفُوًا': '112_004_004',
    // Al-Falaq / An-Nas & Common Iqro 4-6 Quran words
    'أَعُوذُ': '113_001_002',
    'بِرَبِّ': '113_001_003',
    'الْفَلَقِ': '113_001_004',
    'مِنْ': '113_002_001',
    'شَرِّ': '113_002_002',
    'مَا': '113_002_003',
    'خَلَقَ': '113_002_004',
    'غَاسِقٍ': '113_003_002',
    'إِذَا': '113_003_003',
    'وَقَبَ': '113_003_004',
    'النَّفَّاثَاتِ': '113_004_002',
    'فِي': '113_004_003',
    'الْعُقَدِ': '113_004_004',
    'حَاسِدٍ': '113_005_002',
    'حَسَدَ': '113_005_004',
    'النَّاسِ': '114_001_004',
    'مَلِكِ': '114_002_001',
    'إِلَٰهِ': '114_003_001',
    'الْوَسْوَاسِ': '114_004_002',
    'الْخَنَّاسِ': '114_004_003',
    'يُوَسْوِسُ': '114_005_002',
    'صُدُورِ': '114_005_004',
    'الْجِنَّةِ': '114_006_002',
  };

  /// Clean Arabic word to key for audio lookup
  String _cleanKey(String text) {
    return text.replaceAll(RegExp(r'[\s=\.\,\-\–]'), '').trim();
  }

  /// Resolves authentic word-by-word Quran recitation audio for an Arabic word.
  /// First checks local disk cache, then in-memory map, then Quran.com API search.
  /// Returns a local file path or streamable QuranCDN URL, or null if unresolvable.
  Future<String?> resolveQuranWordAudio(String arabicText) async {
    final clean = _cleanKey(arabicText);
    if (clean.isEmpty) return null;

    // Check if we have a direct mapped identifier
    String? wbwId = _knownWbwAudioMap[clean];

    // If not in static map, try looking up via Quran.com search API if online
    if (wbwId == null) {
      wbwId = await _queryQuranWbwId(clean);
    }

    if (wbwId == null) return null;

    final cdnUrl = 'https://audio.qurancdn.com/wbw/$wbwId.mp3';

    // On web or platforms without dart:io directory support, return streamable URL
    if (kIsWeb) {
      return cdnUrl;
    }

    try {
      if (_audioCacheDir == null) {
        final docs = await getApplicationDocumentsDirectory();
        _audioCacheDir = Directory('${docs.path}/iqro_quran_audio');
        if (!await _audioCacheDir!.exists()) {
          await _audioCacheDir!.create(recursive: true);
        }
      }

      final cachedFile = File('${_audioCacheDir!.path}/$wbwId.mp3');
      if (await cachedFile.exists() && await cachedFile.length() > 500) {
        return cachedFile.path;
      }

      // Download and cache in background
      final response = await http.get(Uri.parse(cdnUrl)).timeout(
        const Duration(seconds: 4),
      );
      if (response.statusCode == 200 && response.bodyBytes.length > 500) {
        await cachedFile.writeAsBytes(response.bodyBytes);
        return cachedFile.path;
      }
    } catch (e) {
      debugPrint('[IqroTajweedService] Cache error, streaming: $e');
    }

    // Return direct URL as reliable fallback
    return cdnUrl;
  }

  /// Queries Quran.com API v4 for word location (surah_ayah_word)
  Future<String?> _queryQuranWbwId(String arabicWord) async {
    try {
      final uri = Uri.parse(
        'https://api.quran.com/api/v4/search?q=${Uri.encodeComponent(arabicWord)}&size=1',
      );
      final res = await http.get(uri).timeout(const Duration(seconds: 2));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        final results = data['search']?['results'] as List?;
        if (results != null && results.isNotEmpty) {
          final first = results.first;
          final verseKey = first['verse_key'] as String?; // e.g. "1:1"
          if (verseKey != null && verseKey.contains(':')) {
            final parts = verseKey.split(':');
            final surah = int.tryParse(parts[0]) ?? 1;
            final ayah = int.tryParse(parts[1]) ?? 1;
            final sStr = surah.toString().padLeft(3, '0');
            final aStr = ayah.toString().padLeft(3, '0');
            return '${sStr}_${aStr}_001';
          }
        }
      }
    } catch (_) {}
    return null;
  }
}
