import 'package:flutter_test/flutter_test.dart';
import 'package:aurora_downloader/premium/build_channel.dart';
import 'package:aurora_downloader/premium/ffmpeg/ffmpeg_module_loader.dart';
import 'package:aurora_downloader/downloader/models.dart';
import 'package:aurora_downloader/downloader/torrent_downloader.dart';
import 'package:aurora_downloader/sniffer/player/engines/media_kit_engine.dart';
import 'package:aurora_downloader/sniffer/player/playback_source.dart';
import 'package:aurora_downloader/sniffer/player/playback_state.dart';
import 'package:aurora_downloader/premium/ffmpeg/ffmpeg_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BuildChannel & GitHubModuleLoader Tests', () {
    test('GitHub build channel defaults and behavior', () {
      expect(BuildChannel.raw, equals('github'));
      expect(BuildChannel.isGithub, isTrue);
      expect(BuildChannel.isPlay, isFalse);
      expect(BuildChannel.label, equals('github'));
    });

    test('GitHubModuleLoader returns ready and true synchronously', () async {
      final loader = GitHubModuleLoader();

      expect(loader.statusFor('torrent'), equals(FeatureModuleStatus.ready));
      expect(loader.statusFor('mediakit'), equals(FeatureModuleStatus.ready));
      expect(loader.statusFor('ffmpeg'), equals(FeatureModuleStatus.ready));

      final installedTorrent = await loader.ensureInstalled('torrent');
      final installedMediaKit = await loader.ensureInstalled('mediakit');
      final installedFfmpeg = await loader.ensureInstalled('ffmpeg');

      expect(installedTorrent, isTrue);
      expect(installedMediaKit, isTrue);
      expect(installedFfmpeg, isTrue);

      expect(loader.estimatedSizeBytes('torrent'), isNull);
      expect(loader.estimatedSizeBytes('mediakit'), isNull);
      expect(loader.estimatedSizeBytes('ffmpeg'), isNull);

      expect(loader.displayName('torrent'), equals('BitTorrent engine'));
      expect(loader.displayName('mediakit'), equals('Media player engine'));
      expect(loader.displayName('ffmpeg'), equals('FFmpeg media tools'));
      expect(loader.displayName('unknown'), equals('unknown'));
    });

    test('GitHubModuleLoader watch stream emits ready', () async {
      final loader = GitHubModuleLoader();
      final status = await loader.watch('torrent').first;
      expect(status, equals(FeatureModuleStatus.ready));
    });

    test('FeatureModuleLoader.instance returns GitHubModuleLoader on default channel', () {
      final loader = FeatureModuleLoader.instance;
      expect(loader, isA<GitHubModuleLoader>());
      expect(loader.statusFor('torrent'), equals(FeatureModuleStatus.ready));
    });

    test('GitHubModuleLoader never needs a mid-process restart', () async {
      final loader = GitHubModuleLoader();
      expect(loader.installedInCurrentProcess('torrent'), isFalse);
      expect(loader.installedInCurrentProcess('ffmpeg'), isFalse);
      expect(await loader.requestRestart(), isFalse);
    });
  });

  group('PlayModuleLoader Specification Tests', () {
    test('PlayModuleLoader display names and size estimates', () {
      final playLoader = PlayModuleLoader();

      expect(playLoader.displayName('torrent'), equals('BitTorrent engine'));
      expect(playLoader.displayName('mediakit'), equals('Media player engine'));
      expect(playLoader.displayName('ffmpeg'), equals('FFmpeg media tools'));

      expect(playLoader.estimatedSizeBytes('torrent'), equals(6 * 1024 * 1024));
      expect(playLoader.estimatedSizeBytes('mediakit'), equals(15 * 1024 * 1024));
      expect(playLoader.estimatedSizeBytes('ffmpeg'), equals(18 * 1024 * 1024));
      expect(playLoader.estimatedSizeBytes('unknown'), isNull);
    });

    test('PlayModuleLoader initial status is missing', () {
      final playLoader = PlayModuleLoader();
      expect(playLoader.statusFor('torrent'), equals(FeatureModuleStatus.missing));
      expect(playLoader.statusFor('mediakit'), equals(FeatureModuleStatus.missing));
      expect(playLoader.statusFor('ffmpeg'), equals(FeatureModuleStatus.missing));
    });

    test('PlayModuleLoader starts with nothing installed in this process', () {
      final playLoader = PlayModuleLoader();
      expect(playLoader.installedInCurrentProcess('torrent'), isFalse);
      expect(playLoader.installedInCurrentProcess('ffmpeg'), isFalse);
      expect(playLoader.installedInCurrentProcess('mediakit'), isFalse);
    });
  });

  group('Graceful Degradation Tests', () {
    test('TorrentDownloader handles missing/unloaded engine without crashing', () async {
      final task = DownloadTask(
        id: 'test_magnet_1',
        url: 'magnet:?xt=urn:btih:1234567890abcdef1234567890abcdef12345678',
        savePath: '/tmp/test',
        tempDir: '/tmp/test_temp',
      );

      final downloader = TorrentDownloader(
        task: task,
        useNativeEngine: true,
      );

      // Starting magnet download in desktop test environment where libtorrent .so is not present
      // should catch error and transition to failed state gracefully
      await downloader.start();

      expect(task.state, equals(DownloadState.failed));
      expect(task.failureReason, equals(DownloadFailure.nativeEngineUnavailable));
      expect(task.errorMessage, isNotNull);
    });

    test('MediaKitEngine handles missing native mpv library without crashing', () async {
      final engine = MediaKitEngine();
      final source = PlaybackSource(
        url: 'https://example.com/video.mp4',
        title: 'Test Video',
      );

      // In test env without native libmpv .so, open fails gracefully with PlaybackStatus.failed
      await engine.open(source);

      expect(engine.value.status, equals(PlaybackStatus.failed));
      expect(engine.value.errorMessage, isNotNull);
      expect(engine.value.errorMessage, contains('unavailable'));
    });

    test('MediaKitEngine scrub preview handles missing native mpv library without crashing', () async {
      final engine = MediaKitEngine();
      await engine.prepareScrubPreview();
      expect(engine.scrubPreviewReady, isFalse);
    });

    test('FfmpegService handles probeVersion when ffmpeg native lib is missing', () async {
      final service = FfmpegService();
      final version = await service.probeVersion();

      // probeVersion catches exceptions and returns FfmpegVersion or null without throwing
      if (version != null) {
        expect(version.available, isFalse);
      }
    });
  });
}
