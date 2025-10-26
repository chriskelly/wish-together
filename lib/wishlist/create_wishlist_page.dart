import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:myapp/models/wishlist.dart';
import 'package:myapp/services/firestore_service.dart';
import 'package:firebase_auth/firebase_auth.dart';

class CreateWishlistPage extends StatefulWidget {
  const CreateWishlistPage({super.key});

  @override
  State<CreateWishlistPage> createState() => _CreateWishlistPageState();
}

class _CreateWishlistPageState extends State<CreateWishlistPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _firestoreService = FirestoreService();
  bool _isLoading = false;

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
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('You must be logged in to create a wishlist.')),
          );
          setState(() {
            _isLoading = false;
          });
        }
        return;
      }

      final newWishlist = Wishlist(
        id: '', // Firestore will generate the ID
        name: _nameController.text,
        ownerId: user.uid,
      );

      try {
        await _firestoreService.addWishlist(newWishlist);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Wishlist created!')),
          );
          context.pop();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to create wishlist: $e')),
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
      appBar: AppBar(
        title: const Text('Create a new Wishlist'),
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
                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Save Wishlist'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
