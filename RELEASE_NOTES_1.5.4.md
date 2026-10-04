# Aurora Download Manager OSS v1.5.4 (Build 108)

**Release Date:** October 4, 2026
**Build Number:** 108
**Version:** 1.5.4
**Tracking Issue:** Closes #3

---

### Highlights

Aurora Download Manager OSS v1.5.4 brings the open-source edition fully up to date with core stability, sniffer diagnostics, and download engine enhancements up to v1.5.4, while strictly maintaining pure open-source integrity, F-Droid compliance, and GPL-3.0 compatibility.

---

### Core Download Engine & Lifecycle Fixes

- **Adaptive Retry Chunk Backoff**:
  - Automatically steps down concurrent chunk count on network retry attempts (e.g. 8 -> 4 -> 2 -> 1 chunk fallback on third retry) to salvage downloads on unstable CDNs and rate-limited hosts.
  - Reconfigures active splitters dynamically on chunk count transitions.
- **Queue Lifecycle & History Eviction**:
  - Enforced terminal history eviction on startup and queue reload.
  - Automated disk cleanup of temporary chunk files and HLS segments upon queue row eviction.
  - Sanitization of query tracking parameters from saved URLs to preserve cache locality and privacy.
- **HTTP & Cookie Resolution**:
  - Implemented case-insensitive header matching in NativeDownloadClient (`headerValue`).
  - Forwarded dynamic cookies and Authorization headers directly to the native OkHttp engine.

### Error Classification & Diagnostics

- **Security & Protocol Failures**:
  - Added structured classification for `DownloadFailure.certificateInvalid` to accurately identify site-level TLS/SSL misconfigurations without triggering fruitless retry loops.
  - Added classification for `DownloadFailure.appLinkIntent` (`intent://`, `android-app://`) with browser handoff guidance.
  - Introduced terminal failure checks (`shouldSkipAutoRetry`) to avoid dead swarm loops and wasteful retries.

### Browser & Sniffer Hardening

- **RFC 3986 URI Resolution**:
  - Hardened address bar and search resolution via `BrowserSearch.safeResolve` and error-safe parsing.
  - Protected against `FormatException` crashes on malformed inputs with whitespace preceding colons, leading digits in schemes, or illegal port notations.
- **Android Task Affinity Alignment**:
  - Removed `android:taskAffinity=""` on MainActivity in `AndroidManifest.xml` to eliminate multi-window stack splits and black screen issues when launching from recent tasks or external intents.
- **Unified Overflow Menu**:
  - Replaced the segmented reorderable popup with a clean, high-performance unified menu featuring section headers, dividers, and direct tool actions.

### Media Player & UI Enhancements

- **Player Double-Tap Seek**:
  - Implemented `DoubleTapSeekCombo` enabling responsive seeking intervals (10s, 20s, 40s, 80s) on consecutive double taps.
  - Added transient gesture HUD indicating seek direction, interval, and aspect ratio changes.
- **Aspect Ratio Cycling**:
  - Added three-state viewport fitting (`Fit` -> `Crop` -> `Stretch`) with visual HUD cues.
- **Queue Quick Actions**:
  - Added quick action chips (`Paste link`, `Browse the web`, `Magnet / torrent`) to the empty queue state for direct intake.

### Pure Open-Source Integrity

- **Zero Proprietary SDKs**:
  - Removed all dependencies and references to Google Play Billing, Firebase Analytics, Crashlytics, Google Drive sync, and Play Feature Delivery.
  - Removed Google Play rating prompts and weekly download limits to ensure downloads remain completely unlimited for all open-source users.
- **F-Droid Build Reproducibility**:
  - Maintained `libtorrent_flutter` support across dual ABIs (`armeabi-v7a` and `arm64-v8a`) with no checked-in prebuilt binaries.
  - 100% green test suite across all 775 automated tests.
