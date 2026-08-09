import 'package:flutter_test/flutter_test.dart';

import 'package:aurora_downloader/sniffer/listing_page_crawler.dart';

String listingPage(List<String> detailIds, {int page = 1}) {
  final links = detailIds
      .map((id) => '<a href="https://example.com/user/short/$id">'
          '<img src="https://image-cdn.example.com/$id/thumb.webp"></a>')
      .join('\n');
  final next = page == 1
      ? '<a href="https://example.com/user/short?page=2">Next page</a>'
      : '';
  return '''
<html><head><title>Creator — 56 Shorts | Site</title></head>
<body>
<a href="https://example.com/">Home</a>
<a href="https://example.com/login">Log In</a>
<a href="https://example.com/register">Sign Up</a>
<a href="https://example.com/premium">Premium</a>
<a href="/creators?Networks=OnlyFans">Creators</a>
<a href="/user/video">Videos (1)</a>
<a href="/user/photo">Photos (7)</a>
$links
$next
</body></html>''';
}

String detailPage(String id) => '''
<html><head><title>Creator short #$id — Site</title></head>
<body>
<video controls poster="https://image-cdn.example.com/$id/thumb.webp">
<source src="https://cdn.example.com/storage/videos/$id/master.m3u8" type="application/x-mpegURL">
</video>
</body></html>''';

void main() {
  group('ListingPageCrawler', () {
    test('crawls listing + pagination + detail pages, dedupes, extracts media',
        () async {
      final htmlByUrl = <String, String>{
        'https://example.com/user/short?page=1':
            listingPage(['1001', '1002', '1003']),
        'https://example.com/user/short?page=2':
            listingPage(['2001', '2002', '1001'], page: 2),
        'https://example.com/user/short/1001': detailPage('1001'),
        'https://example.com/user/short/1002': detailPage('1002'),
        'https://example.com/user/short/1003': detailPage('1003'),
        'https://example.com/user/short/2001': detailPage('2001'),
        'https://example.com/user/short/2002': detailPage('2002'),
      };
      final fetches = <String>[];

      final crawler = ListingPageCrawler(
        fetchHtml: (url) async {
          fetches.add(url);
          return htmlByUrl[url];
        },
      );

      final result = await crawler.crawlListing(
        'https://example.com/user/short?page=1',
      );

      // 5 unique detail pages (1001 appears on both listing pages).
      final urls = result.media.map((m) => m.url).toSet();
      expect(urls.length, 5, reason: 'media urls: ${result.media}');
      for (final m in result.media) {
        expect(
          m.sourcePageUrl,
          startsWith('https://example.com/user/short/'),
        );
        expect(m.pageTitle, contains('Creator short'));
      }
      // Pagination was followed.
      expect(fetches, contains('https://example.com/user/short?page=2'));
      // Nav + sibling listings were NOT fetched as detail pages.
      final detailFetches = fetches
          .where((u) => u.contains('/short/') && !u.contains('?'))
          .toList();
      expect(detailFetches.length, 5, reason: 'detail fetches: $detailFetches');
      expect(fetches.where((u) => u.contains('/login')), isEmpty);
      expect(fetches.where((u) => u.contains('/premium')), isEmpty);
      expect(fetches.where((u) => u.contains('/creators')), isEmpty,
          reason: 'fetches: $fetches');
      expect(
        fetches.where((u) => u.contains('/video') || u.contains('/photo')),
        isEmpty,
        reason: 'fetches: $fetches',
      );
    });

    test('/watch/123 shape (detail outside listing path) is followed',
        () async {
      final crawler = ListingPageCrawler(
        fetchHtml: (url) async {
          if (url.contains('/watch/')) {
            final id = Uri.parse(url).pathSegments.last;
            return '<html><title>Watch $id</title>'
                '<video src="https://cdn.x/$id.m3u8"></video></html>';
          }
          return '<html>'
              '<a href="/watch/123">v123</a>'
              '<a href="/watch/456">v456</a>'
              '<a href="/tags">Tags</a>'
              '<a href="/videos?page=2">Next</a>'
              '</html>';
        },
      );
      final result = await crawler.crawlListing('https://x.com/videos?page=1');
      expect(
        result.media.map((m) => m.url),
        containsAll(['https://cdn.x/123.m3u8', 'https://cdn.x/456.m3u8']),
      );
      expect(result.media.length, 2,
          reason: 'two watch pages -> two media');
      expect(
        result.media.every((m) => m.sourcePageUrl.contains('/watch/')),
        isTrue,
      );
    });

    test('sort/query-only links on the same path are not detail pages',
        () async {
      final crawler = ListingPageCrawler(
        fetchHtml: (url) async {
          if (url.contains('/shorts/999')) {
            return '<html><title>v999</title>'
                '<video src="https://cdn.x/999.mp4"></video></html>';
          }
          return '<html>'
              '<a href="/shorts?sort=views">Most views</a>'
              '<a href="/shorts?sort=longest">Longest</a>'
              '<a href="/shorts/999">real video</a>'
              '</html>';
        },
      );
      final result = await crawler.crawlListing('https://x.com/shorts?page=1');
      expect(result.media.length, 1, reason: 'media: ${result.media}');
      expect(result.media.single.sourcePageUrl, 'https://x.com/shorts/999');
    });

    test('maxDetailPages caps the crawl', () async {
      final fetched = <String>[];
      final crawler = ListingPageCrawler(
        maxDetailPages: 2,
        fetchHtml: (url) async {
          fetched.add(url);
          if (url.contains('/short/')) {
            final id = Uri.parse(url).pathSegments.last;
            return '<html><title>v$id</title>'
                '<video src="https://cdn.x/v$id.mp4"></video></html>';
          }
          return '<html>' +
              [
                for (var i = 1; i <= 10; i++) '<a href="/short/$i">v$i</a>',
              ].join() +
              '</html>';
        },
      );
      final result = await crawler.crawlListing('https://x.com/short?page=1');
      final detailFetches = fetched
          .where((u) => u.contains('/short/') && !u.contains('?'))
          .toList();
      expect(detailFetches.length, 2, reason: 'fetched: $fetched');
      expect(result.media.length, 2);
    });

    test('cancellation stops the crawl', () async {
      var cancelled = false;
      final crawler = ListingPageCrawler(
        fetchHtml: (url) async {
          if (cancelled) return null;
          return listingPage(['1001']);
        },
        isCancelled: () => cancelled,
      );
      cancelled = true;
      final result = await crawler.crawlListing(
        'https://example.com/user/short?page=1',
      );
      expect(result.cancelled, isTrue);
    });

    test('media URL on the listing page itself is captured', () async {
      final crawler = ListingPageCrawler(
        fetchHtml: (url) async => '''
<html><body>
<video src="https://cdn.example.com/direct.mp4"></video>
<a href="/v/123">video 123</a>
</body></html>''',
      );
      final result = await crawler.crawlListing('https://example.com/videos?page=1');
      expect(
        result.media.map((m) => m.url),
        contains('https://cdn.example.com/direct.mp4'),
      );
    });

    test('empty / non-http input yields no media', () async {
      final crawler = ListingPageCrawler(fetchHtml: (url) async => null);
      final result = await crawler.crawlListing('not-a-url');
      expect(result.media, isEmpty);
      expect(result.cancelled, isFalse);
    });
  });
}
