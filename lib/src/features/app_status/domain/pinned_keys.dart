/// The Ed25519 public keys app status must be signed with, as base64 of the
/// 32 raw bytes.
///
/// They are compiled in and never downloaded or read from settings, because
/// a key that can be swapped at run time protects nothing. Changing the list
/// is a reviewed code change that ships in an app release; add a new key a
/// release before the server signs with it.
library;

/// The production key: the public key `uv run ngome-app-status-key` prints in
/// pesaclarity-backend. While it is empty no response can be verified, so the
/// app asks for nothing and shows no notices.
const appStatusProductionPublicKey = '';

/// Every key a response may be signed with.
const appStatusPublicKeys = <String>[appStatusProductionPublicKey];
