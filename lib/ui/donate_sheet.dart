import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../settings/donation_prompt_store.dart';
import '../sniffer/external_scheme.dart';

/// Modal bottom sheet with the project's donation options (Patreon + USDT).
///
/// The donation page row launches the system browser via ACTION_VIEW — the
/// user's default browser opens it, or the system resolver prompts when no
/// default is set. [showNeverAgain] renders the permanent opt-out used by
/// the periodic prompt (not the settings row).
Future<void> showDonateSheet(
  BuildContext context, {
  bool showNeverAgain = false,
  Future<void> Function()? onNeverAskAgain,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => DonateSheet(
      showNeverAgain: showNeverAgain,
      onNeverAskAgain: onNeverAskAgain,
    ),
  );
}

class DonateSheet extends StatelessWidget {
  final bool showNeverAgain;
  final Future<void> Function()? onNeverAskAgain;

  const DonateSheet({
    super.key,
    this.showNeverAgain = false,
    this.onNeverAskAgain,
  });

  Future<void> _copy(BuildContext context, String text, String label) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text('$label copied to clipboard'),
      duration: const Duration(seconds: 2),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Support Aurora Download Manager',
              style: theme.textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              'This app is free and open source (GPL-3.0), fully unlocked, with no '
              'ads and no trackers. If you would like to support development, '
              'donations are welcome:',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.favorite_rounded, color: Colors.redAccent),
              title: const Text('Donation page'),
              subtitle: const Text(DonationLinks.website),
              trailing: const Icon(Icons.open_in_new_rounded, size: 18),
              onTap: () async {
                // ACTION_VIEW: default browser, or system resolver when no
                // default is set. Falls back to copying on failure.
                final ok = await launchExternalAppUrl(DonationLinks.website);
                if (!ok && context.mounted) {
                  await _copy(context, DonationLinks.website, 'Donation link');
                }
              },
            ),
            const Divider(height: 1),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.account_balance_wallet_rounded),
              title: const Text(DonationLinks.usdtLabel),
              subtitle: Text(
                DonationLinks.usdtBep20,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
              trailing: const Icon(Icons.copy_rounded, size: 18),
              onTap: () =>
                  _copy(context, DonationLinks.usdtBep20, 'USDT address'),
            ),
            if (showNeverAgain) ...[
              const SizedBox(height: 8),
              Center(
                child: TextButton(
                  onPressed: () async {
                    await onNeverAskAgain?.call();
                    if (!context.mounted) return;
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text('You will not be asked about donations again.'),
                      duration: Duration(seconds: 2),
                    ));
                  },
                  child: const Text('Don\u2019t ask again'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
