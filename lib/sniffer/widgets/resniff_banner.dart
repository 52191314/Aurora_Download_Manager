import 'package:flutter/material.dart';

import '../../theme/aurora_palette.dart';

/// Floating banner displayed at the top of the browser when the active tab
/// is in a targeted resniff session for a failed download task.
class ResniffBanner extends StatelessWidget {
  const ResniffBanner({
    super.key,
    required this.taskName,
    required this.onTap,
    required this.onExit,
  });

  final String taskName;
  final VoidCallback onTap;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) {
    final ac = context.ac;
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(12),
      color: ac.overlaySurface,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: ac.accentAmber.withValues(alpha: 0.6),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: ac.accentAmber.withValues(alpha: 0.15),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(Icons.find_replace_rounded, color: ac.accentAmber, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Resniffing: $taskName',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: ac.textPrimary,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Play video on page to capture new link • Tap to view',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: ac.accentAmber,
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: onExit,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                foregroundColor: ac.statusError,
              ),
              child: const Text(
                'Exit',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
