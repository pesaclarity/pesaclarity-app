/// What the app says when something that needs the internet runs offline.
///
/// Everything else works without a connection, so these are the only
/// places being offline shows; kept together so the wording is easy to
/// review and change.
abstract final class OfflineMessages {
  /// The sign-in panel, for someone not signed in.
  static const signIn =
      'Signing in needs a connection. Everything else works offline.';

  /// Signed-in phones, which the server keeps.
  static const devicesList = 'This list needs a connection.';

  /// A backup that reached [places] (such as "SD card") but not the vault.
  static String backedUpExceptVault(String places) =>
      'Backed up to $places. The vault needs a connection; it will back up '
      'when you are online.';

  /// A backup whose only place is the vault.
  static const vaultOnly =
      'The vault needs a connection. Everything else works offline.';

  /// A space deleted here whose online copy is deleted once online.
  static const onlineCopyDeletedLater =
      'Deleted on this phone. The online copy will be deleted when you are '
      'online.';

  /// Data deleted here whose online copy could not be deleted, and cannot
  /// be remembered (Delete all my data leaves nothing behind).
  static const deleteOnlineCopyLater =
      'Deleted on this phone. Delete the online copy from Backups when you '
      'are online.';
}
