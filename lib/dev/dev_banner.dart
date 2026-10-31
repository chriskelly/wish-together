import 'package:flutter/material.dart';
import 'package:wishtogether/dev/dev_config.dart';

/// The strip a development session shows above every page.
///
/// It exists so a screenshot cannot be mistaken for the real app: it names the
/// scenario the data came from, which also makes a silent fallback to the
/// `default` scenario visible at a glance.
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
