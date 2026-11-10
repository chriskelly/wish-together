import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:wishtogether/common/widgets/button_loading_indicator.dart';
import 'package:wishtogether/common/widgets/confirmation_dialog.dart';
import 'package:wishtogether/common/widgets/primary_app_bar.dart';
import 'package:wishtogether/core/service_locator.dart';
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

  const ItemFormPage({super.key, required this.wishlistId, this.item});

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
  bool _isLoading = false;
  bool _isResetting = false;
  bool _leaving = false;
  late int _claimLimit;

  static const int _singleClaimLimit = 1;
  static const int _unlimitedClaimLimit = 0;
  static const int _maximumClaimLimit = 99;

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
  int get _minimumClaimLimit =>
      math.max(_singleClaimLimit, widget.item?.claimCount ?? 0);

  /// A finite limit is only legal when it can cover every existing claim.
  bool get _canSetFiniteLimit => _minimumClaimLimit <= _maximumClaimLimit;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.item?.name ?? '');
    _descriptionController = TextEditingController(
      text: widget.item?.description ?? '',
    );
    _linkController = TextEditingController(text: widget.item?.url ?? '');
    final storedLimit = widget.item?.claimLimit ?? _singleClaimLimit;
    _claimLimit = storedLimit == _unlimitedClaimLimit
        ? _unlimitedClaimLimit
        : math.max(storedLimit, _minimumClaimLimit);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _linkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      body: SingleChildScrollView(
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
              const SizedBox(height: 24),
              _submitButton(),
            ],
          ),
        ),
      ),
    );
  }

  PrimaryAppBar _buildAppBar() =>
      PrimaryAppBar(title: _isEditing ? 'Edit Item' : 'Add a new Item');

  TextFormField _nameTextFormField() => TextFormField(
    controller: _nameController,
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
    autofocus: true,
  );

  TextFormField _descriptionTextFormField() => TextFormField(
    controller: _descriptionController,
    decoration: const InputDecoration(
      labelText: 'Description (optional)',
      border: OutlineInputBorder(),
      hintText: 'e.g., The latest novel by my favorite author',
    ),
  );

  TextFormField _linkTextFormField() => TextFormField(
    controller: _linkController,
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
    });
  }

  void _increaseClaimLimit() {
    setState(() {
      _claimLimit = _isUnlimited ? _minimumClaimLimit : _claimLimit + 1;
    });
  }

  ElevatedButton _submitButton() => ElevatedButton(
    onPressed: _isLoading ? null : _saveItem,
    style: ElevatedButton.styleFrom(
      padding: const EdgeInsets.symmetric(vertical: 16),
    ),
    child: _isLoading
        ? const ButtonLoadingIndicator()
        : Text(_isEditing ? 'Update Item' : 'Save Item'),
  );

  Future<void> _saveItem() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() {
      _isLoading = true;
    });
    try {
      final name = _nameController.text.trim();
      final description = _descriptionController.text.trim();
      final url = _linkController.text.trim();

      if (_isEditing) {
        await _updateItemUseCase.execute(
          widget.wishlistId,
          widget.item!,
          name: name,
          description: description.isEmpty ? null : description,
          url: url.isEmpty ? null : url,
          claimLimit: _claimLimit,
        );
      } else {
        await _createItemUseCase.execute(
          widget.wishlistId,
          name,
          description: description.isEmpty ? null : description,
          url: url.isEmpty ? null : url,
          claimLimit: _claimLimit,
        );
      }
      if (mounted) {
        _showSnackbarAndExit('Item ${_isEditing ? 'updated' : 'added'}!');
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackbar(e);
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _resetClaims() async {
    final confirmed = await showConfirmationDialog(
      context: context,
      title: 'Reset claims?',
      content:
          '$_resetClaimsWarning This closes the form, so any unsaved changes '
          'will be lost.',
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
        _showSnackbarAndExit('Claims reset.');
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

  /// A save and a reset can both be in flight; only the first may leave the
  /// page, or the second pop would remove the details page underneath.
  void _showSnackbarAndExit(String message) {
    if (_leaving) {
      return;
    }
    _leaving = true;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
    context.pop();
  }

  void _showErrorSnackbar(Object e) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to save item: $e')));
}
