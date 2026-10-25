import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/auth/application/load_user_profile_use_case.dart';
import 'package:wishtogether/features/auth/application/save_user_profile_use_case.dart';
import 'package:wishtogether/features/auth/presentation/delete_account_section.dart';
import 'package:wishtogether/features/auth/presentation/home_page.dart';

import '../domain/user.dart';

/// Where the profile page is in its one read of the signed-in user.
///
/// A read that throws and a read that finds no document both end in [failed]:
/// waiting cannot clear either, and a permanent spinner would hide the Retry
/// that can.
enum ProfileLoadState { loading, loaded, failed }

/// The AppBar title for each load state.
///
/// Only a [ProfileLoadState.loaded] profile knows whether this is onboarding, so
/// the other two stay neutral rather than telling an existing user whose read
/// failed to create a profile.
String profilePageTitle({
  required ProfileLoadState loadState,
  required bool isNewUser,
}) => switch (loadState) {
  ProfileLoadState.loading || ProfileLoadState.failed => 'Profile',
  ProfileLoadState.loaded => isNewUser ? 'Create Your Profile' : 'Edit Profile',
};

/// Whether the profile page offers a way out that does not save.
///
/// An empty display name *is* the onboarding state — the router refuses to let
/// such a user past `/profile` — so an arrow for them would only bounce
/// straight back.
///
/// Only a loaded profile is trusted to answer: a still-loading or failed read
/// knows no name at all, and an arrow there would let a new user past
/// onboarding on the strength of a request that never succeeded. That is why
/// the state is an explicit input rather than a pair of booleans the page
/// derives from whatever it happens to hold.
bool shouldShowProfileBackButton({
  required ProfileLoadState loadState,
  required bool isNewUser,
}) => loadState == ProfileLoadState.loaded && !isNewUser;

/// Where the profile page's exits send the user.
///
/// Returns [redirectTo], trimmed, unless it is absent, blank, or points back
/// at `/profile`, in which case the user goes home. Those cases are picked
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
  ProfileLoadState _loadState = ProfileLoadState.loading;

  // Check if the user is new based on whether a display name is set.
  bool get _isNewUser =>
      _currentUser?.displayName == null || _currentUser!.displayName!.isEmpty;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  /// Reads the signed-in user's document, or reads it again after a failure.
  ///
  /// A throw (offline, permission, transient Firestore failure) and a missing
  /// document both land in [ProfileLoadState.failed] so the page can offer
  /// Retry. The router creates the document before routing here, so a missing
  /// one means something is wrong, not that the user is mid-signup.
  Future<void> _loadUserData() async {
    try {
      final user = await _loadUserProfileUseCase.execute();
      if (!mounted) return;
      if (user == null) {
        setState(() => _loadState = ProfileLoadState.failed);
        return;
      }
      setState(() {
        _currentUser = user;
        _displayNameController.text = user.displayName ?? '';
        _loadState = ProfileLoadState.loaded;
      });
    } catch (error) {
      debugPrint('Profile load failed: $error');
      if (!mounted) return;
      setState(() => _loadState = ProfileLoadState.failed);
    }
  }

  /// Retry from the error state: back to the spinner, then one fresh read.
  Future<void> _retryLoad() async {
    setState(() => _loadState = ProfileLoadState.loading);
    await _loadUserData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _profileAppBar(context),
      body: switch (_loadState) {
        ProfileLoadState.loading => const Center(
          child: CircularProgressIndicator(),
        ),
        ProfileLoadState.failed => _loadErrorPanel(context),
        ProfileLoadState.loaded => SingleChildScrollView(
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
      },
    );
  }

  AppBar _profileAppBar(BuildContext context) => AppBar(
    // Nothing pushes `/profile` today, but an automatic leading arrow would
    // appear if anything ever did — including for a new user who must not be
    // able to dismiss onboarding.
    automaticallyImplyLeading: false,
    leading: _backButton(context),
    title: Text(
      profilePageTitle(loadState: _loadState, isNewUser: _isNewUser),
      style: Theme.of(context).textTheme.headlineSmall,
    ),
  );

  /// The non-saving exit; only built for a loaded, existing user. It shares
  /// [profileExitTarget] with Save, so the two exits cannot disagree.
  Widget? _backButton(BuildContext context) =>
      shouldShowProfileBackButton(loadState: _loadState, isNewUser: _isNewUser)
      ? BackButton(
          onPressed: () => context.go(profileExitTarget(widget.redirectTo)),
        )
      : null;

  /// The failed state: no form, no Save, no delete-account section and no back
  /// arrow, so the only way off this page is a read that succeeds.
  ///
  /// Shaped like the app-update screen: one icon, one headline, one line of
  /// guidance, one action, all inside a scroll view so a small screen or a
  /// large text scale cannot clip the Retry.
  Widget _loadErrorPanel(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_off_rounded,
                size: 56,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text(
                'Could not load your profile.',
                style: theme.textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              Text(
                'Check your connection and try again.',
                style: theme.textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _retryLoad,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      ),
    );
  }

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
