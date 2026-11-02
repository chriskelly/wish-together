import 'package:flutter/material.dart';
import 'package:wishtogether/dev/dev_banner.dart';

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
    this.tone = DevBannerTone.refused,
  });

  /// What the strip says, so the page is still visibly a dev page.
  final String label;

  /// One line naming what is wrong.
  final String headline;

  /// What to change, in the order a reader should act on it.
  final List<String> details;

  /// What the strip is claiming. A failure loaded no data, so the default is
  /// the refused tone.
  final DevBannerTone tone;

  /// The one node a driver reads: the same words a reader sees.
  String get semanticsLabel => '$headline. ${details.join(' ')}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Column(
        children: [
          // The strip keeps the bundle marker on every page, failure included.
          DevBanner(label: label, tone: tone),
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

/// The page a dev session shows when the URL names a scenario that does not
/// exist.
class DevErrorScreen extends StatelessWidget {
  const DevErrorScreen({
    super.key,
    required this.requestedScenario,
    required this.availableScenarios,
  });

  /// The id the URL asked for, which the registry does not have.
  final String requestedScenario;

  /// The ids this build can show, in registry order.
  final List<String> availableScenarios;

  @override
  Widget build(BuildContext context) {
    return DevFailureScreen(
      label: devScenarioLabel(requestedScenario),
      headline: 'Unknown scenario "$requestedScenario"',
      // Nothing loaded: the id does not exist, so the strip is not amber.
      tone: DevBannerTone.refused,
      details: <String>[
        'Available scenarios: ${availableScenarios.join(', ')}',
        'Open one with ?scenario=<id> in the address bar.',
      ],
    );
  }
}
