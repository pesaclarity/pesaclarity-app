/// Errors raised while reading or restoring a `.pcbackup` file.
///
/// Every failure is one of these subtypes, so the restore screen can say
/// exactly what went wrong without parsing messages.
sealed class BackupException implements Exception {
  const BackupException(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// The bytes do not start with the `.pcbackup` magic.
final class NotABackupFileException extends BackupException {
  const NotABackupFileException()
    : super('This file is not a Pesa Clarity backup.');
}

/// The file was written by a format version this build cannot read.
final class UnsupportedBackupVersionException extends BackupException {
  const UnsupportedBackupVersionException(this.version)
    : super('Backup format version $version is not supported.');

  final int version;
}

/// The header asks for a KDF or chunk size outside the accepted bounds.
///
/// Bounds are enforced before any key derivation so a crafted file cannot
/// make the phone allocate gigabytes of memory.
final class UnsupportedBackupParametersException extends BackupException {
  const UnsupportedBackupParametersException(super.message);
}

/// The passphrase or recovery key does not unlock this backup.
final class WrongBackupCredentialException extends BackupException {
  const WrongBackupCredentialException()
    : super('The passphrase or recovery key does not open this backup.');
}

/// The file is damaged: nothing from it may be restored.
sealed class BackupIntegrityException extends BackupException {
  const BackupIntegrityException(super.message);
}

/// The file ends early, at the header or at a chunk boundary.
final class BackupTruncatedException extends BackupIntegrityException {
  const BackupTruncatedException() : super('The backup file is incomplete.');
}

/// The header or encrypted payload was changed after it was written.
final class BackupTamperedException extends BackupIntegrityException {
  const BackupTamperedException(super.message);
}

/// A typed-in recovery key is malformed or fails its checksum.
final class InvalidRecoveryKeyException extends BackupException {
  const InvalidRecoveryKeyException(super.message);
}
