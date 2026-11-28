import 'dart:math' as math;
import 'dart:typed_data';

enum TilawahMaqam {
  bayyati,
  hijaz,
  nahawand,
  rast,
}

class MaqamAnalysisResult {
  final TilawahMaqam maqam;
  final int similarityPct;
  final List<double> userCurve;
  final List<double> referenceCurve;
  final double avgHz;

  const MaqamAnalysisResult({
    required this.maqam,
    required this.similarityPct,
    required this.userCurve,
    required this.referenceCurve,
    required this.avgHz,
  });
}

/// Lightweight F0 pitch tracker & Dynamic Time Warping (DTW) contour matcher
/// for Tilawah Maqam training (Bayyati, Hijaz, Nahawand, Rast).
/// Zero impact on Sherpa-ONNX AI detection.
class PitchMaqamAnalyzer {
  PitchMaqamAnalyzer._();
  static final PitchMaqamAnalyzer instance = PitchMaqamAnalyzer._();

  static const int maxCurvePoints = 64;

  final List<double> _rawHz = [];
  List<double> get rawHz => List.unmodifiable(_rawHz);

  // Normalized semitone melodic contour templates (-6..+6 semitones)
  static const Map<TilawahMaqam, List<double>> maqamContours = {
    TilawahMaqam.bayyati: [
      0.0, 1.5, 2.5, 2.0, 1.0, 2.5, 3.5, 2.0, 1.0, 0.0, -0.5, 0.0
    ],
    TilawahMaqam.hijaz: [
      0.0, 1.0, 4.0, 5.0, 4.0, 1.0, 3.5, 4.5, 2.0, 1.0, 0.0, 0.0
    ],
    TilawahMaqam.nahawand: [
      0.0, 2.0, 3.0, 5.0, 4.5, 3.0, 2.0, 3.0, 1.5, 0.5, 0.0, -0.5
    ],
    TilawahMaqam.rast: [
      0.0, 2.0, 3.5, 5.0, 6.0, 5.0, 3.5, 2.0, 3.0, 1.5, 0.0, 0.0
    ],
  };

  static String maqamName(TilawahMaqam m) => switch (m) {
        TilawahMaqam.bayyati => 'Bayyati',
        TilawahMaqam.hijaz => 'Hijaz',
        TilawahMaqam.nahawand => 'Nahawand',
        TilawahMaqam.rast => 'Rast',
      };

  static String maqamDescription(TilawahMaqam m) => switch (m) {
        TilawahMaqam.bayyati =>
          'Lembut, tenang & khusyuk — umum dipakai membuka tilawah',
        TilawahMaqam.hijaz =>
          'Tajam, menyentuh & dramatis dengan lompatan interval khas',
        TilawahMaqam.nahawand =>
          'Sedih, syahdu & halus — cocok untuk ayat doa & muhasabah',
        TilawahMaqam.rast =>
          'Tegas, berwibawa & cerah dengan nada naik bertahap',
      };

  void reset() => _rawHz.clear();

  /// Passively extracts one F0 sample from a 16kHz Float32 PCM chunk.
  void onAudioChunk(Float32List chunk) {
    if (chunk.length < 512) return;
    final hz = estimatePitchHz(chunk, 16000);
    if (hz > 0) {
      _rawHz.add(hz);
      if (_rawHz.length > maxCurvePoints) {
        _rawHz.removeAt(0);
      }
    }
  }

  /// Fast autocorrelation F0 estimator (80 Hz .. 450 Hz) decimated by 2 for speed.
  static double estimatePitchHz(Float32List samples, int sampleRate) {
    // Take at most 1024 samples from the middle of chunk
    final int len = math.min(samples.length, 1024);
    final int offset = (samples.length - len) ~/ 2;

    double sumSq = 0.0;
    for (int i = 0; i < len; i++) {
      final s = samples[offset + i];
      sumSq += s * s;
    }
    final double rms = math.sqrt(sumSq / len);
    if (rms < 0.015) return 0.0;

    // Decimate by 2 -> effective rate 8000 Hz
    const int step = 2;
    final int effRate = sampleRate ~/ step;
    final int minLag = effRate ~/ 450; // ~17
    final int maxLag = effRate ~/ 80; // ~100
    final int dLen = len ~/ step;
    if (maxLag >= dLen - 4) return 0.0;

    int bestLag = 0;
    double bestCorr = 0.0;
    for (int lag = minLag; lag <= maxLag; lag++) {
      double num = 0.0;
      double den1 = 0.0;
      double den2 = 0.0;
      final int limit = dLen - lag;
      for (int i = 0; i < limit; i++) {
        final a = samples[offset + i * step];
        final b = samples[offset + (i + lag) * step];
        num += a * b;
        den1 += a * a;
        den2 += b * b;
      }
      final denom = math.sqrt(den1 * den2);
      if (denom > 1e-6) {
        final corr = num / denom;
        if (corr > bestCorr) {
          bestCorr = corr;
          bestLag = lag;
        }
      }
    }

    if (bestCorr < 0.55 || bestLag == 0) return 0.0;
    return effRate / bestLag;
  }

  /// Analyzes the captured pitch contour against [maqam] using Dynamic Time Warping.
  MaqamAnalysisResult analyzeAgainst(TilawahMaqam maqam) {
    final ref = maqamContours[maqam]!;
    if (_rawHz.length < 3) {
      return MaqamAnalysisResult(
        maqam: maqam,
        similarityPct: 0,
        userCurve: const [],
        referenceCurve: ref,
        avgHz: 0,
      );
    }

    final avgHz = _rawHz.reduce((a, b) => a + b) / _rawHz.length;
    // Convert Hz to relative semitones centered on user's average pitch
    final userSemitones = _rawHz.map((hz) {
      final st = 12.0 * (math.log(hz / avgHz) / math.ln2);
      return st.clamp(-6.0, 6.0);
    }).toList();

    final dist = _dtwDistance(userSemitones, ref);
    final maxLen = math.max(userSemitones.length, ref.length);
    final avgDist = dist / maxLen;
    // Map average semitone distance (0..4) to 100%..0%
    final sim = ((1.0 - (avgDist / 4.0)) * 100.0).round().clamp(15, 99);

    return MaqamAnalysisResult(
      maqam: maqam,
      similarityPct: sim,
      userCurve: userSemitones,
      referenceCurve: ref,
      avgHz: avgHz,
    );
  }

  static double _dtwDistance(List<double> a, List<double> b) {
    final n = a.length;
    final m = b.length;
    if (n == 0 || m == 0) return 0.0;
    const double inf = 1e9;
    var prev = List<double>.filled(m + 1, inf);
    var curr = List<double>.filled(m + 1, inf);
    prev[0] = 0.0;

    for (int i = 1; i <= n; i++) {
      curr[0] = inf;
      for (int j = 1; j <= m; j++) {
        final cost = (a[i - 1] - b[j - 1]).abs();
        final minPrev = math.min(prev[j], math.min(curr[j - 1], prev[j - 1]));
        curr[j] = cost + minPrev;
      }
      final tmp = prev;
      prev = curr;
      curr = tmp;
    }
    return prev[m];
  }
}
