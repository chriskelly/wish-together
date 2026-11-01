import 'package:flutter/material.dart';
import 'package:wishtogether/dev/dev_banner.dart';

/// The page a dev session shows when the URL names a scenario that does not
/// exist.
///
/// The fixture lookup fails before `runApp`, so without a page like this a bad
/// id is a blank white browser tab whose only trace is a console error, which
/// is exactly the thing an agent with no console listener cannot see. The ids
/// that do exist are on the page, so the corrected URL is one edit away.
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
    final theme = Theme.of(context);
    final available = availableScenarios.join(', ');
    return Scaffold(
      body: Column(
        children: [
          // The strip names what was asked for, so this page is still visibly a
          // dev page and still carries the bundle marker.
          DevBanner(scenarioId: requestedScenario),
          Expanded(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Semantics(
                  // One node carries the whole failure. A driver that addresses
                  // by role and label then reads the same words a reader sees,
                  // including every id that would have worked, without having
                  // to assume how the lines were split.
                  container: true,
                  excludeSemantics: true,
                  label:
                      'Unknown scenario "$requestedScenario". '
                      'Available scenarios: $available.',
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Unknown scenario "$requestedScenario"',
                        style: theme.textTheme.titleLarge,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Available scenarios: $available',
                        style: theme.textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Open one with ?scenario=<id> in the address bar.',
                        style: theme.textTheme.bodyMedium,
                      ),
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
