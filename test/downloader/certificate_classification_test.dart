import 'dart:io';

import 'package:aurora_downloader/downloader/download_error_classifier.dart';
import 'package:aurora_downloader/downloader/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TLS / certificate classification', () {
    test('self-signed certificate -> certificateInvalid', () {
      final error = HandshakeException(
        'Handshake error in client (OS Error: CERTIFICATE_VERIFY_FAILED: '
        'self-signed certificate(ssl_error_certificate_verify_failed), errno = 11)',
      );
      expect(
        DownloadErrorClassifier.classify(error),
        DownloadFailure.certificateInvalid,
      );
    });

    test('untrusted issuer chain -> certificateInvalid', () {
      expect(
        DownloadErrorClassifier.classify(
          TlsException('CERTIFICATE_VERIFY_FAILED: unable to get local issuer certificate'),
        ),
        DownloadFailure.certificateInvalid,
      );
    });

    test('generic handshake failure stays connectionReset', () {
      expect(
        DownloadErrorClassifier.classify(
          HandshakeException('Handshake error in client'),
        ),
        DownloadFailure.connectionReset,
      );
    });

    test('heuristic path: certificate text without a typed exception', () {
      expect(
        DownloadErrorClassifier.classify(
          Exception('certificate verify failed: self-signed certificate'),
        ),
        DownloadFailure.certificateInvalid,
      );
    });

    test('real DNS failures are unaffected', () {
      expect(
        DownloadErrorClassifier.classify(
          const SocketException('Failed host lookup: open.stealth.si'),
        ),
        DownloadFailure.dnsLookupFailed,
      );
    });

    test('certificateInvalid is a network-class, non-resniffable failure', () {
      const reason = DownloadFailure.certificateInvalid;
      expect(reason.isNetworkIssue, isTrue);
      expect(reason.analyticsClass, 'network');
      expect(reason.isResniffable, isFalse);
      expect(reason.userFacingTitle, 'Site Certificate Invalid');
      expect(reason.actionableAdvice, contains('certificate'));
    });

    test('appLinkIntent carries browser-handoff advice', () {
      const reason = DownloadFailure.appLinkIntent;
      expect(reason.isResniffable, isFalse);
      expect(reason.actionableAdvice, contains('browser'));
    });
  });
}
