import 'package:flutter/material.dart';
import 'package:wishtogether/dev/dev_config.dart';

/// The chrome around every dev page: the strip that marks the build, and one
/// accessibility node naming the scenario.
///
/// The label sits on an *ancestor* of the pages rather than on the strip. Flutter
/// drops the semantics of anything painted before a route, so a labelled strip
/// beside the navigator is invisible to an accessibility tree no matter how the
/// strip itself is wrapped — and a driver that addresses widgets by role and
/// label would then have no way to say which scenario is on screen.
class DevSessionFrame extends StatelessWidget {
  const DevSessionFrame({
    super.key,
    required this.scenarioId,
    required this.pages,
  });

  /// The id of the scenario being shown.
  final String scenarioId;

  /// Everything below the strip: the app's own navigator and pages.
  final Widget pages;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: 'Dev session · scenario: $scenarioId',
      child: Column(
        children: [
          DevBanner(scenarioId: scenarioId),
          Expanded(child: pages),
        ],
      ),
    );
  }
}

/// The strip a development session shows above every page.
///
/// It exists so a screenshot cannot be mistaken for the real app: it names the
/// scenario the data came from, which also makes a silent fallback to the
/// `default` scenario visible at a glance. It is deliberately silent in the
/// accessibility tree — [DevSessionFrame] carries the name, because only a node
/// above the pages is not dropped.
class DevBanner extends StatelessWidget {
  const DevBanner({super.key, required this.scenarioId});

  /// The id of the scenario being shown.
  final String scenarioId;

  @override
  Widget build(BuildContext context) {
    return Material(
      // The key carries the marker a CI guard searches the compiled production
      // bundle for: this literal exists in a dev build and in no other.
      key: const ValueKey<String>(devBundleMarker),
      color: const Color(0xFFFFE082),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            const Icon(Icons.science_outlined, size: 16, color: Colors.black87),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Dev session · scenario: $scenarioId',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.black87,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
