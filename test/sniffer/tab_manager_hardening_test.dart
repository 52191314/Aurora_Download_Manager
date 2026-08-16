// Tab-aware hardening tests: per-tab iframe dedup, empty-list invariant,
// and the switch-generation suspend/resume race guard.
//
// Run from the repo root:
//   flutter test test/sniffer/tab_manager_hardening_test.dart

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:aurora_downloader/settings/download_settings.dart';
import 'package:aurora_downloader/sniffer/browser_controller.dart';
import 'package:aurora_downloader/sniffer/media_sniffer_engine.dart';
import 'package:aurora_downloader/sniffer/models/browser_tab.dart';
import 'package:aurora_downloader/sniffer/controllers/tab_manager.dart';
import 'package:aurora_downloader/sniffer/controllers/tab_lifecycle_controller.dart';
import 'package:aurora_downloader/sniffer/controllers/sniff_intake_controller.dart';
import 'package:aurora_downloader/sniffer/safe_browsing_service.dart';
import 'package:aurora_downloader/sniffer/session_recovery.dart';

/// Records suspend/resume calls with controllable completion timing so the
/// switch-generation guard can be exercised deterministically.
class _RecordingController extends MockBrowserController {
  _RecordingController(this.label);

  final String label;
  final List<String> log = [];

  /// When set, [suspendTab] blocks on this before completing (models the
  /// async native pause completion).
  Completer<void>? suspendGate;

  /// When set, [resumeWebView] blocks on this between dispatching the
  /// process-timer resume and applying the per-view resume (models the
  /// `await resumeTimers()` gap in the real [resumeWebView]).
  Completer<void>? resumeGate;

  @override
  Future<void> suspendTab() async {
    log.add('$label.pause');
    final gate = suspendGate;
    if (gate != null) await gate.future;
  }

  @override
  Future<void> resumeWebView({bool checkAlive = true}) async {
    log.add('$label.resumeTimers');
    final gate = resumeGate;
    if (gate != null) await gate.future;
    log.add('$label.resume');
  }
}

BrowserTab _tab(String id, SnifferBrowserController controller) => BrowserTab(
      id: id,
      controller: controller,
      snifferEngine: MediaSnifferEngine(),
      addressController: TextEditingController(),
    );

Future<void> _flush() async {
  for (var i = 0; i < 3; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

/// Minimal [TabLifecycleHost] for the empty-list invariant tests.
class _FakeHost implements TabLifecycleHost {
  _FakeHost(this.tabManager) {
    sniffIntake = SniffIntakeController(
      tabManager: tabManager,
      settings: DownloadSettings.defaults(),
      setState: (fn) => fn(),
      isMounted: () => true,
      uaForProfile: (_) => 'ua',
      downloadUserAgent: (url, tab) => 'ua',
      baseRequestHeaders: () => const {},
      normalizeHeadersForUrl: (headers, url,
              {currentUrl, addressText, sourcePageUrl}) =>
          headers,
      firstNonEmpty: (values) {
        for (final v in values) {
          if (v != null && v.isNotEmpty) return v;
        }
        return null;
      },
    );
  }

  final TabManager tabManager;
  final Set<String> _builtWebViewTabIds = {};
  late final SniffIntakeController sniffIntake;

  @override
  bool get isMounted => true;
  @override
  bool get isDesktopMode => false;
  @override
  BrowserTab get activeTab => tabManager.activeTab;
  @override
  DownloadSettings get settings => DownloadSettings.defaults();
  @override
  String? get baseDir => null;
  @override
  void markNeedsBuild() {}
  @override
  String uaForProfile(String profile) => 'ua';
  @override
  Future<void> loadUrlWithHostSettings(
    BrowserTab tab,
    Uri uri, {
    bool addToHistory = false,
    bool forceInApp = false,
  }) async {}
  @override
  Future<void> configureTabAdblock(BrowserTab tab) async {}
  @override
  Future<void> refreshPageInfo(BrowserTab tab,
      {bool recordHistory = false}) async {}
  @override
  void applyZoomForPage(BrowserTab tab, String url) {}
  @override
  Future<void> applyDarkModeForPage(BrowserTab tab, String url) async {}
  @override
  void switchToActiveTab(int index) => tabManager.switchToActiveTab(index);
  @override
  void cancelPickerIfActive() {}
  @override
  void updateTabNavState(BrowserTab tab) {}
  @override
  void showSnack(String message) {}
  @override
  String titleForUrl(String url) => url;
  @override
  void startVideoPoll(BrowserTab tab) {}
  @override
  void setupTabCallbacks(BrowserTab tab) {}
  @override
  Set<String> get builtWebViewTabIds => _builtWebViewTabIds;
  @override
  SniffIntakeController get sniffIntakeController => sniffIntake;
  @override
  void markTabsLoaded() {}
  @override
  Future<void> ensureTabStartupReady(BrowserTab tab) async {}
}

TabLifecycleController _makeLifecycle(TabManager manager) {
  return TabLifecycleController(
    host: _FakeHost(manager),
    tabManager: manager,
    settings: DownloadSettings.defaults(),
    safeBrowsing: SafeBrowsingService(),
    sessionRecovery: const SessionRecovery(),
    debugControllerFactory: () => MockBrowserController(),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('each tab owns an independent fetchedIframeSrcs set', () {
    final a = _tab('a', MockBrowserController());
    final b = _tab('b', MockBrowserController());
    addTearDown(a.dispose);
    addTearDown(b.dispose);

    a.fetchedIframeSrcs.add('https://cdn/x');

    expect(a.fetchedIframeSrcs, contains('https://cdn/x'));
    expect(b.fetchedIframeSrcs, isEmpty);
    expect(identical(a.fetchedIframeSrcs, b.fetchedIframeSrcs), isFalse);
  });

  test('stale resume from a superseded switch is reverted (background tab '
      'is not resurrected)', () async {
    final a = _RecordingController('A');
    final b = _RecordingController('B');
    final c = _RecordingController('C');
    final manager = TabManager();
    manager.tabs.add(_tab('0', a));
    manager.tabs.add(_tab('1', b));
    manager.tabs.add(_tab('2', c));

    // A -> B: resume B is deferred behind its process-timer gap.
    b.resumeGate = Completer<void>();
    manager.switchToActiveTab(1);

    // B -> C (rapid, before B's resume completes): suspend B, resume C.
    manager.switchToActiveTab(2);

    // Release B's stale resume. The generation guard sees it is stale (B is
    // no longer active) and re-suspends B.
    b.resumeGate!.complete();
    b.resumeGate = null;
    await _flush();

    // B ends suspended — the stale resume did not stick.
    expect(b.log.last, 'B.pause');
    expect(b.log, contains('B.resume'));
    // The active tab C ends resumed.
    expect(c.log.last, 'C.resume');
    // A was suspended once and never resurrected.
    expect(a.log, ['A.pause']);
  });

  test('stale suspend is undone when its tab is re-activated', () async {
    final a = _RecordingController('A');
    final b = _RecordingController('B');
    final manager = TabManager();
    manager.tabs.add(_tab('0', a));
    manager.tabs.add(_tab('1', b));

    // A -> B: defer A's suspend completion.
    a.suspendGate = Completer<void>();
    manager.switchToActiveTab(1);

    // B -> A (rapid, before A's suspend completes): suspend B, resume A.
    manager.switchToActiveTab(0);

    // Release A's stale suspend. The generation guard sees A is active again
    // and undoes the stale suspend with a resume.
    a.suspendGate!.complete();
    a.suspendGate = null;
    await _flush();

    // The active tab A must never be left paused.
    expect(a.log.last, 'A.resume');
    expect(b.log.last, 'B.pause');
  });

  test('closeAllTabs never leaves the tab list observably empty', () {
    final manager = TabManager();
    final lifecycle = _makeLifecycle(manager);
    lifecycle.openNewTab();
    lifecycle.openNewTab();
    expect(manager.tabs, hasLength(2));

    lifecycle.closeAllTabs();

    expect(manager.tabs, isNotEmpty);
    expect(() => manager.activeTab, returnsNormally);
  });

  test('closeGroup re-adds a blank tab when the group holds every tab', () {
    final manager = TabManager();
    final lifecycle = _makeLifecycle(manager);
    lifecycle.openNewTab();
    lifecycle.openNewTab();
    for (final tab in manager.tabs) {
      tab.groupName = 'g1';
    }
    expect(manager.tabs, hasLength(2));

    lifecycle.closeGroup('g1');

    expect(manager.tabs, isNotEmpty);
    expect(() => manager.activeTab, returnsNormally);
    expect(manager.tabs.every((t) => t.groupName == null), isTrue);
  });

  test('openNewTab in tight loop generates unique tab IDs', () {
    final manager = TabManager();
    final lifecycle = _makeLifecycle(manager);
    const count = 30;
    for (var i = 0; i < count; i++) {
      lifecycle.openNewTab(url: 'https://example.com/$i', switchToTab: false);
    }
    final ids = manager.tabs.map((t) => t.id).toSet();
    expect(ids.length, count);
  });
}
