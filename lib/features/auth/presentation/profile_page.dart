import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/auth/data/user_repository.dart';
import 'package:wishtogether/features/auth/presentation/home_page.dart';
import '../domain/user.dart';

class ProfilePage extends StatefulWidget {
  static const String route = '/profile';
  final String? redirectTo;
  const ProfilePage({super.key, this.redirectTo});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _formKey = GlobalKey<FormState>();
  final _displayNameController = TextEditingController();
  final _userRepository = getIt<UserRepository>();

  User? _currentUser;
  bool _isLoading = true;

  // Check if the user is new based on whether a display name is set.
  bool get _isNewUser =>
      _currentUser?.displayName == null || _currentUser!.displayName!.isEmpty;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  // Load user data; the router ensures the user document exists.
  Future<void> _loadUserData() async {
    final authUser = Provider.of<auth.User?>(context, listen: false);
    if (authUser != null) {
      // The get call is now safe because the router's redirect logic
      // using getOrCreateUser guarantees the document exists.
      final user = await _userRepository.get(authUser.uid);
      if (mounted) {
        setState(() {
          _currentUser = user;
          _displayNameController.text = user.displayName ?? '';
          _isLoading = false;
        });
      }
    }
  }

  // Save the user's profile.
  Future<void> _saveProfile() async {
    if (_formKey.currentState!.validate()) {
      final authUser = Provider.of<auth.User?>(context, listen: false);
      if (authUser == null) return;

      final displayName = _displayNameController.text.trim();

      try {
        // The user document is guaranteed to exist, so we always update.
        await _userRepository.updateData(authUser.uid, {
          'displayName': displayName,
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Profile saved successfully!')),
          );
          // Redirect to the originally intended page, or home otherwise.
          context.go(widget.redirectTo ?? HomePage.route);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Error saving profile: $e')));
        }
      }
    }
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isNewUser ? 'Create Your Profile' : 'Edit Profile',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _isNewUser
                              ? 'Welcome! Please enter your name to continue.'
                              : 'Update your profile information.',
                          style: Theme.of(context).textTheme.headlineSmall,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        TextFormField(
                          controller: _displayNameController,
                          decoration: const InputDecoration(
                            labelText: 'Name',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Please enter your name';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 30),
                        ElevatedButton(
                          onPressed: _saveProfile,
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 40,
                              vertical: 15,
                            ),
                            textStyle: Theme.of(context).textTheme.titleMedium,
                          ),
                          child: const Text('Save and Continue'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
