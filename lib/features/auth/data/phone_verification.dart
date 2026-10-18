import 'package:firebase_auth/firebase_auth.dart';

/// The outcome of starting a phone verification.
sealed class PhoneVerification {
  const PhoneVerification();
}

/// An SMS code was sent to the phone number and must be confirmed.
final class PhoneVerificationCodeSent extends PhoneVerification {
  const PhoneVerificationCodeSent(this.verificationId);

  final String verificationId;
}

/// The platform verified the device itself, so no code is needed.
///
/// Android instant verification completes this way when Play Services can
/// confirm the SIM without sending an SMS.
final class PhoneVerificationAutoVerified extends PhoneVerification {
  const PhoneVerificationAutoVerified(this.credential);

  final PhoneAuthCredential credential;
}
