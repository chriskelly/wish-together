import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:go_router/go_router.dart';
import 'package:myapp/features/auth/data/user_repository.dart';
import '../domain/user.dart';

class ProfilePage extends StatefulWidget {
  final String? redirectTo;
  const ProfilePage({super.key, this.redirectTo});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _formKey = GlobalKey<FormState>();
  final _displayNameController = TextEditingController();
  final _userRepository = UserRepository();
  final _auth = auth.FirebaseAuth.instance;

  User? _currentUser;
  bool _isLoading = true;
  bool get _isNewUser =>
      _currentUser?.displayName == null || _currentUser!.displayName!.isEmpty;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    final authUser = _auth.currentUser;
    if (authUser != null) {
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

  Future<void> _saveProfile() async {
    if (_formKey.currentState!.validate()) {
      final authUser = _auth.currentUser;
      if (authUser == null) return;

      final displayName = _displayNameController.text.trim();

      try {
        if (_isNewUser) {
          await _userRepository.add(User(
            id: authUser.uid, 
            displayName: displayName, 
            phoneNumber: authUser.phoneNumber
            ));
        } else {
          await _userRepository.updateData(
            authUser.uid,
            {'displayName': displayName},
          );
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Profile saved successfully!')),
          );
          // Redirect to the originally intended page, or home otherwise.
          context.go(widget.redirectTo ?? '/');
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
        title: Text(_isNewUser ? 'Create Your Profile' : 'Edit Profile', 
        style: Theme.of(context).textTheme.headlineSmall),
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
