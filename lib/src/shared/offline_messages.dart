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

  /// Delete all my data with its online options ticked, and no
  /// connection: asked before anything is deleted.
  static String deleteAllNeedsConnection({
    required bool backup,
    required bool signIn,
  }) => switch ((backup, signIn)) {
    (true, true) =>
      'Deleting your online backup and sign-in needs a connection.',
    (true, false) => 'Deleting your online backup needs a connection.',
    _ => 'Deleting your sign-in needs a connection.',
  };

  /// Erases the phone and skips the online steps.
  static const deleteOnPhoneOnly = 'Delete on this phone only';

  /// Closes the question; nothing is deleted.
  static const waitUntilOnline = "Wait until I'm online";

  /// Online, Delete all my data deleted the phone but an online step
  /// failed partway.
  static String deleteAllLeftOnline({
    required bool backup,
    required bool signIn,
  }) => switch ((backup, signIn)) {
    (true, true) =>
      'Deleted on this phone. Your online backup and sign-in could not be '
          'deleted.',
    (true, false) =>
      'Deleted on this phone. Your online backup could not be deleted.',
    _ => 'Deleted on this phone. Your sign-in could not be deleted.',
  };
}
