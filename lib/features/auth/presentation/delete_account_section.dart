import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:wishtogether/common/widgets/confirmation_dialog.dart';
import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/auth/application/delete_account_use_case.dart';
import 'package:wishtogether/features/auth/data/auth_service.dart';
import 'package:wishtogether/features/auth/data/delete_account_error.dart';
import 'package:wishtogether/features/auth/data/phone_auth_error.dart';
import 'package:wishtogether/features/auth/data/phone_verification.dart';
import 'package:wishtogether/features/auth/data/reauth_provider.dart';
import 'package:wishtogether/features/auth/presentation/login_page.dart';

/// The "delete account" danger zone on the profile page.
///
/// Confirms the intent, re-authenticates for whichever provider this session
/// used (Firebase requires a recent login before deleting an account), then
/// runs [DeleteAccountUseCase] and returns to the login page.
class DeleteAccountSection extends StatefulWidget {
  const DeleteAccountSection({super.key});

  @override
  State<DeleteAccountSection> createState() => _DeleteAccountSectionState();
}

class _DeleteAccountSectionState extends State<DeleteAccountSection> {
  static const String _unsupportedProviderMessage =
      'This sign-in method cannot be confirmed in the app. Please contact us '
      'to delete your account.';

  final AuthService _authService = getIt<AuthService>();
  final DeleteAccountUseCase _deleteAccountUseCase =
      getIt<DeleteAccountUseCase>();

  bool _isDeleting = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(height: 48),
        Text('Delete account', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          'Deleting your account removes your profile, your wishlists and their '
          'items, and your group memberships. This cannot be undone.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _isDeleting ? null : _confirmAndDelete,
          icon: const Icon(Icons.delete_forever_outlined),
          label: const Text('Delete account'),
          style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
        ),
        if (_isDeleting) ...const [
          SizedBox(height: 16),
          Center(child: CircularProgressIndicator()),
        ],
      ],
    );
  }

  Future<void> _confirmAndDelete() async {
    final bool? confirmed = await showConfirmationDialog(
      context: context,
      title: 'Delete your account?',
      content:
          'This permanently deletes your account: your profile, your wishlists '
          'and their items, and your group memberships. Groups you own pass to '
          'another member. Items you claimed in other people\'s lists stay '
          'marked as claimed, so a gift is not bought twice. This cannot be '
          'undone.',
      confirmText: 'Delete account',
    );
    if (confirmed != true || !mounted) {
      return;
    }

    // Deleting the account also drops the session, which disposes this page.
    // Hold on to what the closing messages need, and read the linked providers
    // while the user still exists.
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context, rootNavigator: true);
    final hasAppleLink = _authService.providerIds.contains('apple.com');

    setState(() => _isDeleting = true);
    try {
      final provider = await _resolveReauthProvider();
      if (!mounted) return;
      if (provider == ReauthProvider.unknown) {
        _showMessage(_unsupportedProviderMessage);
        return;
      }

      final confirmedIdentity = await _reauthenticateWith(provider);
      if (!confirmedIdentity || !mounted) {
        return;
      }

      await _deleteAccountUseCase.execute();

      if (hasAppleLink) {
        await _explainAppleRevocation(navigator);
      }

      messenger.showSnackBar(
        const SnackBar(content: Text('Your account has been deleted.')),
      );
      if (mounted) {
        context.go(LoginPage.route);
      }
    } catch (error) {
      final message = deleteAccountErrorMessage(error);
      if (message != null) {
        _showMessage(message);
      }
    } finally {
      if (mounted) {
        setState(() => _isDeleting = false);
      }
    }
  }

  /// TN3194's manual fallback for Sign in with Apple.
  ///
  /// Programmatic revocation needs the Apple refresh token (or authorization
  /// code) and a server-held client secret, neither of which the app keeps.
  /// Apple's documented fallback is to delete the account and then point the
  /// user at the "Stop Using Apple ID" control, so this runs after the cascade
  /// and the auth deletion.
  Future<void> _explainAppleRevocation(NavigatorState navigator) {
    return showDialog<void>(
      context: navigator.context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Remove WishTogether from Apple'),
        content: const Text(
          'Your WishTogether account is deleted. You also signed in with Apple, '
          'so remove the app from your Apple ID:\n\n'
          'Settings → your name → Sign in with Apple → WishTogether → '
          'Stop Using Apple ID.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  /// The provider that issued this session's token, or the account's linked
  /// providers when the token does not name one we can confirm.
  Future<ReauthProvider> _resolveReauthProvider() async {
    final signInProvider = await _authService.signInProvider();
    return preferredReauthProvider(
      signInProvider: signInProvider,
      providerIds: _authService.providerIds,
      isWeb: _authService.isWeb,
    );
  }

  /// Confirms the user's identity. Returns `false` when the user backed out.
  Future<bool> _reauthenticateWith(ReauthProvider provider) async {
    switch (provider) {
      case ReauthProvider.google:
        await _authService.reauthenticateWithGoogle();
        return true;
      case ReauthProvider.apple:
        await _authService.reauthenticateWithApple();
        return true;
      case ReauthProvider.phone:
        return _reauthenticateWithPhone();
      case ReauthProvider.unknown:
        // Handled by the caller, which never gets here.
        return false;
    }
  }

  Future<bool> _reauthenticateWithPhone() async {
    final phoneNumber = _authService.currentUserPhoneNumber;
    if (phoneNumber == null) {
      _showMessage('We could not find a phone number for this account.');
      return false;
    }

    final PhoneVerification verification;
    try {
      verification = await _authService.startPhoneVerification(phoneNumber);
    } on FirebaseAuthException catch (error) {
      _showMessage(phoneAuthErrorMessage(error));
      return false;
    }

    switch (verification) {
      case PhoneVerificationAutoVerified(:final credential):
        // The platform proved possession of the phone itself (Android instant
        // verification), so there is no code to type in.
        await _authService.reauthenticateWithPhoneCredential(credential);
        return true;
      case PhoneVerificationCodeSent(:final verificationId):
        final smsCode = await _promptForSmsCode();
        if (smsCode == null) {
          return false;
        }
        await _authService.reauthenticateWithPhoneCode(
          verificationId: verificationId,
          smsCode: smsCode,
        );
        return true;
    }
  }

  /// Asks for the SMS code. Returns `null` when the user cancels.
  Future<String?> _promptForSmsCode() async {
    final controller = TextEditingController();
    try {
      final code = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Confirm your number'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'We sent a code to your phone. Enter it to confirm it is you.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'SMS code'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogContext).pop(controller.text.trim()),
              child: const Text('Confirm'),
            ),
          ],
        ),
      );
      if (code == null || code.isEmpty) {
        return null;
      }
      return code;
    } finally {
      controller.dispose();
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}
