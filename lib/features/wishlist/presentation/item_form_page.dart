import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:wishtogether/common/widgets/button_loading_indicator.dart';
import 'package:wishtogether/common/widgets/confirmation_dialog.dart';
import 'package:wishtogether/common/widgets/primary_app_bar.dart';
import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/auth/domain/auth_session.dart';
import 'package:wishtogether/features/wishlist/application/claim_failure.dart';
import 'package:wishtogether/features/wishlist/application/create_item_use_case.dart';
import 'package:wishtogether/features/wishlist/application/reset_claims_use_case.dart';
import 'package:wishtogether/features/wishlist/application/update_item_use_case.dart';
import 'package:wishtogether/features/wishlist/domain/item.dart';
import 'package:wishtogether/features/wishlist/presentation/claim_failure_message.dart';

class ItemFormPage extends StatefulWidget {
  static const String createRouteName = 'createItem';
  static const String createRoute = 'add-item';
  static const String editRouteName = 'editItem';
  static const String editRoute = 'item/:itemId/edit';

  final String wishlistId;
  final Item? item;

  /// Present when the page is opened through the edit route. go_router calls
  /// it for a browser back, which does not go through [PopScope].
  final ItemFormLeaveGuard? leaveGuard;

  const ItemFormPage({
    super.key,
    required this.wishlistId,
    this.item,
    this.leaveGuard,
  });

  @override
  State<ItemFormPage> createState() => _ItemFormPageState();
}

class _ItemFormPageState extends State<ItemFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _linkController;
  final _createItemUseCase = getIt<CreateItemUseCase>();
  final _updateItemUseCase = getIt<UpdateItemUseCase>();
  final _resetClaimsUseCase = getIt<ResetClaimsUseCase>();
  final _session = getIt<AuthSession>();
  bool _isLoading = false;
  bool _isResetting = false;
  bool _leaving = false;
  late int _claimLimit;

  /// The claim count this page last saw, refreshed to zero when a reset
  /// succeeds. The route's item snapshot does not change on its own, and the
  /// stepper's minimum must follow the claims that actually exist.
  late int _claimCount;

  /// The values this form last wrote (or the values it opened with), so a
  /// successful write stops counting as an unsaved change.
  late _ItemDraft _savedDraft;

  /// A failed or unconfirmed write, shown above the form until the owner types
  /// again or retries.
  String? _saveError;

  /// Identifies the newest save attempt, so a write that resolves late cannot
  /// overwrite the result of a retry.
  int _saveAttempt = 0;
  Timer? _saveTimer;

  /// Set while the unsaved-changes dialog is open, so a second back press does
  /// not stack a second copy of the same question.
  bool _askingLeave = false;

  static const int _singleClaimLimit = 1;
  static const int _unlimitedClaimLimit = 0;
  static const int _maximumClaimLimit = 99;

  /// How long an edit save may stay unacknowledged before it is reported. A
  /// plain Firestore write queues offline and can stay pending, so without a
  /// bound the page would show a spinner with no way to retry.
  static const Duration _saveConfirmationTimeout = Duration(seconds: 10);

  static const String _unconfirmedSaveMessage =
      "Couldn't confirm the save. Check your connection and try again.";
  static const String _genericSaveMessage =
      "Couldn't save your changes. Please try again.";

  /// Shown beside the reset button and in its confirmation, so the action and
  /// the consequence it confirms cannot drift apart.
  static const String _resetClaimsWarning =
      "Resetting removes all claims on the item if there are any. "
      "This can't be undone.";

  bool get _isEditing => widget.item != null;

  bool get _isUnlimited => _claimLimit == _unlimitedClaimLimit;

  /// The fewest claims the limit may be lowered to.
  ///
  /// An item that already has claims cannot be set below them: the claims stay
  /// on the document, so a lower limit would be an impossible state.
  int get _minimumClaimLimit => math.max(_singleClaimLimit, _claimCount);

  /// The form's values as a save writes them: text trimmed, and the limit as
  /// the stepper holds it.
  _ItemDraft get _draft => (
    name: _nameController.text.trim(),
    description: _descriptionController.text.trim(),
    url: _linkController.text.trim(),
    claimLimit: _claimLimit,
  );

  /// The session the form opened under. A router redirect caused by that
  /// session ending or changing must win over an unsaved prompt: the form
  /// cannot save into a different session, and holding the redirect would
  /// strand the owner on a page they can no longer write to.
  late final String? _openedUid;

  bool get _sessionChanged => _session.currentUserId != _openedUid;

  /// Whether the form holds a change the stored item does not. Creating has no
  /// stored item to differ from, so it is never guarded.
  bool get _isDirty => _isEditing && _draft != _savedDraft;

  /// A finite limit is only legal when it can cover every existing claim.
  bool get _canSetFiniteLimit => _minimumClaimLimit <= _maximumClaimLimit;

  @override
  void initState() {
    super.initState();
    _openedUid = _session.currentUserId;
    _nameController = TextEditingController(text: widget.item?.name ?? '');
    _descriptionController = TextEditingController(
      text: widget.item?.description ?? '',
    );
    _linkController = TextEditingController(text: widget.item?.url ?? '');
    _claimCount = widget.item?.claimCount ?? 0;
    final storedLimit = widget.item?.claimLimit ?? _singleClaimLimit;
    _claimLimit = storedLimit == _unlimitedClaimLimit
        ? _unlimitedClaimLimit
        : math.max(storedLimit, _minimumClaimLimit);
    _savedDraft = _draft;
    widget.leaveGuard?.attach(_requestBrowserLeave);
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    widget.leaveGuard?.detach();
    _nameController.dispose();
    _descriptionController.dispose();
    _linkController.dispose();
    super.dispose();
  }

  /// A text change supersedes a failure about the previous values, so the
  /// banner goes away with the edit. The rebuild also re-evaluates
  /// [_isDirty] for the app bar's save action. Reached only from `onChanged`:
  /// moving the caret or focus is not an edit and keeps the banner and its
  /// retry.
  void _markEdited() {
    setState(() {
      _saveError = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<Object?>(
      canPop: !_isEditing || _sessionChanged || (!_isDirty && !_isLoading),
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          return;
        }
        _handleBlockedPop();
      },
      child: Scaffold(
        appBar: _buildAppBar(),
        body: Column(
          children: [
            if (_saveError case final message?) _saveErrorBanner(message),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16.0),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _nameTextFormField(),
                      const SizedBox(height: 16),
                      _descriptionTextFormField(),
                      const SizedBox(height: 16),
                      _linkTextFormField(),
                      const SizedBox(height: 24),
                      _claimLimitFields(),
                      if (_isEditing) ...[
                        const SizedBox(height: 24),
                        _resetClaimsSection(),
                      ],
                      if (!_isEditing) ...[
                        const SizedBox(height: 24),
                        _submitButton(),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  PrimaryAppBar _buildAppBar() => PrimaryAppBar(
    title: _isEditing ? 'Edit Item' : 'Add a new Item',
    actions: _isEditing ? [_saveAction()] : null,
  );

  /// The edit form's only save action: a check mark that is enabled exactly
  /// while there is something to save. Its disabled state is the visible
  /// "everything is saved" signal.
  Widget _saveAction() {
    if (_isLoading) {
      return const IconButton(
        onPressed: null,
        tooltip: 'Saving changes',
        icon: ButtonLoadingIndicator(),
      );
    }
    return IconButton(
      onPressed: _isDirty ? _saveItem : null,
      tooltip: _isDirty ? 'Save changes' : 'No unsaved changes',
      icon: const Icon(Icons.check),
    );
  }

  Widget _saveErrorBanner(String message) {
    final theme = Theme.of(context);
    final foreground = theme.colorScheme.onErrorContainer;
    return Semantics(
      liveRegion: true,
      child: Material(
        color: theme.colorScheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
          child: Row(
            children: [
              Icon(Icons.error_outline, color: foreground),
              const SizedBox(width: 12),
              Expanded(
                child: Text(message, style: TextStyle(color: foreground)),
              ),
              TextButton(onPressed: _saveItem, child: const Text('Retry')),
            ],
          ),
        ),
      ),
    );
  }

  TextFormField _nameTextFormField() => TextFormField(
    controller: _nameController,
    onChanged: (_) => _markEdited(),
    decoration: const InputDecoration(
      labelText: 'Item Name',
      border: OutlineInputBorder(),
      hintText: 'e.g., A new book',
    ),
    validator: (value) {
      if (value == null || value.trim().isEmpty) {
        return 'Please enter a name for the item.';
      }
      return null;
    },
    // Editing starts on a full form, so opening the keyboard here only hides
    // the parts the owner may have come to change. Creating starts empty and
    // the name is always the first thing to type.
    autofocus: !_isEditing,
  );

  TextFormField _descriptionTextFormField() => TextFormField(
    controller: _descriptionController,
    onChanged: (_) => _markEdited(),
    decoration: const InputDecoration(
      labelText: 'Description (optional)',
      border: OutlineInputBorder(),
      hintText: 'e.g., The latest novel by my favorite author',
    ),
  );

  TextFormField _linkTextFormField() => TextFormField(
    controller: _linkController,
    onChanged: (_) => _markEdited(),
    decoration: const InputDecoration(
      labelText: 'Link (optional)',
      border: OutlineInputBorder(),
      hintText: 'e.g., https://example.com/product/123',
    ),
    keyboardType: TextInputType.url,
    validator: _urlValidator,
  );

  String? _urlValidator(String? value) {
    if (value != null && value.trim().isNotEmpty) {
      final uri = Uri.tryParse(value.trim());
      if (uri == null || !uri.isAbsolute) {
        return 'Please enter a valid URL (are you missing "http://"?)';
      }
    }
    return null;
  }

  Widget _claimLimitFields() {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'How many people can claim this?',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          'Each person can claim one. Unlimited suits a gift where any number is welcome.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            IconButton(
              onPressed: _canDecreaseClaimLimit ? _decreaseClaimLimit : null,
              tooltip: 'Fewer people',
              icon: const Icon(Icons.remove),
            ),
            Semantics(
              container: true,
              excludeSemantics: true,
              label: _isUnlimited
                  ? 'No claim limit'
                  : 'Claim limit: $_claimLimit',
              child: SizedBox(
                width: 56,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    _isUnlimited ? '∞' : '$_claimLimit',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall,
                  ),
                ),
              ),
            ),
            IconButton(
              onPressed: _canIncreaseClaimLimit ? _increaseClaimLimit : null,
              tooltip: 'More people',
              icon: const Icon(Icons.add),
            ),
          ],
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Unlimited'),
          subtitle: const Text(
            'No limit on how many people can claim this item.',
          ),
          value: _isUnlimited,
          // With more claims than the stepper's ceiling, no finite limit can
          // legally cover them, so the item must stay unlimited.
          onChanged: !_isUnlimited || _canSetFiniteLimit
              ? (unlimited) {
                  setState(() {
                    _claimLimit = unlimited
                        ? _unlimitedClaimLimit
                        : _minimumClaimLimit;
                    _saveError = null;
                  });
                }
              : null,
        ),
      ],
    );
  }

  /// The owner's one deliberate way to clear every claim. It is always shown
  /// on an edit, even with no claims, so its presence never reveals whether
  /// anyone has claimed the item.
  Widget _resetClaimsSection() {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 1),
        const SizedBox(height: 24),
        Text('Claims', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          _resetClaimsWarning,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: (_isLoading || _isResetting) ? null : _resetClaims,
          style: OutlinedButton.styleFrom(
            foregroundColor: theme.colorScheme.error,
          ),
          child: _isResetting
              ? const ButtonLoadingIndicator()
              : const Text('Reset claims'),
        ),
      ],
    );
  }

  /// A limit above 99 can exist in a document written outside this form; it is
  /// kept and cannot be lowered, because the stepper only edits 1..99.
  bool get _canDecreaseClaimLimit =>
      !_isUnlimited &&
      _claimLimit <= _maximumClaimLimit &&
      _claimLimit > _minimumClaimLimit;

  bool get _canIncreaseClaimLimit =>
      _isUnlimited ? _canSetFiniteLimit : _claimLimit < _maximumClaimLimit;

  void _decreaseClaimLimit() {
    setState(() {
      _claimLimit -= 1;
      _saveError = null;
    });
  }

  void _increaseClaimLimit() {
    setState(() {
      _claimLimit = _isUnlimited ? _minimumClaimLimit : _claimLimit + 1;
      _saveError = null;
    });
  }

  ElevatedButton _submitButton() => ElevatedButton(
    onPressed: _isLoading ? null : _saveItem,
    style: ElevatedButton.styleFrom(
      padding: const EdgeInsets.symmetric(vertical: 16),
    ),
    child: _isLoading
        ? const ButtonLoadingIndicator()
        : const Text('Save Item'),
  );

  /// Writes [draft] through the use case that matches the page: an edit
  /// updates the stored item, a create adds a new one. An optional field left
  /// blank is stored as absent rather than empty.
  Future<void> _write(_ItemDraft draft) {
    final description = draft.description.isEmpty ? null : draft.description;
    final url = draft.url.isEmpty ? null : draft.url;
    if (_isEditing) {
      return _updateItemUseCase.execute(
        widget.wishlistId,
        widget.item!,
        name: draft.name,
        description: description,
        url: url,
        claimLimit: draft.claimLimit,
      );
    }
    return _createItemUseCase.execute(
      widget.wishlistId,
      draft.name,
      description: description,
      url: url,
      claimLimit: draft.claimLimit,
    );
  }

  /// Returns true only when the write succeeded and the page is leaving.
  Future<bool> _saveItem() async {
    if (_isLoading || !_formKey.currentState!.validate()) {
      return false;
    }
    final draft = _draft;
    final attempt = ++_saveAttempt;
    setState(() {
      _isLoading = true;
      _saveError = null;
    });

    var timedOut = false;
    // Creating is one shot: a create that is slow or queued must not invite a
    // second add, so it keeps its button disabled until the write resolves.
    final timer = _isEditing
        ? Timer(_saveConfirmationTimeout, () {
            timedOut = true;
            if (!mounted || attempt != _saveAttempt) {
              return;
            }
            setState(() {
              _isLoading = false;
              _saveError = _unconfirmedSaveMessage;
            });
          })
        : null;
    _saveTimer?.cancel();
    _saveTimer = timer;

    try {
      await _write(draft);
      if (!mounted || attempt != _saveAttempt) {
        return false;
      }
      _savedDraft = draft;
      // Only an edit stays open for newer input; creating keeps its explicit
      // one-shot action.
      final hasNewerEdits = _isEditing && _draft != draft;
      if (timedOut || hasNewerEdits) {
        // The write landed after the page reported it as unconfirmed, or the
        // owner kept typing while it was in flight. Record what was written,
        // but do not pull the page away from newer unsaved edits.
        setState(() {
          _isLoading = false;
          _saveError = null;
        });
        return false;
      }
      _showSnackbarAndExit('Item ${_isEditing ? 'updated' : 'added'}!');
      return true;
    } catch (error) {
      if (!mounted || attempt != _saveAttempt) {
        return false;
      }
      if (_isEditing) {
        setState(() {
          _isLoading = false;
          _saveError = _saveFailureMessage(error);
        });
      } else {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_saveFailureMessage(error))));
      }
      return false;
    } finally {
      timer?.cancel();
      if (identical(_saveTimer, timer)) {
        _saveTimer = null;
      }
    }
  }

  /// Back and the system gesture land here while the form holds a change or a
  /// save is in flight.
  Future<void> _handleBlockedPop() async {
    if (_askingLeave) {
      return;
    }
    if (_isLoading) {
      _showSavingMessage();
      return;
    }
    if (!_isDirty) {
      return;
    }

    final choice = await _askLeave();
    if (!mounted) {
      return;
    }

    switch (choice) {
      case _LeaveChoice.discard:
        // The pop itself is checked by the route's onExit as well; detach so
        // the discarded form cannot ask a second time on the way out.
        widget.leaveGuard?.detach();
        context.pop();
      case _LeaveChoice.save:
        await _saveItem();
      case _LeaveChoice.keepEditing || null:
        return;
    }
  }

  /// A browser back can reach the form as a Navigator pop and then as a route
  /// replacement. The replacement goes through go_router's `onExit`, not
  /// [PopScope], so this guard asks there; the dialog guard stops the two
  /// paths from stacking a second prompt. Returning false keeps the form in
  /// place, and the browser's own navigation applies when it returns true.
  Future<bool> _requestBrowserLeave() async {
    if (_leaving || _sessionChanged) {
      return true;
    }
    if (_askingLeave) {
      return false;
    }
    if (_isLoading) {
      _showSavingMessage();
      return false;
    }
    if (!_isDirty) {
      return true;
    }
    final choice = await _askLeave();
    return switch (choice) {
      _LeaveChoice.discard => true,
      _LeaveChoice.save => await _saveItem(),
      _LeaveChoice.keepEditing || null => false,
    };
  }

  Future<_LeaveChoice?> _askLeave() async {
    _askingLeave = true;
    try {
      return await showDialog<_LeaveChoice>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Save your changes?'),
          content: const Text('You have unsaved changes to this item.'),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(_LeaveChoice.keepEditing),
              child: const Text('Keep editing'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(_LeaveChoice.discard),
              child: Text(
                'Discard',
                style: TextStyle(
                  color: Theme.of(dialogContext).colorScheme.error,
                ),
              ),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(_LeaveChoice.save),
              child: const Text('Save'),
            ),
          ],
        ),
      );
    } finally {
      _askingLeave = false;
    }
  }

  void _showSavingMessage() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Saving your changes…')));
  }

  /// The reset no longer closes the form, so a pending edit survives it and the
  /// stepper's minimum follows the claims that remain (none).
  Future<void> _resetClaims() async {
    final confirmed = await showConfirmationDialog(
      context: context,
      title: 'Reset claims?',
      content: _resetClaimsWarning,
      confirmText: 'Reset claims',
    );
    if (confirmed != true || !mounted) {
      return;
    }

    setState(() {
      _isResetting = true;
    });
    try {
      await _resetClaimsUseCase.execute(widget.wishlistId, widget.item!.id!);
      if (mounted) {
        setState(() {
          _claimCount = 0;
        });
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Claims reset.')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_resetFailureMessage(error))));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isResetting = false;
        });
      }
    }
  }

  String _resetFailureMessage(Object error) {
    final reason = error is ClaimFailure
        ? error.reason
        : ClaimFailureReason.unknown;
    return switch (reason) {
      ClaimFailureReason.signedOut => 'Please sign in again to reset claims.',
      ClaimFailureReason.offline => offlineFailureMessage,
      ClaimFailureReason.accessDenied =>
        "You don't have permission to reset this item's claims.",
      ClaimFailureReason.itemMissing => itemMissingFailureMessage,
      ClaimFailureReason.fullyClaimed ||
      ClaimFailureReason.unknown => "Couldn't reset claims. Please try again.",
    };
  }

  String _saveFailureMessage(Object error) {
    final reason = ClaimFailure.from(error).reason;
    return switch (reason) {
      ClaimFailureReason.offline => offlineFailureMessage,
      ClaimFailureReason.accessDenied =>
        "You don't have permission to save this item.",
      ClaimFailureReason.itemMissing => itemMissingFailureMessage,
      ClaimFailureReason.signedOut => 'Please sign in again to save this item.',
      ClaimFailureReason.fullyClaimed ||
      ClaimFailureReason.unknown => _genericSaveMessage,
    };
  }

  /// A save can be in flight when another exit is attempted; only the first
  /// completion may leave the page, or the second pop would remove the details
  /// page underneath.
  void _showSnackbarAndExit(String message) {
    if (_leaving) {
      return;
    }
    _leaving = true;
    // go_router completes a page-based pop in a deferred onExit. Clear the
    // spinner first so the app bar never shows a save still running while the
    // page is on its way out.
    setState(() {
      _isLoading = false;
    });
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
    context.pop();
  }
}

enum _LeaveChoice { keepEditing, discard, save }

/// Arguments for the edit route: the item to edit plus the guard that lets the
/// browser's back button reach the form's unsaved-changes prompt.
class EditItemRouteArgs {
  EditItemRouteArgs(this.item);

  final Item item;
  final ItemFormLeaveGuard leaveGuard = ItemFormLeaveGuard();
}

/// Bridges go_router's `onExit` to the form. The page attaches while it is
/// mounted; an unattached guard allows the route to exit.
class ItemFormLeaveGuard {
  Future<bool> Function()? _requestLeave;

  void attach(Future<bool> Function() requestLeave) {
    _requestLeave = requestLeave;
  }

  void detach() {
    _requestLeave = null;
  }

  Future<bool> requestLeave() async => await _requestLeave?.call() ?? true;
}

/// The item fields the form edits, compared as one value so "has anything
/// changed" is a single comparison.
typedef _ItemDraft = ({
  String name,
  String description,
  String url,
  int claimLimit,
});
