import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:aurora_downloader/settings/download_settings.dart';
import 'package:aurora_downloader/sniffer/ad_block_engine_native.dart';

void main() {
  group('procedural cosmetic translation', () {
    test(':-abp-has(X) is translated to plain CSS :has(X)', () {
      final parsed = AdBlockEngine.parseFilterText('##div:-abp-has(> .ad)\n');
      expect(parsed.cosmeticRules, hasLength(1));
      expect(parsed.cosmeticRules.single.selector, 'div:has(> .ad)');
    });

    test('translation leaves the rest of the selector intact', () {
      final parsed = AdBlockEngine.parseFilterText(
        '##a:-abp-has(img):hover::after\n',
      );
      expect(parsed.cosmeticRules.single.selector, 'a:has(img):hover::after');
    });

    test('nested :-abp-has tokens are all translated', () {
      final parsed = AdBlockEngine.parseFilterText(
        '##div:-abp-has(span:-abp-has(.bad))\n',
      );
      expect(parsed.cosmeticRules.single.selector, 'div:has(span:has(.bad))');
    });

    test('rules still carrying a procedural token are dropped', () {
      final parsed = AdBlockEngine.parseFilterText(
        '##.a:has-text(Ads)\n'
        '##.b:-abp-contains(ad)\n'
        '##.c:upward(2)\n'
        '##.d:matches-css-before(content: "x")\n'
        '##.e:style(display: none !important)\n'
        '##.f:xpath(//div)\n'
        '##.g:remove()\n'
        '##.h:others()\n'
        '##.i:if(script)\n'
        '##.j:if-not(script)\n'
        '##.k:min-text-length(10)\n'
        '##.l:watch-attr(class)\n'
        '##.m:matches-attr(^data-)\n'
        '##.n:matches-path(^/ad)\n'
        '##.o:-abp-has(.x):has-text(Sponsored)\n',
      );
      expect(parsed.cosmeticRules, isEmpty);
    });

    test('valid selectors survive next to dropped procedural ones', () {
      final parsed = AdBlockEngine.parseFilterText(
        '##.good-ad\n##.bad:has-text(Ads)\n',
      );
      expect(parsed.cosmeticRules, hasLength(1));
      expect(parsed.cosmeticRules.single.selector, '.good-ad');
    });
  });

  group('removeparam', () {
    AdBlockEngine engineFor(String text) {
      final parsed = AdBlockEngine.parseFilterText(text);
      return AdBlockEngine(
        enabled: true,
        rules: parsed.networkRules,
        removeParamRules: parsed.removeParamRules,
      );
    }

    test('plain param is stripped', () {
      final engine = engineFor(r'$removeparam=utm_source');
      expect(
        engine.stripTrackingParams('https://a.example/x?utm_source=1&id=2'),
        'https://a.example/x?id=2',
      );
    });

    test('regex param strips every name matching the regex', () {
      final engine = engineFor(r'$removeparam=/^utm_/');
      expect(
        engine.stripTrackingParams(
          'https://a.example/x?utm_source=1&utm_campaign=2&id=3',
        ),
        'https://a.example/x?id=3',
      );
    });

    test('~exception alone never strips', () {
      final engine = engineFor(r'$removeparam=~utm_source');
      expect(
        engine.stripTrackingParams('https://a.example/x?utm_source=1'),
        isNull,
      );
    });

    test('exception beats a strip rule on the same param', () {
      final engine = engineFor(
        r'$removeparam=utm_source' '\n' r'$removeparam=~utm_source',
      );
      expect(
        engine.stripTrackingParams('https://a.example/x?utm_source=1'),
        isNull,
      );
    });

    test('regex exception form (~/regex/) is parsed as an exception', () {
      final parsed = AdBlockEngine.parseFilterText(
        r'||use.typekit.net^$font,removeparam=~/^(primer|subset_id)=/,domain=~fonts.adobe.com',
      );
      expect(parsed.removeParamRules, hasLength(1));
      final rule = parsed.removeParamRules.single;
      expect(rule.isException, isTrue);
      expect(rule.paramRegex, isNotNull);
    });

    test('mixed strip + exception rules: exceptions win', () {
      final engine = engineFor(
        r'$removeparam=/^utm_/' '\n' r'$removeparam=~utm_campaign',
      );
      expect(
        engine.stripTrackingParams(
          'https://a.example/x?utm_source=1&utm_campaign=2&id=3',
        ),
        'https://a.example/x?utm_campaign=2&id=3',
      );
    });

    test('strip-all rule keeps ~exempted params', () {
      final engine = engineFor(r'$removeparam' '\n' r'$removeparam=~keep');
      expect(
        engine.stripTrackingParams('https://a.example/x?a=1&keep=2'),
        'https://a.example/x?keep=2',
      );
    });

    test('param names match case-insensitively', () {
      final engine = engineFor(r'$removeparam=UTM_SOURCE');
      expect(
        engine.stripTrackingParams('https://a.example/x?utm_source=1'),
        'https://a.example/x',
      );
    });

    test('regex removeparam matches case-insensitively', () {
      final engine = engineFor(r'$removeparam=/^utm_/');
      expect(
        engine.stripTrackingParams('https://a.example/x?UTM_SOURCE=1&id=2'),
        'https://a.example/x?id=2',
      );
    });

    test('regex rule respects its host pattern', () {
      final engine = engineFor(r'||shop.example^$removeparam=/^ref_/');
      expect(
        engine.stripTrackingParams('https://shop.example/p?ref_x=1&id=2'),
        'https://shop.example/p?id=2',
      );
      expect(
        engine.stripTrackingParams('https://other.example/p?ref_x=1'),
        isNull,
      );
    });

    test('invalid regex is dropped, not applied broadly', () {
      final engine = engineFor(r'$removeparam=/(unclosed/');
      expect(engine.removeParamRules, isEmpty);
    });

    test('regex removeparam lines never reach the native engine text',
        () async {
      final engine = await AdBlockEngine.fromFilterSources(
        enabled: true,
        sources: const [
          AdblockFilterSource(
            name: 'Mock TrackParam',
            url: 'https://example.com/trackparam.txt',
          ),
        ],
        client: MockClient((request) async {
          return http.Response(
            r'$removeparam=/^utm_/' '\n' r'||ads.example.com^' '\n',
            200,
          );
        }),
      );
      expect(engine.rawRulesText, isNot(contains('removeparam')));
      expect(engine.rawRulesText, contains('ads.example.com'));
      expect(engine.removeParamRules.single.paramRegex, isNotNull);
    });
  });

  group('generichide / elemhide', () {
    test('\$generichide and \$elemhide hosts are tracked from network rules',
        () {
      final parsed = AdBlockEngine.parseFilterText(
        '||example.com^\$generichide\n'
        '@@||shop.example^\$elemhide\n',
      );
      expect(parsed.genericHideHosts, contains('example.com'));
      expect(parsed.elemHideHosts, contains('shop.example'));
    });

    test('generichide/elemhide rules still become network rules', () {
      final parsed = AdBlockEngine.parseFilterText(
        '||example.com^\$generichide\n',
      );
      expect(parsed.networkRules, hasLength(1));
      expect(parsed.networkRules.single.pattern, 'example.com');
      expect(parsed.networkRules.single.isException, isFalse);
    });

    test('generichide host suppresses generic CSS only', () {
      final parsed = AdBlockEngine.parseFilterText(
        '||example.com^\$generichide\n'
        '##.generic-ad\n'
        'example.com##.specific-ad\n',
      );
      final engine = AdBlockEngine(
        enabled: true,
        rules: parsed.networkRules,
        cosmeticRules: parsed.cosmeticRules,
        genericHideHosts: parsed.genericHideHosts,
        elemHideHosts: parsed.elemHideHosts,
      );
      // No-host call (user script install) is unaffected.
      expect(engine.getGenericCosmeticCss(), contains('.generic-ad'));
      // The generichide host (and its subdomains) get no generic CSS...
      expect(engine.getGenericCosmeticCss('example.com'), isEmpty);
      expect(engine.getGenericCosmeticCss('sub.example.com'), isEmpty);
      // ...but other hosts still do, and host-specific rules still apply.
      expect(
        engine.getGenericCosmeticCss('other.com'),
        contains('.generic-ad'),
      );
      expect(
        engine.getCosmeticCssForHost('example.com'),
        contains('.specific-ad'),
      );
    });

    test('elemhide host suppresses all cosmetics', () {
      final parsed = AdBlockEngine.parseFilterText(
        '||shop.example^\$elemhide\n'
        '##.generic-ad\n'
        'shop.example##.specific-ad\n'
        'other.com##.other-ad\n',
      );
      final engine = AdBlockEngine(
        enabled: true,
        rules: parsed.networkRules,
        cosmeticRules: parsed.cosmeticRules,
        genericHideHosts: parsed.genericHideHosts,
        elemHideHosts: parsed.elemHideHosts,
      );
      expect(engine.getGenericCosmeticCss('shop.example'), isEmpty);
      expect(engine.getCosmeticCssForHost('shop.example'), isEmpty);
      // Other hosts are unaffected.
      expect(
        engine.getCosmeticCssForHost('other.com'),
        contains('.other-ad'),
      );
    });

    test('generic hide/elemhide sets survive the source pipeline', () async {
      final engine = await AdBlockEngine.fromFilterSources(
        enabled: true,
        sources: const [
          AdblockFilterSource(
            name: 'Mock List',
            url: 'https://example.com/list.txt',
          ),
        ],
        client: MockClient((request) async {
          return http.Response(
            '||example.com^\$generichide\n'
            '||shop.example^\$elemhide\n',
            200,
          );
        }),
      );
      expect(engine.genericHideHosts, contains('example.com'));
      expect(engine.elemHideHosts, contains('shop.example'));
      expect(engine.getGenericCosmeticCss('example.com'), isEmpty);
      expect(engine.getCosmeticCssForHost('shop.example'), isEmpty);
    });
  });
}
