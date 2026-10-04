import 'package:flutter_test/flutter_test.dart';
import 'package:aurora_downloader/downloader/download_queue.dart';
import 'package:aurora_downloader/downloader/models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DownloadQueue backup import deduplication', () {
    late DownloadQueue queue;

    setUp(() {
      queue = DownloadQueue(maxConcurrentDownloads: 2);
    });

    tearDown(() {
      queue.dispose();
    });

    test('isBackupImport skips duplicates with same task ID', () {
      final task1 = DownloadTask(
        id: 'task-1',
        url: 'https://example.com/video.mp4',
        savePath: '/tmp/video.mp4',
        tempDir: '/tmp/temp_1',
        state: DownloadState.completed,
      );
      final task1Duplicate = DownloadTask(
        id: 'task-1',
        url: 'https://example.com/video.mp4',
        savePath: '/tmp/video.mp4',
        tempDir: '/tmp/temp_1_dup',
        state: DownloadState.completed,
        isBackupImport: true,
      );

      final added1 = queue.addTask(task1);
      expect(added1, isTrue);
      expect(queue.allTasks.length, equals(1));

      final added2 = queue.addTask(task1Duplicate);
      expect(added2, isFalse, reason: 'Duplicate task ID on import must be skipped');
      expect(queue.allTasks.length, equals(1));
    });

    test('isBackupImport skips duplicate URLs even if task ID differs', () {
      final task1 = DownloadTask(
        id: 'task-local',
        url: 'https://example.com/video.mp4?utm_source=test',
        savePath: '/tmp/video.mp4',
        tempDir: '/tmp/temp_1',
        state: DownloadState.completed,
      );
      final task2Import = DownloadTask(
        id: '1dm_9999',
        url: 'https://example.com/video.mp4',
        savePath: '/tmp/video.mp4',
        tempDir: '/tmp/temp_2',
        state: DownloadState.completed,
        isBackupImport: true,
      );

      final added1 = queue.addTask(task1);
      expect(added1, isTrue);
      expect(queue.allTasks.length, equals(1));

      final added2 = queue.addTask(task2Import);
      expect(added2, isFalse, reason: 'Duplicate URL on import must be skipped even with different task ID');
      expect(queue.allTasks.length, equals(1));
    });

    test('isBackupImport allows truly unique new tasks', () {
      final task1 = DownloadTask(
        id: 'task-1',
        url: 'https://example.com/video1.mp4',
        savePath: '/tmp/video1.mp4',
        tempDir: '/tmp/temp_1',
        state: DownloadState.completed,
      );
      final task2 = DownloadTask(
        id: 'task-2',
        url: 'https://example.com/video2.mp4',
        savePath: '/tmp/video2.mp4',
        tempDir: '/tmp/temp_2',
        state: DownloadState.completed,
        isBackupImport: true,
      );

      expect(queue.addTask(task1), isTrue);
      expect(queue.addTask(task2), isTrue);
      expect(queue.allTasks.length, equals(2));
    });

    test('normal non-import addTask still allows re-downloading completed URLs', () {
      final task1 = DownloadTask(
        id: 'task-1',
        url: 'https://example.com/video.mp4',
        savePath: '/tmp/video.mp4',
        tempDir: '/tmp/temp_1',
        state: DownloadState.completed,
      );
      final task2Redownload = DownloadTask(
        id: 'task-2',
        url: 'https://example.com/video.mp4',
        savePath: '/tmp/video_copy.mp4',
        tempDir: '/tmp/temp_2',
        state: DownloadState.idle,
        isBackupImport: false,
      );

      expect(queue.addTask(task1), isTrue);
      expect(queue.addTask(task2Redownload), isTrue);
      expect(queue.allTasks.length, equals(2));
    });
  });
}
