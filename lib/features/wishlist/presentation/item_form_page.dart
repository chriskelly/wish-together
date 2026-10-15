import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:wishtogether/common/widgets/button_loading_indicator.dart';
import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/wishlist/application/create_item_use_case.dart';
import 'package:wishtogether/features/wishlist/application/update_item_use_case.dart';
import 'package:wishtogether/features/wishlist/domain/item.dart';

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
  bool _isLoading = false;

  bool get _isEditing => widget.item != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.item?.name ?? '');
    _descriptionController = TextEditingController(
      text: widget.item?.description ?? '',
    );
    _linkController = TextEditingController(text: widget.item?.url ?? '');
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
      body: Padding(
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
              _submitButton(),
            ],
          ),
        ),
      ),
    );
  }

  AppBar _buildAppBar() => AppBar(
    title: Text(
      _isEditing ? 'Edit Item' : 'Add a new Item',
      style: Theme.of(context).textTheme.headlineSmall,
    ),
  );

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
        );
      } else {
        await _createItemUseCase.execute(
          widget.wishlistId,
          name,
          description: description.isEmpty ? null : description,
          url: url.isEmpty ? null : url,
        );
      }
      if (mounted) {
        _showSnackbarAndExit();
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

  void _showSnackbarAndExit() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Item ${_isEditing ? 'updated' : 'added'}!')),
    );
    context.pop();
  }

  void _showErrorSnackbar(Object e) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Failed to save item: $e')));
}
