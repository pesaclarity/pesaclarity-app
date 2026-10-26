/// Gets a Google ID token for `POST /v1/auth/google`.
///
/// Only the play flavour may provide a working one; the foss build must not
/// depend on Google services.
abstract interface class GoogleIdTokenSource {
  /// Whether this build can sign in with Google.
  bool get isAvailable;

  /// Shows Google's account picker. Returns null when the person cancels.
  Future<String?> requestIdToken();
}

/// Used until the Play build wires in Credential Manager, and always in foss.
class UnavailableGoogleIdTokenSource implements GoogleIdTokenSource {
  const UnavailableGoogleIdTokenSource();

  @override
  bool get isAvailable => false;

  @override
  Future<String?> requestIdToken() async => null;
}
