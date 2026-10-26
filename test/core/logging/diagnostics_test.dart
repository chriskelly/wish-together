import 'package:flutter_test/flutter_test.dart';
import 'package:wishtogether/core/logging/app_event.dart';
import 'package:wishtogether/core/logging/diagnostics.dart';

import 'recording_sink.dart';
import 'recording_transport.dart';

import 'package:wishtogether/core/logging/sentry_startup.dart';

void main() {
  group('createLaunchDiagnostics', () {
    test('omits the Sentry sink when no transport is supplied', () {
      final diagnostics = createLaunchDiagnostics(
        identity: BuildIdentity(
          build: testSession.build,
          platform: testSession.platform,
        ),
        consoleEnabled: false,
      );

      expect(diagnostics.sentrySink, isNull);
      expect(diagnostics.log.session.build, testSession.build);
      expect(diagnostics.log.session.platform, testSession.platform);
    });

    test('fans records out to Sentry when a transport is supplied', () {
      final transport = RecordingTransport();
      final diagnostics = createLaunchDiagnostics(
        identity: BuildIdentity(
          build: testSession.build,
          platform: testSession.platform,
        ),
        consoleEnabled: false,
        sentryTransport: transport,
      );

      diagnostics.log.event(
        const AuthStateEvent(outcome: AuthOutcome.signedOut),
      );

      expect(transport.breadcrumbs, hasLength(1));
    });
  });

  group('authOutcomeFor', () {
    test('maps a signed-out session', () {
      expect(
        authOutcomeFor(signedIn: false, providerIds: const <String>[]),
        AuthOutcome.signedOut,
      );
    });

    test('maps the provider ids', () {
      expect(
        authOutcomeFor(signedIn: true, providerIds: const ['phone']),
        AuthOutcome.phone,
      );
      expect(
        authOutcomeFor(signedIn: true, providerIds: const ['google.com']),
        AuthOutcome.google,
      );
      expect(
        authOutcomeFor(signedIn: true, providerIds: const ['apple.com']),
        AuthOutcome.apple,
      );
    });

    test('names the last linked provider on a linked account', () {
      expect(
        authOutcomeFor(
          signedIn: true,
          providerIds: const ['google.com', 'apple.com'],
        ),
        AuthOutcome.apple,
      );
    });

    test('reports nothing for a provider outside the vocabulary', () {
      expect(
        authOutcomeFor(signedIn: true, providerIds: const ['password']),
        isNull,
      );
    });
  });
}
