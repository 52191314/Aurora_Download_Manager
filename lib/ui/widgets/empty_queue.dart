import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../theme/aurora_palette.dart';
import 'panel.dart';

class EmptyQueue extends StatefulWidget {
  final String? message;
  final IconData icon;
  final VoidCallback? onPasteLink;
  final VoidCallback? onOpenBrowser;
  final VoidCallback? onAddTorrent;

  const EmptyQueue({
    super.key,
    this.message,
    this.icon = Icons.inbox_outlined,
    this.onPasteLink,
    this.onOpenBrowser,
    this.onAddTorrent,
  });

  @override
  State<EmptyQueue> createState() => _EmptyQueueState();
}

class _EmptyQueueState extends State<EmptyQueue>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    _pulse = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _hasActions =>
      widget.onPasteLink != null ||
      widget.onOpenBrowser != null ||
      widget.onAddTorrent != null;

  @override
  Widget build(BuildContext context) {
    final ac = context.ac;
    final l10n = AppLocalizations.of(context);
    return Panel(
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedBuilder(
                animation: _pulse,
                builder: (context, child) => Transform.scale(
                  scale: _pulse.value,
                  child: child,
                ),
                child: Icon(
                  widget.icon,
                  color: ac.textTertiary,
                  size: 48,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                widget.message ??
                    (l10n?.emptyQueueDesc ??
                        'Paste a link, open the browser, or share a URL from another app.'),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Inter',
                  fontSize: 14,
                  color: ac.textSecondary,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (_hasActions) ...[
                const SizedBox(height: 16),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (widget.onPasteLink != null)
                      _ActionChip(
                        icon: Icons.content_paste_rounded,
                        label: 'Paste link',
                        onTap: widget.onPasteLink!,
                      ),
                    if (widget.onOpenBrowser != null)
                      _ActionChip(
                        icon: Icons.travel_explore_rounded,
                        label: 'Browse the web',
                        onTap: widget.onOpenBrowser!,
                      ),
                    if (widget.onAddTorrent != null)
                      _ActionChip(
                        icon: Icons.hub_outlined,
                        label: 'Magnet / torrent',
                        onTap: widget.onAddTorrent!,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ac = context.ac;
    return ActionChip(
      avatar: Icon(icon, size: 16, color: ac.accentFrost),
      label: Text(label),
      labelStyle: TextStyle(
        fontSize: 12.5,
        fontWeight: FontWeight.w600,
        color: ac.textPrimary,
      ),
      side: BorderSide(color: ac.glassBorder),
      backgroundColor: ac.surfacePanel,
      onPressed: onTap,
    );
  }
}
