import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:go_router/go_router.dart';

import 'dart:developer' as developer;

import 'package:url_launcher/url_launcher.dart';
import 'package:wishtogether/core/router.dart';
import 'package:wishtogether/core/service_locator.dart';
import 'package:wishtogether/features/auth/data/auth_service.dart';
import 'package:wishtogether/features/auth/data/google_sign_in_stub.dart'
    if (dart.library.html) 'package:google_sign_in_web/web_only.dart'
    as web_only;
import 'package:wishtogether/features/auth/presentation/verification_page.dart';

class LoginPage extends StatefulWidget {
  static const String route = '/login';

  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with SingleTickerProviderStateMixin {
  final _phoneController = TextEditingController();
  final _authService = getIt<AuthService>();
  late AnimationController _arrowAnimationController;
  late Animation<double> _arrowAnimation;

  static const String _privacyPolicyUrl = 'https://wishtogether.gift/privacy';

  @override
  void initState() {
    super.initState();
    _arrowAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _arrowAnimation = Tween<double>(begin: 0.0, end: 10.0).animate(
      CurvedAnimation(
        parent: _arrowAnimationController,
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _arrowAnimationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: <Widget>[
                    // Login section - always visible at the top
                    // Takes up at least the full viewport height so users must scroll
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: MediaQuery.of(context).size.height,
                      ),
                      child: Stack(
                        children: [
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: <Widget>[
                              Text(
                                'Welcome to WishTogether',
                                style: Theme.of(context).textTheme.displayLarge,
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 40),
                              _googleSignInButton(),
                              const SizedBox(height: 20),
                              _dividerBetweenOAuthAndPhone(),
                              const SizedBox(height: 20),
                              _phoneNumberInputField(),
                              const SizedBox(height: 20),
                              _requestVerificationCodeButton(context),
                            ],
                          ),
                          // Downward arrow indicator - only on web, positioned at bottom
                          if (kIsWeb)
                            Positioned(
                              bottom: 20,
                              left: 0,
                              right: 0,
                              child: Center(
                                child: _buildScrollIndicator(context),
                              ),
                            ),
                        ],
                      ),
                    ),
                    // App information section - only visible on web, below login
                    if (kIsWeb) ..._buildAppInfoSection(context),
                    const SizedBox(height: 24),
                    _buildPrivacyPolicyLink(context),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Renders the Google sign-in button.
  ///
  /// On web this is the button provided by `google_sign_in_web`. On native
  /// platforms (iOS/Android) that package is unavailable, so we render our own
  /// button that drives the native Google sign-in flow through [AuthService].
  Widget _googleSignInButton() {
    if (kIsWeb) {
      return web_only.renderButton();
    }
    return ElevatedButton(
      onPressed: _signInWithGoogle,
      child: const Text('Sign in with Google'),
    );
  }

  Future<void> _signInWithGoogle() async {
    try {
      await _authService.googleSignIn.signIn();
    } catch (error) {
      developer.log('Google sign-in failed', error: error);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Google sign-in failed: $error')),
        );
      }
    }
  }

  Row _dividerBetweenOAuthAndPhone() => const Row(
    children: [
      Expanded(child: Divider()),
      Padding(
        padding: EdgeInsets.symmetric(horizontal: 16.0),
        child: Text('OR'),
      ),
      Expanded(child: Divider()),
    ],
  );

  TextField _phoneNumberInputField() => TextField(
    controller: _phoneController,
    decoration: const InputDecoration(
      labelText: 'Phone Number (e.g. 408 555 1234)',
      border: OutlineInputBorder(),
    ),
    keyboardType: TextInputType.phone,
  );

  ElevatedButton _requestVerificationCodeButton(
    BuildContext context,
  ) => ElevatedButton(
    onPressed: () async {
      // Automatically prepend the US country code
      final phoneNumber = '+1${_phoneController.text}';

      final redirectTo = GoRouterState.of(context)
          .uri
          .queryParameters[redirectToParam];
      await _authService.verifyPhoneNumber(
        phoneNumber: phoneNumber,
        verificationCompleted: (credential) async {
          await _authService.signInWithPhoneCredential(credential);
          // ignore: use_build_context_synchronously
          if (context.mounted) {
            context.go(redirectTo ?? '/');
          }
        },
        verificationFailed: (e) {
          developer.log('Phone verification failed', error: e);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Phone verification failed: ${e.message}'),
              ),
            );
          }
        },
        codeSent: (verificationId, forceResendingToken) {
          if (mounted) {
            final redirectTo = GoRouterState.of(context)
                .uri
                .queryParameters[redirectToParam];
            final verifyUri = redirectTo != null
                ? '${VerificationPage.route}?$redirectToParam=${Uri.encodeComponent(redirectTo)}'
                : VerificationPage.route;
            context.go(verifyUri, extra: verificationId);
          }
        },
        codeAutoRetrievalTimeout: (verificationId) {
          developer.log(
            'Auto-retrieval timeout for verification ID: $verificationId',
          );
        },
      );
    },
    child: const Text('Send Verification Code'),
  );

  List<Widget> _buildAppInfoSection(BuildContext context) {
    return [
      const SizedBox(height: 60),
      Text(
        'About WishTogether',
        style: Theme.of(context).textTheme.headlineMedium,
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 24),
      Text(
        'Make gift-giving for families and groups simple, fun, and spoiler-free.',
        style: Theme.of(context).textTheme.bodyLarge,
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 40),
      _buildFeatureCard(
        context,
        icon: Icons.list_alt,
        title: 'Create Wishlists',
        description: 'Create and manage your personal wishlists. Add items you\'d love to receive, and keep them organized.',
      ),
      const SizedBox(height: 20),
      _buildFeatureCard(
        context,
        icon: Icons.group,
        title: 'Share with Groups',
        description: 'Create groups with family and friends. Keep wishlists synced between multiple groups. Great for in-laws!',
      ),
      const SizedBox(height: 20),
      _buildFeatureCard(
        context,
        icon: Icons.card_giftcard,
        title: 'Spoiler-Free Gifting',
        description: 'By default, no need to worry about spoilers! The owner can enable spoiler mode when they\'re ready to see what\'s been claimed.',
      ),
      const SizedBox(height: 40),
    ];
  }

  Widget _buildFeatureCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 40, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text(
                    description,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildScrollIndicator(BuildContext context) {
    return AnimatedBuilder(
      animation: _arrowAnimation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, _arrowAnimation.value),
          child: Icon(
            Icons.keyboard_arrow_down,
            size: 48,
            color: Theme.of(context).colorScheme.primary.withAlpha(179),
          ),
        );
      },
    );
  }

  Widget _buildPrivacyPolicyLink(BuildContext context) {
    return TextButton(
      onPressed: () => _launchPrivacyPolicy(),
      child: Text(
        'Privacy Policy',
        style: TextStyle(
          fontSize: Theme.of(context).textTheme.bodySmall?.fontSize,
          decoration: TextDecoration.underline,
        ),
      ),
    );
  }

  Future<void> _launchPrivacyPolicy() async {
    final uri = Uri.parse(_privacyPolicyUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open privacy policy link.')),
        );
      }
    }
  }
}
