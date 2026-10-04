import 'package:flutter/material.dart';

import '../../theme/aurora_palette.dart';

/// One row in the Chrome-style overflow popup.
class OverflowMenuEntry {
  final IconData icon;
  final String label;
  final Color? color;
  final String? badge;
  final VoidCallback onTap;
  final bool isDivider;
  final bool isHeader;

  const OverflowMenuEntry({
    required this.icon,
    required this.label,
    this.color,
    this.badge,
    required this.onTap,
  })  : isDivider = false,
        isHeader = false;

  const OverflowMenuEntry.divider()
      : icon = Icons.remove,
        label = '',
        color = null,
        badge = null,
        onTap = _noop,
        isDivider = true,
        isHeader = false;

  const OverflowMenuEntry.header(this.label)
      : icon = Icons.label_outline,
        color = null,
        badge = null,
        onTap = _noop,
        isDivider = false,
        isHeader = true;

  static void _noop() {}
}

/// Kept so existing tests compile. The popup is a single list now.
enum OverflowMenuSegment { settings, tools }

class OverflowMenuSegmentStore {
  static OverflowMenuSegment last = OverflowMenuSegment.settings;
}

/// Right-bottom floating card matching Chrome's overflow geometry.
Future<void> showBrowserOverflowPopup(
  BuildContext context, {
  String? pageTitle,
  String? pageUrl,
  bool isSecure = false,
  VoidCallback? onShare,
  List<OverflowMenuEntry>? entries,
  List<OverflowMenuEntry> settingsEntries = const [],
  List<OverflowMenuEntry> toolEntries = const [],
  OverflowMenuSegment? initialSegment,
  ValueChanged<List<String>>? onReorderSettings,
  ValueChanged<List<String>>? onReorderTools,
}) {
  final host = () {
    final raw = pageUrl?.trim() ?? '';
    if (raw.isEmpty) return '';
    return Uri.tryParse(raw)?.host ?? raw;
  }();
  final title = (pageTitle != null && pageTitle.trim().isNotEmpty)
      ? pageTitle.trim()
      : (host.isNotEmpty ? host : 'Current page');

  final combined = entries ??
      <OverflowMenuEntry>[
        ...toolEntries,
        if (toolEntries.isNotEmpty && settingsEntries.isNotEmpty)
          const OverflowMenuEntry.divider(),
        ...settingsEntries,
      ];

  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss menu',
    barrierColor: Colors.black.withValues(alpha: 0.35),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (ctx, anim, secondary) {
      return const SizedBox.shrink();
    },
    transitionBuilder: (ctx, anim, secondary, child) {
      final size = MediaQuery.sizeOf(ctx);
      final pad = MediaQuery.paddingOf(ctx);
      final maxW = (size.width * 0.78).clamp(280.0, 360.0);
      final maxH = size.height * 0.72;
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);

      return Stack(
        children: [
          Positioned(
            right: 12,
            bottom: pad.bottom + 56,
            child: FadeTransition(
              opacity: curved,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
                alignment: Alignment.bottomRight,
                child: Material(
                  color: Colors.transparent,
                  child: _OverflowCard(
                    maxWidth: maxW,
                    maxHeight: maxH,
                    title: title,
                    host: host,
                    isSecure: isSecure,
                    onShare: onShare,
                    entries: combined,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}

class _OverflowCard extends StatelessWidget {
  final double maxWidth;
  final double maxHeight;
  final String title;
  final String host;
  final bool isSecure;
  final VoidCallback? onShare;
  final List<OverflowMenuEntry> entries;

  const _OverflowCard({
    required this.maxWidth,
    required this.maxHeight,
    required this.title,
    required this.host,
    required this.isSecure,
    required this.entries,
    this.onShare,
  });

  @override
  Widget build(BuildContext context) {
    final ac = context.ac;
    final initial = host.isNotEmpty ? host[0].toUpperCase() : 'A';

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: maxWidth,
        maxHeight: maxHeight,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: ac.overlay,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: ac.glassBorder),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.45),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 8, 10),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 18,
                      backgroundColor: ac.surfaceElevated,
                      child: Text(
                        initial,
                        style: TextStyle(
                          color: ac.textPrimary,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                isSecure
                                    ? Icons.lock_rounded
                                    : Icons.lock_open_rounded,
                                size: 12,
                                color: ac.textSecondary,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: ac.textPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (host.isNotEmpty)
                            Text(
                              host,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: ac.textSecondary,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (onShare != null)
                      IconButton(
                        tooltip: 'Share',
                        icon: Icon(
                          Icons.ios_share_rounded,
                          size: 20,
                          color: ac.textPrimary,
                        ),
                        onPressed: () {
                          Navigator.of(context).pop();
                          onShare!();
                        },
                      ),
                  ],
                ),
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 10),
                  itemCount: entries.length,
                  itemBuilder: (context, i) {
                    final e = entries[i];
                    if (e.isDivider) {
                      return Padding(
                        key: ValueKey('divider_$i'),
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Divider(
                          height: 1,
                          thickness: 1,
                          color: ac.borderHairline,
                        ),
                      );
                    }
                    if (e.isHeader) {
                      return Padding(
                        key: ValueKey('header_${i}_${e.label}'),
                        padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
                        child: Text(
                          e.label.toUpperCase(),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: ac.textTertiary,
                            letterSpacing: 0.8,
                          ),
                        ),
                      );
                    }
                    return Material(
                      key: ValueKey('row_${i}_${e.label}'),
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          Navigator.of(context).pop();
                          e.onTap();
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 18,
                            vertical: 13,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                e.icon,
                                size: 22,
                                color: e.color ?? ac.textPrimary,
                              ),
                              const SizedBox(width: 18),
                              Expanded(
                                child: Text(
                                  e.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w400,
                                    color: ac.textPrimary,
                                  ),
                                ),
                              ),
                              if (e.badge != null) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: ac.accentAmber.withValues(alpha: 0.18),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    e.badge!,
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: ac.accentAmber,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
