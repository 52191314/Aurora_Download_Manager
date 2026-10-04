import 'package:flutter/material.dart';

import '../../theme/aurora_palette.dart';
import '../../theme/aurora_tokens.dart';

/// IDM-style floating media control that sits over (or near) a detected video.
///
/// Provides quick "Download" and "Play" actions when video is active.
/// Tap → trigger default action (download/play). Long-press → dismiss for this page.
/// Optional drag so the user can move it if it covers controls.
class FloatingVideoButton extends StatefulWidget {
  final VoidCallback onTap;
  final VoidCallback? onDownload;
  final VoidCallback? onPlay;
  final VoidCallback? onDismiss;

  /// Optional label under the icon (kept short, e.g. quality).
  final String? subtitle;

  const FloatingVideoButton({
    super.key,
    required this.onTap,
    this.onDownload,
    this.onPlay,
    this.onDismiss,
    this.subtitle,
  });

  @override
  State<FloatingVideoButton> createState() => _FloatingVideoButtonState();
}

class _FloatingVideoButtonState extends State<FloatingVideoButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl;
  late final Animation<double> _scaleAnim;
  Offset _dragOffset = Offset.zero;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    _scaleAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.elasticOut);
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  void _dismiss() {
    _animCtrl.reverse().then((_) {
      if (mounted) widget.onDismiss?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    final ac = context.ac;
    final hasDualActions = widget.onDownload != null && widget.onPlay != null;

    return Transform.translate(
      offset: _dragOffset,
      child: ScaleTransition(
        scale: _scaleAnim,
        child: GestureDetector(
          onLongPress: _dismiss,
          onPanUpdate: (d) {
            setState(() => _dragOffset += d.delta);
          },
          child: Material(
            color: Colors.transparent,
            child: hasDualActions
                ? _buildDualCapsule(ac)
                : _buildSingleButton(ac),
          ),
        ),
      ),
    );
  }

  Widget _buildDualCapsule(AColors ac) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: ac.surfacePanel.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: ac.accentFrost.withValues(alpha: 0.8),
          width: 1.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Download action
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: widget.onDownload ?? widget.onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: ac.accentFrost.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.download_rounded,
                    color: ac.accentFrost,
                    size: 18,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    widget.subtitle != null && widget.subtitle!.isNotEmpty
                        ? 'Download (${widget.subtitle})'
                        : 'Download',
                    style: TextStyle(
                      color: ac.accentFrost,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 4),
          // Play action
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: widget.onPlay,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: ac.surfaceElevated,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.play_arrow_rounded,
                color: ac.textPrimary,
                size: 20,
              ),
            ),
          ),
          const SizedBox(width: 2),
          // Dismiss X
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: _dismiss,
            child: Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              child: Icon(
                Icons.close_rounded,
                color: ac.textTertiary,
                size: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSingleButton(AColors ac) {
    return GestureDetector(
      onTap: widget.onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: ac.surfacePanel.withValues(alpha: 0.94),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.45),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
              border: Border.all(
                color: ac.accentFrost.withValues(alpha: 0.75),
                width: 2,
              ),
            ),
            child: Icon(
              Icons.play_arrow_rounded,
              color: ac.accentFrost,
              size: 30,
            ),
          ),
          if (widget.subtitle != null && widget.subtitle!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 6,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                widget.subtitle!,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
