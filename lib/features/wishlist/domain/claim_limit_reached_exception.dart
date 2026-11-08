/// A claim was refused because the item already has as many claimants as its
/// limit allows.
///
/// Lives in the domain layer so the repository and the application layer can
/// name the same condition without importing each other.
class ClaimLimitReachedException implements Exception {
  const ClaimLimitReachedException();

  @override
  String toString() => 'ClaimLimitReachedException';
}
