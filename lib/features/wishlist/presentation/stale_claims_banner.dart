import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wishtogether/common/widgets/button_loading_indicator.dart';
import 'package:wishtogether/common/widgets/confirmation_dialog.dart';
import 'package:wishtogether/core/logging/diagnostics.dart';
import 'package:wishtogether/features/wishlist/application/claim_failure.dart';
import 'package:wishtogether/features/wishlist/domain/stale_claims.dart';
import 'package:wishtogether/features/wishlist/presentation/claim_failure_message.dart';
import 'package:wishtogether/features/wishlist/presentation/item_action_feedback.dart';
import 'package:wishtogether/features/wishlist/presentation/providers/wishlist_details_providers.dart';

/// The owner-only prompt to clear claims left over from a previous season.
///
/// It names no item, no claimant and no count: it is the one aggregate
/// exception to the owner's spoiler-free view. Its action goes through the
/// page's [ItemActions] so a claim, unclaim or delete cannot run beside it.
class StaleClaimsBanner extends ConsumerWidget {
  const StaleClaimsBanner({
    super.key,
    required this.wishlistId,
    required this.plan,
  });

  final String wishlistId;
  final StaleClaimsPlan plan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (isBusy, isClearing) = ref.watch(
      wishlistItemActionsProvider(wishlistId)
          .select((state) => (state.isBusy, state.isBulk)),
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.history, color: scheme.onSurfaceVariant),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'You have claim(s) older than $staleClaimAgeLabel.',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: isBusy ? null : () => _clear(context, ref),
              child: isClearing
                  ? const ButtonLoadingIndicator()
                  : const Text('Clear old claims'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _clear(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showConfirmationDialog(
      context: context,
      title: 'Clear old claims?',
      content:
          'This removes any item claims older than $staleClaimAgeLabel. '
          'Claims made in the last $staleClaimAgeLabel are kept. '
          "This can't be undone.",
      confirmText: 'Clear old claims',
    );
    if (confirmed != true || !context.mounted) {
      return;
    }

    await runItemAction(
      context,
      () => ref
          .read(wishlistItemActionsProvider(wishlistId).notifier)
          .clearStaleClaims(plan),
      success: 'Old claims cleared.',
      failure: clearStaleClaimsFailureMessage,
      messenger: messenger,
      onError: (error, stackTrace) {
        if (error is! ClaimFailure) {
          appLogOrNull?.error(error, stackTrace);
        }
      },
    );
  }
}
