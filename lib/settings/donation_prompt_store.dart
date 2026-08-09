import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Donation links for the OSS edition (shown in-app and on the F-Droid listing).
class DonationLinks {
  static const String patreon = 'https://www.patreon.com/c/Ahjie521';
  static const String usdtLabel = 'USDT (BEP20 / BSC)';
  static const String usdtBep20 = '0xd08d47bde441888166b801616754c667672cd502';
}

/// Pure decision rule for the periodic, non-blocking donation prompt.
///
/// Prompts when the user has not opted out, the install grace period has
/// passed, and the previous prompt is older than the cooldown. Both periods
/// default to 7 days.
bool shouldShowDonationPrompt({
  required bool neverAskAgain,
  required int installEpochMs,
  required int lastPromptEpochMs,
  required int nowEpochMs,
  Duration gracePeriod = const Duration(days: 7),
  Duration cooldown = const Duration(days: 7),
}) {
  if (neverAskAgain) return false;
  if (nowEpochMs - installEpochMs < gracePeriod.inMilliseconds) return false;
  if (lastPromptEpochMs > 0 &&
      nowEpochMs - lastPromptEpochMs < cooldown.inMilliseconds) {
    return false;
  }
  return true;
}

/// File-backed state for the donation prompt (same pattern as
/// [ProEntitlementStore]: a small JSON file in the app support directory).
class DonationPromptStore {
  static const _fileName = 'donation_prompt.json';

  bool _neverAskAgain = false;
  int _installEpochMs = 0;
  int _lastPromptEpochMs = 0;

  bool get neverAskAgain => _neverAskAgain;
  int get installEpochMs => _installEpochMs;
  int get lastPromptEpochMs => _lastPromptEpochMs;

  Future<void> load() async {
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/$_fileName');
      if (!await file.exists()) {
        _installEpochMs = DateTime.now().millisecondsSinceEpoch;
        await _write(file);
        return;
      }
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      _neverAskAgain = json['neverAskAgain'] == true;
      _lastPromptEpochMs = (json['lastPromptEpochMs'] as num?)?.toInt() ?? 0;
      _installEpochMs = (json['installEpochMs'] as num?)?.toInt() ??
          DateTime.now().millisecondsSinceEpoch;
    } catch (e) {
      // Corrupt/missing file is treated as a fresh install; never throws.
      debugPrint('[donation] store load failed: $e');
      if (_installEpochMs == 0) {
        _installEpochMs = DateTime.now().millisecondsSinceEpoch;
      }
    }
  }

  Future<void> _write(File file) async {
    await file.writeAsString(jsonEncode({
      'schemaVersion': 1,
      'neverAskAgain': _neverAskAgain,
      'lastPromptEpochMs': _lastPromptEpochMs,
      'installEpochMs': _installEpochMs,
    }));
  }

  /// Records that the prompt was shown (starts the cooldown).
  Future<void> markPrompted() async {
    _lastPromptEpochMs = DateTime.now().millisecondsSinceEpoch;
    try {
      final dir = await getApplicationSupportDirectory();
      await _write(File('${dir.path}/$_fileName'));
    } catch (e) {
      debugPrint('[donation] store write failed: $e');
    }
  }

  /// Permanent opt-out ("Never ask again").
  Future<void> setNeverAskAgain() async {
    _neverAskAgain = true;
    try {
      final dir = await getApplicationSupportDirectory();
      await _write(File('${dir.path}/$_fileName'));
    } catch (e) {
      debugPrint('[donation] store write failed: $e');
    }
  }
}
