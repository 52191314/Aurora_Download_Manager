import 'package:flutter_test/flutter_test.dart';

import 'package:aurora_downloader/settings/donation_prompt_store.dart';

void main() {
  const int day = 86400000; // ms
  const int install = 1_700_000_000_000; // arbitrary epoch anchor

  group('shouldShowDonationPrompt (7-day grace, 7-day cooldown)', () {
    test('never ask again wins over everything', () {
      expect(
        shouldShowDonationPrompt(
          neverAskAgain: true,
          installEpochMs: install,
          lastPromptEpochMs: 0,
          nowEpochMs: install + 90 * day,
        ),
        isFalse,
      );
    });

    test('silent inside the 7-day install grace period', () {
      expect(
        shouldShowDonationPrompt(
          neverAskAgain: false,
          installEpochMs: install,
          lastPromptEpochMs: 0,
          nowEpochMs: install + 3 * day,
        ),
        isFalse,
      );
      // Exactly at the boundary (7 days) the grace has passed.
      expect(
        shouldShowDonationPrompt(
          neverAskAgain: false,
          installEpochMs: install,
          lastPromptEpochMs: 0,
          nowEpochMs: install + 7 * day,
        ),
        isTrue,
      );
    });

    test('prompts after grace when never prompted before', () {
      expect(
        shouldShowDonationPrompt(
          neverAskAgain: false,
          installEpochMs: install,
          lastPromptEpochMs: 0,
          nowEpochMs: install + 8 * day,
        ),
        isTrue,
      );
    });

    test('silent inside the 7-day cooldown after a prompt', () {
      final prompted = install + 8 * day;
      expect(
        shouldShowDonationPrompt(
          neverAskAgain: false,
          installEpochMs: install,
          lastPromptEpochMs: prompted,
          nowEpochMs: prompted + 6 * day,
        ),
        isFalse,
      );
    });

    test('prompts again once the cooldown has elapsed', () {
      final prompted = install + 8 * day;
      expect(
        shouldShowDonationPrompt(
          neverAskAgain: false,
          installEpochMs: install,
          lastPromptEpochMs: prompted,
          nowEpochMs: prompted + 7 * day,
        ),
        isTrue,
      );
    });

    test('custom cadence honors overridden durations', () {
      expect(
        shouldShowDonationPrompt(
          neverAskAgain: false,
          installEpochMs: install,
          lastPromptEpochMs: 0,
          nowEpochMs: install + 1 * day,
          gracePeriod: const Duration(days: 1),
        ),
        isTrue,
      );
    });
  });
}
