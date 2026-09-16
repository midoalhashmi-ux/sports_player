import 'package:flutter_test/flutter_test.dart';
import 'package:sports_player/services/hls_variant_selector.dart';

/// الروابط هنا مأخوذة حرفياً من سجلات تشخيص حقيقية (topcinema/vidtube،
/// ristoanime/vidmoly) — راجع TECHNICAL.md #50.
const _base = 'https://serv-stream-cdn28.cdn-video.xyz/hls2/01/00061';

HlsVariant _variant(String tier, int bandwidth) => HlsVariant(
      bandwidth: bandwidth,
      label: '${bandwidth ~/ 1000} kbps',
      url: '$_base/uyjeu9vq4p2b_$tier/index-v1-a1.m3u8',
    );

/// أربع جودات بنفس ترتيب المصادر التي فشلت فعلياً (`,l,n,h,x,`).
List<HlsVariant> _fourTiers() => [
      _variant('l', 249003),
      _variant('n', 660000),
      _variant('h', 1319341),
      _variant('x', 2400000),
    ];

/// جودتان فقط — نفس شكل المصدرين اللذين نجحا نظيفَين (`,n,l,`).
List<HlsVariant> _twoTiers() => [
      _variant('l', 249003),
      _variant('n', 660000),
    ];

void main() {
  group('variantKey', () {
    test('تجمع الشريحة وقائمتها تحت نفس المفتاح', () {
      final playlist =
          HlsVariantSelector.variantKey('$_base/uyjeu9vq4p2b_n/index-v1-a1.m3u8');
      final segment = HlsVariantSelector.variantKey(
          '$_base/uyjeu9vq4p2b_n/seg-1-v1-a1.ts?t=abc&s=123&e=86400');
      expect(playlist, isNotNull);
      expect(segment, playlist);
    });

    test('تفرّق بين جودتين مختلفتين', () {
      expect(
        HlsVariantSelector.variantKey('$_base/uyjeu9vq4p2b_n/seg-1.ts'),
        isNot(HlsVariantSelector.variantKey('$_base/uyjeu9vq4p2b_x/seg-1.ts')),
      );
    });

    test('ترجع null لرابط بلا مسار حقيقي', () {
      expect(HlsVariantSelector.variantKey('https://example.com'), isNull);
      expect(HlsVariantSelector.variantKey('not a url at all'), isNull);
    });
  });

  group('prioritize — الجودة المُثبَتة من WebView', () {
    test('تتقدّم المُثبَتة على الأعلى نطاقاً', () {
      final proven = {
        HlsVariantSelector.variantKey('$_base/uyjeu9vq4p2b_n/seg-1-v1-a1.ts')!
      };
      final ordered =
          HlsVariantSelector.prioritize(_fourTiers(), provenKeys: proven);
      expect(ordered.first.url, contains('_n/'));
    });

    test('الأعلى بين المُثبَتات أولاً', () {
      final proven = {
        HlsVariantSelector.variantKey('$_base/uyjeu9vq4p2b_n/seg-1.ts')!,
        HlsVariantSelector.variantKey('$_base/uyjeu9vq4p2b_l/seg-1.ts')!,
      };
      final ordered =
          HlsVariantSelector.prioritize(_fourTiers(), provenKeys: proven);
      expect(ordered[0].url, contains('_n/'));
      expect(ordered[1].url, contains('_l/'));
    });

    test('لا تُحذف أي جودة — الترتيب فقط', () {
      final proven = {
        HlsVariantSelector.variantKey('$_base/uyjeu9vq4p2b_n/seg-1.ts')!
      };
      final ordered =
          HlsVariantSelector.prioritize(_fourTiers(), provenKeys: proven);
      expect(ordered.length, 4);
      expect(ordered.map((v) => v.url).toSet().length, 4);
    });

    test('إثبات لا يطابق أي جودة يرجع للسلوك الافتراضي', () {
      final ordered = HlsVariantSelector.prioritize(
        _fourTiers(),
        provenKeys: {'other-host.example/some/other/path'},
      );
      expect(ordered.first.url, contains('_h/'));
      expect(ordered.last.url, contains('_x/'));
    });
  });

  group('prioritize — بلا أي إثبات', () {
    test('تؤخّر الأعلى للآخر حين تكون الجودات 3 فأكثر', () {
      final ordered = HlsVariantSelector.prioritize(_fourTiers());
      expect(ordered.first.url, contains('_h/'),
          reason: 'تبدأ بما دون الأعلى مباشرة');
      expect(ordered.last.url, contains('_x/'),
          reason: 'الأعلى تبقى متاحة يدوياً لكن ليست البداية');
    });

    test('تُبقي الأعلى أولاً حين تكون جودتين فقط', () {
      final ordered = HlsVariantSelector.prioritize(_twoTiers());
      expect(ordered.first.url, contains('_n/'),
          reason: 'مصادر الجودتين نجحت فعلياً بالأعلى — لا تخفيض بلا سبب');
    });

    test('جودة واحدة تمرّ كما هي', () {
      final single = [_variant('n', 660000)];
      expect(HlsVariantSelector.prioritize(single).single.url, single.single.url);
    });
  });

  group('allowedUrls — سقف التكيّف داخل القائمة الرئيسية', () {
    test('سقف لا مطابقة: تسمح بكل ما هو ≤ أعلى جودة مُثبَتة', () {
      final proven = {
        HlsVariantSelector.variantKey('$_base/uyjeu9vq4p2b_n/seg-1.ts')!
      };
      final allowed =
          HlsVariantSelector.allowedUrls(_fourTiers(), provenKeys: proven);
      expect(allowed, isNotNull);
      // _n (المُثبَتة) و_l (أدنى منها) — بلا _h و_x
      expect(allowed!.length, 2);
      expect(allowed.any((u) => u.contains('_n/')), isTrue);
      expect(allowed.any((u) => u.contains('_l/')), isTrue);
      expect(allowed.any((u) => u.contains('_h/')), isFalse);
      expect(allowed.any((u) => u.contains('_x/')), isFalse);
    });

    test('إثبات الأدنى وحده لا يحبس المشاهدة عليه بلا داعٍ', () {
      // نفس حالة سجل الأنمي: أول إثبات كان _l، فكان السقف القديم يُبقي
      // جودة واحدة فقط (kept=1/2) ويحبس الحلقة على 480p.
      final proven = {
        HlsVariantSelector.variantKey('$_base/uyjeu9vq4p2b_l/seg-1.ts')!
      };
      final allowed =
          HlsVariantSelector.allowedUrls(_twoTiers(), provenKeys: proven);
      expect(allowed, isNotNull);
      expect(allowed!.length, 1, reason: 'بجودتين فقط، _l هي كل ما دون السقف');
    });

    test('تحذف الأعلى فقط حين لا يوجد إثبات', () {
      final allowed = HlsVariantSelector.allowedUrls(_fourTiers());
      expect(allowed, isNotNull);
      expect(allowed!.length, 3);
      expect(allowed.any((url) => url.contains('_x/')), isFalse);
    });

    test('ترجع null لجودتين بلا إثبات (لا تعديل على القائمة)', () {
      expect(HlsVariantSelector.allowedUrls(_twoTiers()), isNull);
    });

    test('ترجع null حين تكون كل الجودات مُثبَتة', () {
      final proven = {
        for (final variant in _twoTiers())
          HlsVariantSelector.variantKey(variant.url)!
      };
      expect(
        HlsVariantSelector.allowedUrls(_twoTiers(), provenKeys: proven),
        isNull,
      );
    });

    test('لا تُفرغ القائمة أبداً', () {
      for (final count in [1, 2, 3, 4]) {
        final variants = _fourTiers().take(count).toList();
        final allowed = HlsVariantSelector.allowedUrls(variants);
        expect(allowed == null || allowed.isNotEmpty, isTrue);
      }
    });
  });
}
