/// The Ed25519 public keys app status must be signed with, as base64 of the
/// 32 raw bytes.
///
/// They are compiled in and never downloaded or read from settings, because
/// a key that can be swapped at run time protects nothing. Changing the list
/// is a reviewed code change that ships in an app release; add a new key a
/// release before the server signs with it.
library;

/// The production key: the public half of the seed pesaclarity-backend signs
/// with (`NGOME_APP_STATUS_SIGNING_SEED`). With it empty no response could be
/// verified, so the app would ask for nothing and show no notices.
const appStatusProductionPublicKey =
    'NXR6XVU3vs0bGJWsvY53vCtG/6K9pXYOyDing653iGU=';

/// Every key a response may be signed with.
const appStatusPublicKeys = <String>[appStatusProductionPublicKey];
