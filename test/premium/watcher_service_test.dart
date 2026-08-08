import 'dart:io';

import 'package:aurora_downloader/premium/watcher/watcher_models.dart';
import 'package:aurora_downloader/premium/watcher/watcher_service.dart';
import 'package:flutter_test/flutter_test.dart';

const _rssBody = '''
<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0">
<channel>
  <title>Test Feed</title>
  <item>
    <guid>ep-1</guid>
    <title>Episode One</title>
    <link>http://example.com/ep1.mp4</link>
  </item>
  <item>
    <guid>mv-2</guid>
    <title>Movie Two</title>
    <link>http://example.com/movie2.mp4</link>
  </item>
  <item>
    <guid>ep-3</guid>
    <title>Episode Three</title>
    <link>http://example.com/ep3.mp4</link>
  </item>
</channel>
</rss>
''';

void main() {
  // NOTE: no TestWidgetsFlutterBinding here — its fake HttpClient returns
  // 400 for every request, which would break these real-socket tests.

  late HttpServer server;
  late String feedUrl;

  setUp(() async {
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) {
      request.response.statusCode = 200;
      request.response.headers.contentType = ContentType('application', 'xml');
      request.response.write(_rssBody);
      request.response.close();
    });
    feedUrl = 'http://127.0.0.1:${server.port}/feed.xml';
  });

  tearDown(() async {
    await server.close(force: true);
  });

  WatchRule rule(String id, {String? matchRegex}) => WatchRule(
        id: id,
        kind: WatchKind.rss,
        url: feedUrl,
        minInterval: Duration.zero,
        matchRegex: matchRegex,
      );

  test('discovers and enqueues new items, then dedupes on recheck', () async {
    final enqueued = <String>[];
    final notices = <String>[];
    final service = WatcherService(
      onEnqueue: (url, {label}) async => enqueued.add(url),
      onNewItems: notices.add,
    );

    await service.addRule(rule('r1'));
    await service.checkNow('r1');

    expect(enqueued, hasLength(3));
    expect(
      enqueued,
      containsAll(['http://example.com/ep1.mp4', 'http://example.com/movie2.mp4']),
    );
    expect(notices, ['3 new items · $feedUrl']);
    final r1 = service.rules.first;
    expect(r1.seenIds, containsAll(['ep-1', 'mv-2', 'ep-3']));
    expect(r1.lastCheckedAt, isNotNull);

    // Second check: nothing new → no enqueue, no notification.
    enqueued.clear();
    notices.clear();
    await service.checkNow('r1');
    expect(enqueued, isEmpty);
    expect(notices, isEmpty);
  });

  test('matchRegex filters items before enqueue', () async {
    final enqueued = <String>[];
    final service = WatcherService(onEnqueue: (url, {label}) async {
      enqueued.add(url);
    });

    await service.addRule(rule('r2', matchRegex: r'Episode'));
    await service.checkNow('r2');

    expect(enqueued, ['http://example.com/ep1.mp4', 'http://example.com/ep3.mp4']);
  });

  test('invalid regex does not break the check', () async {
    final enqueued = <String>[];
    final service = WatcherService(onEnqueue: (url, {label}) async {
      enqueued.add(url);
    });

    await service.addRule(rule('r3', matchRegex: r'([unclosed'));
    await service.checkNow('r3');

    // Invalid regex → filter skipped, all items enqueued.
    expect(enqueued, hasLength(3));
  });
}
