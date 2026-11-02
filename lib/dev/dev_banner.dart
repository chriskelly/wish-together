import 'package:flutter/material.dart';
import 'package:wishtogether/dev/dev_config.dart';

/// The banner text for a fake-mode session.
String devScenarioLabel(String scenarioId) =>
    'Dev session · scenario: $scenarioId';

/// The banner text for a live session.
///
/// [ignoredScenario] is the `?scenario=` the page URL asked for. Live data has
/// no scenario, so the banner says the request was ignored: otherwise staging
/// data could be read as the fixture of that name.
String devLiveLabel(String databaseId, {String? ignoredScenario}) {
  final base = 'Dev session · live data · database: $databaseId';
  final ignored = ignoredScenario?.trim() ?? '';
  if (ignored.isEmpty) {
    return base;
  }
  return '$base · scenario "$ignored" ignored';
}

/// The banner text for a launch that did not start.
const String devNotStartedLabel = 'Dev session · not started';

/// What the strip is claiming about the data on screen.
///
/// The colour is part of the claim, not decoration: amber means an in-memory
/// fixture, red means real data from a named database, grey means no data was
/// ever loaded. A screenshot carries the colour even when the text is too small
/// to read.
enum DevBannerTone {
  /// An in-memory fixture, chosen by a scenario id.
  scenario(color: Color(0xFFFFE082), icon: Icons.science_outlined),

  /// Real data from a named database.
  live(color: Color(0xFFFFCDD2), icon: Icons.warning_amber_rounded),

  /// Nothing loaded: the launch was refused or the sign-in failed.
  refused(color: Color(0xFFE0E0E0), icon: Icons.error_outline);

  const DevBannerTone({required this.color, required this.icon});

  final Color color;
  final IconData icon;
}

/// The chrome around every dev page: the strip that marks the build, and one
/// accessibility node naming what the session is showing.
///
/// The label sits on an *ancestor* of the pages rather than on the strip. Flutter
/// drops the semantics of anything painted before a route, so a labelled strip
/// beside the navigator is invisible to an accessibility tree no matter how the
/// strip itself is wrapped — and a driver that addresses widgets by role and
/// label would then have no way to say what is on screen.
class DevSessionFrame extends StatelessWidget {
  const DevSessionFrame({
    super.key,
    required this.label,
    required this.pages,
    this.tone = DevBannerTone.scenario,
  });

  /// A fake-mode session showing [scenarioId].
  factory DevSessionFrame.scenario(
    String scenarioId, {
    required Widget pages,
  }) => DevSessionFrame(label: devScenarioLabel(scenarioId), pages: pages);

  /// A live session against [databaseId].
  ///
  /// [ignoredScenario] is the `?scenario=` the URL asked for, which live mode
  /// ignores.
  factory DevSessionFrame.live(
    String databaseId, {
    required Widget pages,
    String? ignoredScenario,
  }) => DevSessionFrame(
    label: devLiveLabel(databaseId, ignoredScenario: ignoredScenario),
    pages: pages,
    tone: DevBannerTone.live,
  );

  /// What this session is showing, in the strip and in the accessibility tree.
  final String label;

  /// Everything below the strip: the app's own navigator and pages.
  final Widget pages;

  /// What the label is claiming about the data.
  final DevBannerTone tone;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: label,
      child: Column(
        children: [
          DevBanner(label: label, tone: tone),
          Expanded(child: pages),
        ],
      ),
    );
  }
}

/// The strip a development session shows above every page.
///
/// It exists so a screenshot cannot be mistaken for the real app: it names the
/// scenario, or the database the live data came from. It is deliberately silent
/// in the accessibility tree — [DevSessionFrame] carries the name, because only
/// a node above the pages is not dropped.
class DevBanner extends StatelessWidget {
  const DevBanner({
    super.key,
    required this.label,
    this.tone = DevBannerTone.scenario,
  });

  /// What this session is showing.
  final String label;

  /// What the label is claiming about the data.
  final DevBannerTone tone;

  @override
  Widget build(BuildContext context) {
    return Material(
      // The key carries the marker a CI guard searches the compiled production
      // bundle for: this literal exists in a dev build and in no other.
      key: const ValueKey<String>(devBundleMarker),
      color: tone.color,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: [
            Icon(tone.icon, size: 16, color: Colors.black87),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
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
