# Aurora Download Manager OSS v1.3.1 (Build 80)

## Improvements & Bug Fixes

* **Tab Import Reliability Fix**:
  * Resolved blank web page loading by generating collision-free atomic tab IDs.
  * Added auto-navigation of empty initial tabs (`about:blank`) to the first imported URL.
  * Added deferred initialization (`deferStartupWork: true`) for imported background tabs to prevent unmounted WebView hangs.
  * Added full Open Tabs support across Library Transfer backup and restore sheets.
* **Crash & Stability Fixes**:
  * **Android 14/15 Foreground Service Timeout**: Implemented `onTimeout` lifecycle callbacks and switched `DownloadForegroundService` to `START_NOT_STICKY` to eliminate `ForegroundServiceDidNotStopInTimeException`.
  * **Flutter Material Hierarchy**: Replaced `Container + ListTile` with `Material + InkWell` in language selection dialog to prevent Flutter framework assertions.
