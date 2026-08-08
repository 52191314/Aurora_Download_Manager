import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:aurora_downloader/premium/build_channel.dart';
import 'package:aurora_downloader/premium/ffmpeg/ffmpeg_module_loader.dart';
import 'package:aurora_downloader/downloader/models.dart';
import 'package:aurora_downloader/downloader/torrent_downloader.dart';
import 'package:aurora_downloader/sniffer/player/engines/media_kit_engine.dart';
import 'package:aurora_downloader/sniffer/player/playback_source.dart';
import 'package:aurora_downloader/sniffer/player/playback_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('M1 Cold Launch & FFI Stress Verification', () {
    test('BuildChannel correctly resolves when AURORA_BUILD_CHANNEL=play is defined', () {
      // In this test run, if passed with --dart-define=AURORA_BUILD_CHANNEL=play
      // BuildChannel.isPlay should be true, and FeatureModuleLoader.instance should be PlayModuleLoader.
      if (BuildChannel.raw == 'play') {
        expect(BuildChannel.isPlay, isTrue);
        expect(BuildChannel.isGithub, isFalse);
        expect(FeatureModuleLoader.instance, isA<PlayModuleLoader>());
      } else {
        expect(BuildChannel.isGithub, isTrue);
        expect(FeatureModuleLoader.instance, isA<GitHubModuleLoader>());
      }
    });

    test('Cold launch instantiation of TorrentDownloader does not load FFI or crash', () {
      final task = DownloadTask(
        id: 'cold_test_torrent',
        url: 'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567',
        savePath: '/tmp/test_cold_save',
        tempDir: '/tmp/test_cold_temp',
      );

      // Instantiating object at cold launch must not load FFI library or crash
      final downloader = TorrentDownloader(task: task);
      expect(downloader, isNotNull);
      expect(downloader.useNativeEngine, isTrue);
    });

    test('Cold launch instantiation of MediaKitEngine does not load FFI or crash', () {
      // Instantiating MediaKitEngine at cold launch must not load FFI library or crash
      final engine = MediaKitEngine();
      expect(engine, isNotNull);
      expect(engine.value.status, equals(PlaybackStatus.idle));
      expect(engine.scrubPreviewReady, isFalse);
    });

    test('PlayModuleLoader correctly configures display names and estimated sizes', () {
      final loader = PlayModuleLoader();
      expect(loader.displayName('ffmpeg'), equals('FFmpeg media tools'));
      expect(loader.displayName('torrent'), equals('BitTorrent engine'));
      expect(loader.displayName('mediakit'), equals('Media player engine'));

      expect(loader.estimatedSizeBytes('ffmpeg'), equals(18 * 1024 * 1024));
      expect(loader.estimatedSizeBytes('torrent'), equals(6 * 1024 * 1024));
      expect(loader.estimatedSizeBytes('mediakit'), equals(15 * 1024 * 1024));
      expect(loader.estimatedSizeBytes('unknown'), isNull);
    });

    test('Graceful degradation when Play Store dynamic feature module is missing', () async {
      // Test TorrentDownloader hard-fail when useNativeEngine is false or module uninstalled
      final task = DownloadTask(
        id: 'cold_test_torrent_2',
        url: 'magnet:?xt=urn:btih:0123456789abcdef0123456789abcdef01234567',
        savePath: '/tmp/test_cold_save',
        tempDir: '/tmp/test_cold_temp',
      );

      final downloader = TorrentDownloader(task: task, useNativeEngine: false);
      await downloader.start();

      expect(task.state, equals(DownloadState.failed));
      expect(task.failureReason, equals(DownloadFailure.nativeEngineUnavailable));
      expect(task.errorMessage, contains('Magnet downloads require the native torrent engine'));
    });

    test('MediaKitEngine open fails gracefully when native lib is missing', () async {
      final engine = MediaKitEngine();
      final source = PlaybackSource(
        url: 'https://example.com/stream.m3u8',
        title: 'Test Stream',
      );

      await engine.open(source);
      // In environment without libmpv.so, open must return failed state gracefully without crash
      expect(engine.value.status, equals(PlaybackStatus.failed));
      expect(engine.value.errorMessage, isNotNull);
    });
  });
}
