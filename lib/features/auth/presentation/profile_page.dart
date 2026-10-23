import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/auth/application/load_user_profile_use_case.dart';
import 'package:wishtogether/features/auth/application/save_user_profile_use_case.dart';
import 'package:wishtogether/features/auth/presentation/delete_account_section.dart';
import 'package:wishtogether/features/auth/presentation/home_page.dart';

import '../domain/user.dart';

/// Whether the profile page offers a way out that does not save.
///
/// An empty display name *is* the onboarding state — the router refuses to let
/// such a user past `/profile` — so an arrow for them would only bounce
/// straight back.
///
/// [isLoading] is checked as well even though a still-loading profile already
/// reads as "new" (no user document yet): the gate should not depend on that
/// coincidence, so the load state stays an explicit input.
bool shouldShowProfileBackButton({
  required bool isLoading,
  required bool isNewUser,
}) => !isLoading && !isNewUser;

/// Where the profile page's exits send the user.
///
/// Returns [redirectTo] unless it is absent, blank, or points back at
/// `/profile`, in which case the user goes home. Those cases are picked
/// because a `redirect_to` is untrusted query-string input and each one would
/// otherwise make the exit a no-op or an unmatched location: `context.go('')`
/// renders go_router's error page, and `context.go('/profile')` keeps the user
/// on the page they are trying to leave.
///
/// Both the back arrow and Save use this, so the two exits cannot disagree.
String profileExitTarget(String? redirectTo) {
  final target = redirectTo?.trim() ?? '';
  return target.isEmpty || _isProfilePageLocation(target)
      ? HomePage.route
      : target;
}

/// True for `/profile` and its canonical spellings (`/profile/`,
/// `/profile?redirect_to=…`), which all resolve to the same page.
bool _isProfilePageLocation(String location) {
  final path = Uri.tryParse(location)?.path ?? location;
  final withoutTrailingSlash = path.length > 1 && path.endsWith('/')
      ? path.substring(0, path.length - 1)
      : path;
  return withoutTrailingSlash == ProfilePage.route;
}

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
  final _loadUserProfileUseCase = getIt<LoadUserProfileUseCase>();
  final _saveUserProfileUseCase = getIt<SaveUserProfileUseCase>();

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
    final user = await _loadUserProfileUseCase.execute();
    if (mounted && user != null) {
      setState(() {
        _currentUser = user;
        _displayNameController.text = user.displayName ?? '';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _profileAppBar(context),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: _profilePageForm(context),
                  ),
                ),
              ),
            ),
    );
  }

  AppBar _profileAppBar(BuildContext context) => AppBar(
    // Nothing pushes `/profile` today, but an automatic leading arrow would
    // appear if anything ever did — including for a new user who must not be
    // able to dismiss onboarding.
    automaticallyImplyLeading: false,
    leading: _backButton(context),
    title: Text(
      _isNewUser ? 'Create Your Profile' : 'Edit Profile',
      style: Theme.of(context).textTheme.headlineSmall,
    ),
  );

  /// The non-saving exit; only built for a loaded, existing user. It shares
  /// [profileExitTarget] with Save, so the two exits cannot disagree.
  Widget? _backButton(BuildContext context) =>
      shouldShowProfileBackButton(isLoading: _isLoading, isNewUser: _isNewUser)
      ? BackButton(
          onPressed: () => context.go(profileExitTarget(widget.redirectTo)),
        )
      : null;

  Form _profilePageForm(BuildContext context) => Form(
    key: _formKey,
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _headerText(context),
        const SizedBox(height: 20),
        _nameTextFormField(),
        const SizedBox(height: 30),
        _saveButton(context),
        // The account exists as soon as the user signs in — even before they
        // have picked a display name — so deletion must always be reachable.
        const DeleteAccountSection(),
      ],
    ),
  );

  Text _headerText(BuildContext context) => Text(
    _isNewUser
        ? 'Welcome! Please enter your name to continue.'
        : 'Update your profile information.',
    style: Theme.of(context).textTheme.headlineSmall,
    textAlign: TextAlign.center,
  );

  TextFormField _nameTextFormField() => TextFormField(
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
  );

  ElevatedButton _saveButton(BuildContext context) => ElevatedButton(
    onPressed: _saveProfile,
    style: ElevatedButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
      textStyle: Theme.of(context).textTheme.titleMedium,
    ),
    child: const Text('Save and Continue'),
  );

  Future<void> _saveProfile() async {
    if (_formKey.currentState!.validate()) {
      final displayName = _displayNameController.text.trim();
      try {
        await _saveUserProfileUseCase.execute(displayName);
        _showConfirmationSnackbarAndExit();
      } catch (e) {
        _showErrorSnackBar(e);
      }
    }
  }

  void _showConfirmationSnackbarAndExit() {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile saved successfully!')),
      );
      context.go(profileExitTarget(widget.redirectTo));
    }
  }

  void _showErrorSnackBar(Object e) {
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Error saving profile: $e')));
    }
  }

  @override
  void dispose() {
    _displayNameController.dispose();
    super.dispose();
  }
}
