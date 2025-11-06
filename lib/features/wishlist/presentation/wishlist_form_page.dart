import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:wishtogether/common/widgets/primary_app_bar.dart';
import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/auth/data/auth_service.dart';
import 'package:wishtogether/features/wishlist/data/wishlist_repository.dart';
import 'package:wishtogether/features/wishlist/domain/wishlist.dart';

class WishlistFormPage extends StatefulWidget {
  static const String createRoute = '/create-wishlist';
  static const String editRoute = 'edit';
  static const String editRouteName = 'editWishlist';

  final Wishlist? wishlist;

  const WishlistFormPage({super.key, this.wishlist});

  @override
  State<WishlistFormPage> createState() => _WishlistFormPageState();
}

class _WishlistFormPageState extends State<WishlistFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  final _wishlistRepository = getIt<WishlistRepository>();
  final _authService = getIt<AuthService>();
  bool _isLoading = false;

  bool get _isEditing => widget.wishlist != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.wishlist?.name ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
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
              const SizedBox(height: 24),
              _submitButton(),
            ],
          ),
        ),
      ),
    );
  }

  PrimaryAppBar _buildAppBar() => PrimaryAppBar(
    title: _isEditing ? 'Edit Wishlist' : 'Create a new Wishlist',
  );

  TextFormField _nameTextFormField() => TextFormField(
    controller: _nameController,
    decoration: const InputDecoration(
      labelText: 'Wishlist Name',
      border: OutlineInputBorder(),
      hintText: 'e.g., My Birthday 2024',
    ),
    validator: (value) {
      if (value == null || value.trim().isEmpty) {
        return 'Please enter a name for your wishlist.';
      }
      return null;
    },
    autofocus: true,
  );

  ElevatedButton _submitButton() => ElevatedButton(
    onPressed: _isLoading ? null : _saveWishlist,
    style: ElevatedButton.styleFrom(
      padding: const EdgeInsets.symmetric(vertical: 16),
    ),
    child: _isLoading
        ? _loadingIndicator()
        : Text(_isEditing ? 'Update Wishlist' : 'Save Wishlist'),
  );

  Widget _loadingIndicator() => const SizedBox(
    height: 20,
    width: 20,
    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
  );

  Future<void> _saveWishlist() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final user = _authService.currentUser!;
    setState(() {
      _isLoading = true;
    });
    try {
      if (_isEditing) {
        await _updateWishlist();
      } else {
        await _addWishlist(user);
      }
      if (mounted) {
        _showSnackbarAndExit();
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackbar('Failed to save wishlist: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _updateWishlist() async {
    final updatedWishlist = widget.wishlist!.copyWith(
      name: _nameController.text.trim(),
    );
    await _wishlistRepository.update(updatedWishlist.id!, updatedWishlist);
  }

  Future<void> _addWishlist(auth.User user) async {
    final newWishlist = Wishlist(
      name: _nameController.text.trim(),
      ownerId: user.uid,
    );
    await _wishlistRepository.add(newWishlist);
  }

  void _showSnackbarAndExit() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Wishlist ${_isEditing ? 'updated' : 'created'}!'),
      ),
    );
    context.pop();
  }

  void _showErrorSnackbar(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));
}
