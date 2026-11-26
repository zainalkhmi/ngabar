import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/app_state.dart';
import 'dialog_base.dart';

// ══════════════════════════════════════════════════════════════════════════════
// 1. APP GUIDE & HOW-TO SHEET (PANDUAN LENGKAP + TIPS ANTI-STUCK AI)
// ══════════════════════════════════════════════════════════════════════════════

/// Comprehensive interactive guide covering:
/// 1. Core features (AI tracking, Hifz mode, Audio, Voice Search, Majlis, Screen Recording & Social Share).
/// 2. Practical reading tips so the AI tracker stays smooth and never gets stuck.
/// 3. Step-by-step actions when a recitation mistake (Red/Yellow) is detected.
class AppGuideDialog extends StatefulWidget {
  final int initialTab;

  const AppGuideDialog({
    super.key,
    this.initialTab = 0,
  });

  /// Displays the Complete Guide bottom sheet.
  static Future<void> show(
    BuildContext context, {
    int initialTab = 0,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: DialogTokens.barrierColor,
      elevation: 0,
      builder: (_) => AppGuideDialog(initialTab: initialTab),
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('has_seen_app_guide_v1', true);
    await prefs.setBool('has_seen_v1_2_maglis_whats_new', true);
  }

  @override
  State<AppGuideDialog> createState() => _AppGuideDialogState();
}

class _AppGuideDialogState extends State<AppGuideDialog> {
  late int _selectedTab;

  @override
  void initState() {
    super.initState();
    _selectedTab = widget.initialTab.clamp(0, 2);
  }

  @override
  Widget build(BuildContext context) {
    return AppBottomSheet(
      maxHeightFactor: 0.86,
      headerBuilder: (context, c, isAr, isDark) {
        final isId = AppState.instance.isIndonesian;
        final title = isId
            ? 'Panduan Lengkap'
            : (isAr ? 'الدليل الشامل' : 'Complete Guide');
        final subtitle = isId
            ? 'Fitur ngabar, tips membaca agar AI lancar, & cara perbaikan'
            : (isAr
                ? 'الميزات ونصائح القراءة لتجنب توقف التتبع'
                : 'Features, anti-stuck reading tips & mistake recovery');

        return AppModalHeader(
          title: title,
          subtitle: subtitle,
          leading: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFF10B981)
                  .withValues(alpha: isDark ? 0.18 : 0.11),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFF10B981)
                    .withValues(alpha: isDark ? 0.38 : 0.24),
              ),
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.menu_book_rounded,
              color: Color(0xFF10B981),
              size: 20,
            ),
          ),
        );
      },
      builder: (context, c, isAr, isDark) {
        final isId = AppState.instance.isIndonesian;

        final tabLabels = isId
            ? const ['Fitur', 'Anti-Stuck AI', 'Saat Salah']
            : (isAr
                ? const ['الميزات', 'منع التوقف', 'عند الخطأ']
                : const ['Features', 'Anti-Stuck', 'Mistakes']);

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
              child: AppSegmentedPillSelector(
                labels: tabLabels,
                selected: _selectedTab,
                c: c,
                height: 38,
                onSelected: (idx) => setState(() => _selectedTab = idx),
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 16),
                child: switch (_selectedTab) {
                  0 => _buildFeaturesTab(c, isId, isAr, isDark),
                  1 => _buildAntiStuckTab(c, isId, isAr, isDark),
                  _ => _buildMistakesTab(c, isId, isAr, isDark),
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(DialogTokens.buttonRadius),
                    ),
                  ),
                  child: Text(
                    isId ? 'Mengerti' : (isAr ? 'حسناً، فهمت' : 'Got it'),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSectionCard({
    required ThemeColors c,
    required bool isDark,
    required List<Widget> children,
  }) {
    final divider = Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Divider(
        height: 1,
        thickness: 0.7,
        color: c.border.withValues(alpha: isDark ? 0.16 : 0.22),
      ),
    );

    final spaced = <Widget>[];
    for (int i = 0; i < children.length; i++) {
      spaced.add(children[i]);
      if (i < children.length - 1) spaced.add(divider);
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: c.surfaceHigh.withValues(alpha: isDark ? 0.35 : 0.55),
        borderRadius: BorderRadius.circular(DialogTokens.cardRadius),
        border: Border.fromBorderSide(DialogTokens.borderSide(c, isDark)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: spaced,
      ),
    );
  }

  Widget _buildFeaturesTab(
    ThemeColors c,
    bool isId,
    bool isAr,
    bool isDark,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppDialogInfoBanner(
          icon: Icons.tips_and_updates_rounded,
          accentColor: const Color(0xFF10B981),
          textAlign: TextAlign.start,
          text: isId
              ? 'Buka tab "Anti-Stuck AI" untuk tips agar pelacakan AI selalu lancar dan tidak macet saat membaca.'
              : (isAr
                  ? 'افتح تبويب "منع التوقف" لنصائح القراءة السلسة دون توقف التتبع.'
                  : 'Check the "Anti-Stuck" tab for reading tips so AI tracking stays smooth.'),
        ),
        const SizedBox(height: 10),
        _buildSectionCard(
          c: c,
          isDark: isDark,
          children: [
            _buildRow(
              icon: Icons.mic_rounded,
              iconColor: c.primary,
              title: isId
                  ? 'Pelacakan Tilawah AI'
                  : (isAr ? 'تتبع التلاوة بالذكاء الاصطناعي' : 'AI Voice Recitation'),
              c: c,
              extra: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isId
                        ? 'Tekan tombol mikrofon di bawah lalu mulai membaca Al-Qur’an dengan suara jelas.'
                        : (isAr
                            ? 'اضغط زر الميكروفون بالأسفل وابدأ التلاوة بصوت واضح.'
                            : 'Tap the bottom Mic button and start reciting clearly.'),
                    style: TextStyle(
                      color: c.textSecondary,
                      fontSize: 11.6,
                      height: 1.38,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 5,
                    runSpacing: 4,
                    children: [
                      _buildChip(
                        c.green,
                        isId ? 'Hijau: Benar' : (isAr ? 'أخضر: صحيح' : 'Green: Correct'),
                        c,
                        isDark,
                      ),
                      _buildChip(
                        c.warning,
                        isId
                            ? 'Kuning: Tajwid (ketuk)'
                            : (isAr ? 'أصفر: تجويد (اضغط)' : 'Yellow: Tajweed (tap)'),
                        c,
                        isDark,
                      ),
                      _buildChip(
                        c.red,
                        isId
                            ? 'Merah: Salah/Lewat'
                            : (isAr ? 'أحمر: خطأ/تجاوز' : 'Red: Mistake'),
                        c,
                        isDark,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            _buildRow(
              icon: Icons.visibility_off_rounded,
              iconColor: const Color(0xFF6366F1),
              title: isId
                  ? 'Mode Hafalan (Sembunyikan Ayat)'
                  : (isAr ? 'وضع الحفظ (إخفاء الآيات)' : 'Hifz Mode (Hide Verses)'),
              text: isId
                  ? 'Tekan ikon mata untuk menutup teks ayat; kata akan terbuka otomatis saat dibaca benar.'
                  : (isAr
                      ? 'اضغط أيقونة العين لإخفاء الكلمات؛ وتظهر تلقائياً عند قراءتها بشكل صحيح.'
                      : 'Tap the Eye icon to hide words; they reveal automatically as you recite correctly.'),
              c: c,
            ),
            _buildRow(
              icon: Icons.play_circle_fill_rounded,
              iconColor: isDark ? c.gold : const Color(0xFFD97706),
              title: isId
                  ? 'Putar Audio Murottal'
                  : (isAr ? 'تشغيل التلاوة الصوتية' : 'Audio Playback'),
              text: isId
                  ? 'Ketuk nomor ayat untuk memutar murottal ayat, atau ketuk kata untuk mendengar pelafalan per kata.'
                  : (isAr
                      ? 'اضغط رقم الآية لسماع التلاوة، أو اضغط أي كلمة لسماع نطقها.'
                      : 'Tap Ayah number for verse audio, or tap any word to hear its pronunciation.'),
              c: c,
            ),
            _buildRow(
              icon: Icons.graphic_eq_rounded,
              iconColor: const Color(0xFF10B981),
              title: isId
                  ? 'Pencarian Ayat dengan Suara'
                  : (isAr ? 'البحث الصوتي عن الآية' : 'Voice Search'),
              text: isId
                  ? 'Tekan ikon pencarian suara untuk mencari dan langsung melompat ke ayat hanya dengan melafalkannya.'
                  : (isAr
                      ? 'اضغط أيقونة البحث الصوتي للانتقال فوراً إلى أي آية بمجرد تلاوتها.'
                      : 'Tap the Voice Search icon and recite any verse to jump to it instantly.'),
              c: c,
            ),
            _buildRow(
              icon: Icons.groups_rounded,
              iconColor: const Color(0xFF2563EB),
              title: isId
                  ? 'Majelis Quran (Link & Web Browser)'
                  : (isAr ? 'مجلس القرآن (رابط ومتصفح الويب)' : 'Quran Majlis (Link & Web Browser)'),
              text: isId
                  ? 'Tilawah bersama via audio & sinkronisasi mushaf. Bagikan tautan Zoom-style (https://ngabar.vercel.app/kode) dengan jadwal mulai; teman yang belum install aplikasi bisa langsung bergabung via browser HP atau Laptop!'
                  : (isAr
                      ? 'تلاوة جماعية مباشرة بالصوت ومزامنة صفحات المصحف. يمكنك مشاركة رابط المجلس مع موعد الانعقاد والانضمام عبر المتصفح بدون تثبيت التطبيق.'
                      : 'Recite together with voice & synced Mushaf. Share Zoom-style link (https://ngabar.vercel.app/code) with scheduled time; friends without the app can join right inside their web browser!'),
              c: c,
            ),
            _buildRow(
              icon: Icons.videocam_rounded,
              iconColor: const Color(0xFFE11D48),
              title: isId
                  ? 'Rekam Layar, Live & Share Sosmed'
                  : (isAr ? 'تسجيل الشاشة والبث المباشر' : 'Record, Live & Social Share'),
              text: isId
                  ? 'Rekam layar untuk dibagikan ke YouTube, TikTok & Facebook, atau siaran langsung (Live RTMP) dengan opsi encoder ringan aman AI.'
                  : (isAr
                      ? 'سجل تلاوتك وشاركها على يوتيوب وتيك توك وفيسبوك، أو ابدأ بثاً مباشراً RTMP بخيار ترميز خفيف.'
                      : 'Record & share to YouTube, TikTok & Facebook, or go Live via RTMP using the AI-safe light encoder.'),
              c: c,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAntiStuckTab(
    ThemeColors c,
    bool isId,
    bool isAr,
    bool isDark,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppDialogInfoBanner(
          icon: Icons.auto_fix_high_rounded,
          accentColor: const Color(0xFF10B981),
          textAlign: TextAlign.start,
          text: isId
              ? 'AI ngabar membaca bunyi huruf secara berurutan. Ikuti tips berikut agar pelacakan tetap cepat, akurat, dan tidak stuck:'
              : (isAr
                  ? 'يتتبع الذكاء الاصطناعي الحروف بالتسلسل. اتبع هذه النصائح لضمان سلاسة التتبع:'
                  : 'The AI matches phonemes sequentially. Follow these tips to keep tracking smooth and prevent stalls:'),
        ),
        const SizedBox(height: 10),
        _buildSectionCard(
          c: c,
          isDark: isDark,
          children: [
            _buildRow(
              icon: Icons.record_voice_over_rounded,
              iconColor: const Color(0xFF10B981),
              title: isId
                  ? '1. Suara Jelas & Jarak Mic 15–30 cm'
                  : (isAr ? '١. صوت واضح ومسافة مناسبة' : '1. Clear Voice & 15–30 cm Mic Distance'),
              text: isId
                  ? 'Jangan berbisik dan hindari tempat berisik (angin/TV). Suara yang terlalu pelan atau bising membuat huruf mirip sulit dibedakan.'
                  : (isAr
                      ? 'اقرأ بصوت واضح وتجنب الضوضاء الشديدة حتى لا تختلط مخارج الحروف.'
                      : 'Avoid whispering or noisy backgrounds; clear audio prevents phoneme confusion.'),
              c: c,
            ),
            _buildRow(
              icon: Icons.speed_rounded,
              iconColor: const Color(0xFF0EA5E9),
              title: isId
                  ? '2. Tempo Stabil & Ucapkan Akhir Kata'
                  : (isAr ? '٢. وتيرة مستقرة وإتمام أواخر الكلمات' : '2. Steady Pace & Pronounce Word Endings'),
              text: isId
                  ? 'Hindari membaca terlalu cepat atau menelan huruf/harakat akhir kata. Pastikan huruf terakhir sebelum berpindah kata terdengar jelas.'
                  : (isAr
                      ? 'تجنب الإسراع المفرط أو بلع الحرف الأخير من الكلمة قبل الانتقال للتالية.'
                      : 'Avoid rushing or swallowing trailing letters so the AI commits each word cleanly.'),
              c: c,
            ),
            _buildRow(
              icon: Icons.tune_rounded,
              iconColor: const Color(0xFFF59E0B),
              title: isId
                  ? '3. Pahami Mode Tajwid vs Standar'
                  : (isAr ? '٣. الفرق بين وضع التجويد والوضع العادي' : '3. Tajweed vs Standard Mode'),
              text: isId
                  ? '• Tajwid OFF (Standar): Paling toleran dan punya Auto Re-Anchor jika bacaan melompat.\n• Tajwid ON: Menilai mad (2–6 harakat) lebih ketat; baca dengan tempo terukur dan jangan memotong panjang mad.'
                  : (isAr
                      ? '• إيقاف التجويد: أكثر مرونة ويدعم إعادة التموضع التلقائي.\n• تفعيل التجويد: يراقب المدود والمخارج بدقة، فالتزم بزمن المد.'
                      : '• Tajweed OFF: Most forgiving, with automatic re-anchoring.\n• Tajweed ON: Checks Madd timing strictly—keep vowel lengths steady.'),
              c: c,
            ),
            _buildRow(
              icon: Icons.fast_forward_rounded,
              iconColor: const Color(0xFF8B5CF6),
              title: isId
                  ? '4. Cara Cepat Jika Kursor AI Stuck'
                  : (isAr ? '٤. ماذا تفعل إذا توقف المؤشر؟' : '4. Quick Recovery If AI Stalls'),
              text: isId
                  ? '• Ulangi kata yang macet dengan harakat jelas, ATAU terus baca 2–4 kata berikutnya (di mode standar, Auto Re-Anchor otomatis menyusul).\n• Cara tercepat: ketuk langsung ayat di layar untuk memindahkan titik awal AI ke ayat yang sedang Anda baca.'
                  : (isAr
                      ? '• أعد نطق الكلمة بوضوح، أو استمر بقراءة كلمتين إلى ٤ كلمات، أو اضغط مباشرة على الآية لإعادة توجيه التتبع.'
                      : '• Repeat the stalled word clearly, keep reading 2–4 words ahead (auto re-anchor), or tap the verse directly to re-target.'),
              c: c,
            ),
            _buildRow(
              icon: Icons.manage_search_rounded,
              iconColor: const Color(0xFF2563EB),
              title: isId
                  ? '5. Pindah Surat / Ayat Jauh Lewat Menu'
                  : (isAr ? '٥. الانتقال لسورة أو آية بعيدة' : '5. Switching Surah or Distant Verses'),
              text: isId
                  ? 'Jika ingin loncat ke surat/halaman lain, gunakan Daftar Surat atau Voice Search terlebih dulu—jangan langsung membaca surat lain saat AI masih aktif di surat lama.'
                  : (isAr
                      ? 'استخدم قائمة السور أو البحث الصوتي قبل قراءة سورة جديدة بدلاً من القفز المباشر.'
                      : 'Use the Surah list or Voice Search before reciting a different Surah instead of jumping abruptly.'),
              c: c,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMistakesTab(
    ThemeColors c,
    bool isId,
    bool isAr,
    bool isDark,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppDialogInfoBanner(
          icon: Icons.hearing_rounded,
          accentColor: const Color(0xFFF43F5E),
          textAlign: TextAlign.start,
          text: isId
              ? 'Saat kata ditandai Merah atau Kuning, jangan panik—semua petunjuk & rekaman suaramu tersimpan otomatis untuk dievaluasi.'
              : (isAr
                  ? 'عند ظهور علامة حمراء أو صفراء، لا تقلق؛ تُحفظ المقاطع والتفاصيل للمراجعة.'
                  : 'When a word turns Red or Yellow, stay calm—audio snippets and details are saved for review.'),
        ),
        const SizedBox(height: 10),
        _buildSectionCard(
          c: c,
          isDark: isDark,
          children: [
            _buildRow(
              icon: Icons.looks_one_rounded,
              iconColor: const Color(0xFFF43F5E),
              title: isId
                  ? 'Saat Masih Membaca (Live)'
                  : (isAr ? 'أثناء التلاوة المباشرة' : 'While Reciting Live'),
              text: isId
                  ? 'Anda boleh terus menyelesaikan ayat/halaman dulu karena cuplikan suara (~4 detik) otomatis tersimpan. Jika ingin langsung mengulang, ketuk ayat tersebut untuk membaca ulang dari awal ayat.'
                  : (isAr
                      ? 'يمكنك إكمال الآية أولاً لأن مقطع صوتك (~٤ ثوانٍ) يُحفظ تلقائياً، أو اضغط على الآية لإعادتها من البداية.'
                      : 'You can finish the verse (your ~4s audio clip is saved automatically), or tap the verse anytime to restart from it.'),
              c: c,
            ),
            _buildRow(
              icon: Icons.compare_arrows_rounded,
              iconColor: const Color(0xFFF43F5E),
              title: isId
                  ? 'Kata Merah → Bandingkan Bacaan'
                  : (isAr ? 'الكلمة الحمراء ← مقارنة التلاوة' : 'Red Word → Compare Audio'),
              text: isId
                  ? 'Ketuk kata berwarna merah atau tombol "Rekaman Salah • Bandingkan" di layar. Putar "Bacaan Kamu (Terekam)" lalu bandingkan langsung dengan contoh Qari Syekh Al-Husary.'
                  : (isAr
                      ? 'اضغط الكلمة الحمراء أو شريط "مقارنة" لتسمع تسجيلك وتقارنه بتلاوة الشيخ الحصري.'
                      : 'Tap any red word or the "Compare" pill to listen to your own voice side-by-side with Sheikh Al-Husary.'),
              c: c,
            ),
            _buildRow(
              icon: Icons.menu_book_outlined,
              iconColor: c.warning,
              title: isId
                  ? 'Kata Kuning → Cek Detail Tajwid'
                  : (isAr ? 'الكلمة الصفراء ← تفاصيل التجويد' : 'Yellow Word → Tajweed Detail'),
              text: isId
                  ? 'Ketuk kata berwarna kuning untuk melihat huruf/hukum mad yang kurang tepat beserta tombol putar audio pengucapan yang benar.'
                  : (isAr
                      ? 'اضغط الكلمة الصفراء لعرض ملاحظة التجويد والاستماع للنطق الصحيح.'
                      : 'Tap any yellow word to view the Tajweed/Madd breakdown and play the correct pronunciation.'),
              c: c,
            ),
            _buildRow(
              icon: Icons.vibration_rounded,
              iconColor: const Color(0xFF10B981),
              title: isId
                  ? 'Atur Suara & Getar Kesalahan'
                  : (isAr ? 'التحكم في صوت واهتزاز التنبيه' : 'Mistake Sound & Vibration'),
              text: isId
                  ? 'Jika bip/getar terasa mengganggu fokus, Anda bisa mematikan "Peringatan Kesalahan (Suara & Getar)" di menu Pengaturan tanpa menonaktifkan penandaan warna.'
                  : (isAr
                      ? 'يمكنك إيقاف صوت واهتزاز التنبيه من الإعدادات مع بقاء التلوين نشطاً.'
                      : 'You can toggle "Mistake Alert (Sound & Vibrate)" in Settings anytime while keeping highlights active.'),
              c: c,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildChip(Color color, String label, ThemeColors c, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.16 : 0.10),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: color.withValues(alpha: isDark ? 0.38 : 0.28),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 5.5,
            height: 5.5,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4.5),
          Text(
            label,
            style: TextStyle(
              color: isDark ? c.text : color,
              fontSize: 10.6,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRow({
    required IconData icon,
    required Color iconColor,
    required String title,
    required ThemeColors c,
    String? text,
    Widget? extra,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 16.5, color: iconColor),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  color: c.text,
                  fontSize: 12.6,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 2.5),
              if (text != null)
                Text(
                  text,
                  style: TextStyle(
                    color: c.textSecondary,
                    fontSize: 11.6,
                    height: 1.38,
                  ),
                ),
              if (extra != null) extra,
            ],
          ),
        ),
      ],
    );
  }
}

/// Backward compatibility alias
typedef WhatsNewDialog = AppGuideDialog;

// ══════════════════════════════════════════════════════════════════════════════
// 2. MAGLIS HOW-TO EXPLANATION DIALOG
// ══════════════════════════════════════════════════════════════════════════════

class MaglisExplanationDialog extends StatelessWidget {
  const MaglisExplanationDialog({super.key});

  /// Displays the explanation dialog and persists that the user has seen it.
  static Future<void> show(BuildContext context) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: DialogTokens.barrierColor,
      builder: (_) => const MaglisExplanationDialog(),
    );
    final prefs = await SharedPreferences.getInstance();
    AppState.instance.hasSeenMaglisExplanation = true;
    await prefs.setBool('has_seen_maglis_explanation', true);
  }

  @override
  Widget build(BuildContext context) {
    final app = AppState.instance;
    final isId = app.isIndonesian;
    final c = app.colors;

    final purpose = isId
        ? 'Majlis tilawah Al-Qur’an interaktif dengan sambungan suara langsung dan sinkronisasi mushaf bersama (hingga 4 peserta).'
        : 'A live Quran Majlis with open voice & synced Mushaf (up to 4 peers) to recite and correct together.';

    return AppDialog(
      heroIcon: const AppDialogHeroIcon(
        icon: Icons.groups_rounded,
        iconSize: 30,
        padding: 12,
      ),
      title: isId ? 'Majlis Al-Qur’an' : 'The Glorious Quran Majlis',
      banner: AppDialogInfoBanner(
        text: purpose,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildStepRow(
            number: '1',
            title: isId ? 'Kode Majlis (5 Digit)' : '5-Digit Majlis Code',
            body: isId
                ? '• Tuan Rumah: Tekan "Buka Majlis" dan bagikan kode kepada teman.\n• Peserta: Tekan "Gabung Majlis", masukkan kode 5 digit, dan langsung bergabung.'
                : '• Teacher: Taps "Open Majlis" and shares the code.\n• Student: Taps "Join Majlis", types code, and enters instantly.',
            c: c,
          ),
          const SizedBox(height: 10),
          _buildStepRow(
            number: '2',
            title: isId ? 'Tilawah & Saling Memperbaiki' : 'Reciting & Guiding',
            body: isId
                ? '• Panggilan suara aktif secara otomatis untuk saling menyimak dan berbincang.\n• Tekan tombol "Rekam" saat giliran membaca untuk menampilkan mushaf dan bacaan Anda ke semua peserta.'
                : '• Voice call is live for everyone to listen and guide.\n• Tap "Record" to broadcast your recitation and verses live.',
            c: c,
          ),
        ],
      ),
      primaryAction: AppDialogActionItem(
        label: isId ? 'Mengerti, Mulai' : "Got it, let's start",
        onPressed: () {
          Navigator.of(context).pop();
        },
      ),
    );
  }

  Widget _buildStepRow({
    required String number,
    required String title,
    required String body,
    required ThemeColors c,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: c.surfaceHigh,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: c.border.withValues(alpha: 0.35),
          width: 0.9,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: c.primary,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              number,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: c.text,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  body,
                  style: TextStyle(
                    color: c.muted,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
