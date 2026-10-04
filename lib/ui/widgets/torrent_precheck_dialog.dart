import 'package:flutter/material.dart';

import '../../downloader/torrent_downloader.dart';

/// Whether the torrent engine can start a download in this process.
enum TorrentPrepareOutcome {
  /// FFI loaded; enqueue and start.
  ready,

  /// User cancelled install or restart. Do not enqueue.
  cancelled,

  /// Device cannot load the engine. Show [showTorrentEngineUnavailableDialog].
  unavailable,

  /// Module is on disk but this process cannot dlopen it.
  needsRestart,
}

/// Checks if the native torrent engine (libtorrent) is ready on this device.
Future<TorrentPrepareOutcome> prepareTorrentEngineForUser(
  BuildContext context,
) async {
  final isAvailable = await TorrentDownloader.isNativeEngineAvailable();
  if (isAvailable) {
    return TorrentPrepareOutcome.ready;
  }
  final err = await TorrentDownloader.checkNativeEngineAvailability();
  if (err == null) {
    return TorrentPrepareOutcome.ready;
  }
  return TorrentPrepareOutcome.unavailable;
}

/// Shows an alert dialog warning the user that the native torrent engine
/// could not be loaded on this device before they attempt a magnet download.
Future<void> showTorrentEngineUnavailableDialog(
  BuildContext context, {
  String? reason,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.orangeAccent, size: 24),
          SizedBox(width: 8),
          Flexible(child: Text('Torrent Engine Unavailable')),
        ],
      ),
      content: Text(
        reason ??
            'Magnet and torrent downloads cannot be started because the native '
            'torrent engine (libtorrent) failed to load on this device. '
            'Your device architecture may not be supported.',
        style: const TextStyle(fontSize: 13, height: 1.4),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('OK'),
        ),
      ],
    ),
  );
}
