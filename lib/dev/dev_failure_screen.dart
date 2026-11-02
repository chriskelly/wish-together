import 'package:flutter/material.dart';
import 'package:wishtogether/core/theme.dart';
import 'package:wishtogether/dev/dev_banner.dart';
import 'package:wishtogether/dev/dev_config.dart';
import 'package:wishtogether/dev/fixtures/registry.dart';

/// The one place a failure's text becomes an accessibility label.
///
/// The page and any test that asserts on it read this same function. Joining the
/// lines twice would let a test pass on text it composed itself while the page
/// rendered nothing.
String failureSemanticsLabel(String headline, List<String> details) =>
    '$headline. ${details.join(' ')}';

/// The page a dev session shows when it cannot start, or when a scenario id
/// does not exist.
///
/// A launch failure happens before `runApp`, so without a page like this a bad
/// input is a blank white browser tab whose only trace is a console error,
/// which is exactly the thing an agent with no console listener cannot see.
/// [headline] and [details] are on the page and in one accessibility node, so
/// the corrected command is one edit away.
class DevFailureScreen extends StatelessWidget {
  const DevFailureScreen({
    super.key,
    required this.label,
    required this.headline,
    required this.details,
  });

  /// What the strip says, so the page is still visibly a dev page.
  final String label;

  /// One line naming what is wrong.
  final String headline;

  /// What to change, in the order a reader should act on it.
  final List<String> details;

  /// The one node a driver reads: the same words a reader sees.
  String get semanticsLabel => failureSemanticsLabel(headline, details);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Column(
        children: [
          // A failure page loaded no data, so its strip never claims any. The
          // strip also keeps the bundle marker on every page, this one included.
          DevBanner(label: label, tone: DevBannerTone.refused),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Semantics(
                  // One node carries the whole failure. A driver that addresses
                  // by role and label then reads the same words a reader sees,
                  // including every line of the fix, without having to assume
                  // how the lines were split.
                  container: true,
                  excludeSemantics: true,
                  label: semanticsLabel,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(headline, style: theme.textTheme.titleLarge),
                      for (final detail in details) ...[
                        const SizedBox(height: 12),
                        Text(detail, style: theme.textTheme.bodyLarge),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One dev page, inside the app's own theme.
///
/// Every dev page — a session, a failure, a refusal — is the production theme
/// over a dev strip, so the theme is applied here rather than per page.
Widget buildDevPageApp(Widget home) => MaterialApp(
  title: 'WishTogether dev session',
  debugShowCheckedModeBanner: false,
  theme: lightTheme,
  darkTheme: darkTheme,
  themeMode: ThemeMode.system,
  home: home,
);

/// The page shown for a scenario id the registry does not have.
Widget buildUnknownScenarioApp(String requestedScenario) => buildDevPageApp(
  DevFailureScreen(
    label: devScenarioLabel(requestedScenario),
    headline: 'Unknown scenario "$requestedScenario"',
    details: <String>[
      'Available scenarios: ${devScenarios.keys.join(', ')}',
      'Open one with ?scenario=<id> in the address bar.',
    ],
  ),
);

/// The page shown when the build cannot run what it was asked for.
///
/// A refused launch is still a page: the reason and the fix are the whole point
/// of refusing, and a blank tab tells a reader nothing.
Widget buildRefusedDevApp(RefusedDevLaunch refusal) => buildDevPageApp(
  DevFailureScreen(
    label: devNotStartedLabel,
    headline: refusal.headline,
    details: refusal.details,
  ),
);
