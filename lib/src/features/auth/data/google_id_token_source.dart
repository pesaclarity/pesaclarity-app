import 'package:flutter/services.dart';

import '../domain/auth_models.dart';

/// The OAuth web client id the server accepts as the token audience, set at
/// build time with `--dart-define=PESACLARITY_GOOGLE_SERVER_CLIENT_ID=...`.
const googleServerClientId = String.fromEnvironment(
  'PESACLARITY_GOOGLE_SERVER_CLIENT_ID',
);

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

/// The play build's source: Android's Credential Manager, behind a platform
/// channel. The foss build answers the same channel without Google code.
class PlatformGoogleIdTokenSource implements GoogleIdTokenSource {
  const PlatformGoogleIdTokenSource({
    required this.serverClientId,
    this._channel = const MethodChannel('com.pesaclarity.app/google_sign_in'),
  });

  final String serverClientId;
  final MethodChannel _channel;

  @override
  bool get isAvailable => serverClientId.isNotEmpty;

  @override
  Future<String?> requestIdToken() async {
    try {
      return await _channel.invokeMethod<String>('requestIdToken', {
        'serverClientId': serverClientId,
      });
    } on PlatformException catch (e) {
      throw AuthFailure(switch (e.code) {
        'no_account' => AuthFailureKind.noGoogleAccount,
        'unavailable' => AuthFailureKind.unavailable,
        _ => AuthFailureKind.server,
      }, e.message);
    }
  }
}
