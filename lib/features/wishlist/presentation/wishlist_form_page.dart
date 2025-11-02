import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:wishtogether/common/widgets/primary_app_bar.dart';
import 'package:wishtogether/features/wishlist/data/wishlist_repository.dart';
import 'package:wishtogether/features/wishlist/domain/wishlist.dart';
import 'package:firebase_auth/firebase_auth.dart';

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
  final _wishlistRepository = WishlistRepository();
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

  Future<void> _saveWishlist() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        // This should not happen if the user is on this page,
        // but it's good practice to check.
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('You must be logged in.')),
          );
        }
        return;
      }

      try {
        if (_isEditing) {
          final updatedWishlist = widget.wishlist!.copyWith(
            name: _nameController.text,
          );
          await _wishlistRepository.update(
            updatedWishlist.id!,
            updatedWishlist,
          );
        } else {
          final newWishlist = Wishlist(
            name: _nameController.text,
            ownerId: user.uid,
          );
          await _wishlistRepository.add(newWishlist);
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Wishlist ${_isEditing ? 'updated' : 'created'}!'),
            ),
          );
          context.pop();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to save wishlist: $e')),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: PrimaryAppBar(
        title: _isEditing ? 'Edit Wishlist' : 'Create a new Wishlist',
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
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
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isLoading ? null : _saveWishlist,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(_isEditing ? 'Update Wishlist' : 'Save Wishlist'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
