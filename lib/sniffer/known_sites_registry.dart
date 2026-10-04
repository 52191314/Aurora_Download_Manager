// Known-site registry — static, offline knowledge about hosts with known
// bad behaviour, surfaced as small notices in the capture/queue/support UI.
//
// Pure Dart (no Flutter imports) so it is unit-testable in isolation.
// Seed data comes from the live site debug of 2026-09-11 plus the site-study
// verdicts; keep entries factual and site-specific, never accusatory.
//
// When a host starts behaving, delete its entry — stale warnings erode trust.

/// Visual weight of the notice.
enum SiteWarning { info, warning }

class KnownSite {
  /// Suffix match (lowercased). `example.com` also matches `cdn.example.com`.
  final String hostSuffix;
  final SiteWarning severity;

  /// One-line notice headline.
  final String title;

  /// Optional second line with what the user can actually do.
  final String? detail;

  /// Machine-readable behaviours so callers can adapt (not just display):
  /// `refreshOnExpire`, `deadTls`, `torrentSource`, `appLinkOnly`,
  /// `transientDns`.
  final Set<String> behaviors;

  const KnownSite(
    this.hostSuffix,
    this.severity,
    this.title, [
    this.detail,
    this.behaviors = const <String>{},
  ]);
}

const List<KnownSite> knownSites = <KnownSite>[
  KnownSite(
    'open.stealth.si',
    SiteWarning.warning,
    'This site has a broken security certificate.',
    "Downloads from this site usually fail at connection - it is the site's fault, not your phone or network. Try another source.",
    {'deadTls'},
  ),
  KnownSite(
    'okcdn.ru',
    SiteWarning.warning,
    'OK.ru streams use short-lived signed links.',
    'If a download fails with "Stream Link Expired", tap Refresh for a fresh link. Automatic repair is a Pro feature.',
    {'refreshOnExpire'},
  ),
  KnownSite(
    'cloudwindow-route.com',
    SiteWarning.info,
    'This CDN sometimes times out on certain networks.',
    'A quick retry usually succeeds. If it keeps timing out, your route to this CDN may be blocked.',
    {'transientDns'},
  ),
  KnownSite(
    'filestore.app',
    SiteWarning.info,
    'This host only serves signed direct links.',
    'A DNS failure here is usually momentary - retry in a few seconds.',
    {'transientDns'},
  ),
  KnownSite(
    'goo.gl',
    SiteWarning.info,
    'Google short links can resolve to Android app links (intent://).',
    'App links cannot be downloaded directly. Open them in the browser instead.',
    {'appLinkOnly'},
  ),
  KnownSite(
    'webtor.io',
    SiteWarning.info,
    'Torrent / magnet source.',
    'Magnet downloads need the torrent engine. "Torrent Engine Unavailable" means the engine could not load on this device.',
    {'torrentSource'},
  ),
  KnownSite(
    'limetorrents.fun',
    SiteWarning.info,
    'Torrent / magnet source.',
    'Magnet downloads need the torrent engine. "Torrent Engine Unavailable" means the engine could not load on this device.',
    {'torrentSource'},
  ),
];

/// Returns the most specific (longest-suffix) matching entry, or null.
KnownSite? lookupKnownSite(String urlOrHost) {
  final raw = urlOrHost.trim().toLowerCase();
  if (raw.isEmpty) return null;
  String host = raw;
  if (raw.contains('://') || raw.startsWith('//')) {
    host = Uri.tryParse(raw)?.host.toLowerCase() ?? raw;
  } else {
    final slash = raw.indexOf('/');
    if (slash != -1) host = raw.substring(0, slash);
  }
  if (host.isEmpty) return null;

  KnownSite? best;
  for (final site in knownSites) {
    if (host == site.hostSuffix || host.endsWith('.${site.hostSuffix}')) {
      if (best == null || site.hostSuffix.length > best.hostSuffix.length) {
        best = site;
      }
    }
  }
  return best;
}
