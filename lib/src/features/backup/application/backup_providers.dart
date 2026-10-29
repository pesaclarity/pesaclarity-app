import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/io_client.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../config/flavor.dart';
import '../../../core/backup/backup.dart';
import '../../../core/integrity/app_attest.dart';
import '../../../core/integrity/integrity_attestor.dart';
import '../../../core/network/pinned_http_client.dart';
import '../../../core/time/clock.dart';
import '../../auth/application/auth_controller.dart';
import '../../security/data/secure_store.dart';
import '../data/backup_location.dart';
import '../data/backup_settings_repository.dart';
import '../data/backup_sharing.dart';
import '../data/document_storage.dart';
import '../data/drive_client.dart';
import '../data/key_value_store.dart';
import '../data/local_database_backup.dart';
import '../data/vault_client.dart';
import 'backup_service.dart';

final backupKeyValueStoreProvider = Provider<KeyValueStore>(
  (ref) => SecureKeyValueStore(),
);

final backupSettingsRepositoryProvider = Provider<BackupSettingsRepository>(
  (ref) => BackupSettingsRepository(ref.watch(backupKeyValueStoreProvider)),
);

final documentStorageProvider = Provider<DocumentStorage>(
  (ref) => const MethodChannelDocumentStorage(),
);

final fileSharerProvider = Provider<FileSharer>(
  (ref) => const SharePlusFileSharer(),
);

final documentPrinterProvider = Provider<DocumentPrinter>(
  (ref) => const SystemDocumentPrinter(),
);

/// The vault's address; null while the vault is not deployed.
final vaultBaseUrlProvider = Provider<Uri?>((ref) => VaultConfig.uri);

final vaultTokenSourceProvider = Provider<VaultTokenSource>(
  (ref) => const SignedOutVaultTokenSource(),
);

/// Apple App Attest on the iPhone.
final appAttestServiceProvider = Provider<AppAttestService>(
  (ref) => const PlatformAppAttestService(),
);

/// Proves vault uploads come from the genuine app: Play Integrity on Google
/// Play builds, App Attest on iPhone, nothing on F-Droid builds.
final vaultIntegrityProvider = Provider<IntegrityHeaderHook>((ref) {
  final url = ref.watch(vaultBaseUrlProvider);
  if (ref.watch(appFlavorProvider) != AppFlavor.appstore || url == null) {
    return ref.watch(integrityHeaderHookProvider);
  }
  final tokens = ref.watch(vaultTokenSourceProvider);
  final sessions = ref.watch(sessionStoreProvider);
  return IntegrityHeaderHook(
    AppAttestAttestor(
      service: ref.watch(appAttestServiceProvider),
      server: HttpAppAttestServer(
        baseUrl: url,
        accessToken: tokens.accessToken,
        client: IOClient(ref.watch(httpClientFactoryProvider).create()),
      ),
      store: ref.watch(secureStoreProvider),
      accountId: () async => (await sessions.read())?.accountId,
    ),
  );
});

/// Google sign-in for Drive.
///
/// Only a Play build may ever return a working [DriveAuth]; none exists yet,
/// so every build reports Drive as unavailable.
final driveAuthProvider = Provider<DriveAuth>(
  (ref) => const UnavailableDriveAuth(),
);

/// Whether this build may show Google Drive at all.
final driveAllowedProvider = Provider<bool>(
  (ref) => ref.watch(appFlavorProvider).allowsGoogleServices,
);

final localDataStoreProvider = Provider<LocalDataStore>(
  SqlCipherLocalDataStore.new,
);

/// Encryption cost for new backups. Tests lower it.
final backupKdfParamsProvider = Provider<KdfParams>(
  (ref) => KdfParams.recommended,
);

final backupServiceProvider = Provider<BackupService>(
  (ref) => BackupService(
    data: ref.watch(localDataStoreProvider),
    settings: ref.watch(backupSettingsRepositoryProvider),
    workDirectory: () async =>
        Directory(p.join((await getTemporaryDirectory()).path, 'backup')),
    clock: ref.watch(clockProvider),
    kdfParams: ref.watch(backupKdfParamsProvider),
  ),
);

/// Which locations this build and phone can offer, whether or not they are
/// switched on.
final class BackupAvailability {
  const BackupAvailability({required this.vault, required this.drive});

  final bool vault;
  final bool drive;
}

final backupAvailabilityProvider = Provider<BackupAvailability>(
  (ref) => BackupAvailability(
    vault: ref.watch(vaultBaseUrlProvider) != null,
    drive: ref.watch(driveAuthProvider).isAvailable,
  ),
);

/// Backup settings for the screen, with the actions that change them.
final backupControllerProvider =
    AsyncNotifierProvider<BackupController, BackupSettings>(
      BackupController.new,
    );

class BackupController extends AsyncNotifier<BackupSettings> {
  BackupSettingsRepository get _repo =>
      ref.read(backupSettingsRepositoryProvider);

  @override
  Future<BackupSettings> build() =>
      ref.watch(backupSettingsRepositoryProvider).load();

  Future<void> _save(BackupSettings next) async {
    await _repo.save(next);
    state = AsyncData(next);
  }

  /// Stores the passphrase and recovery key for new backups.
  Future<void> completeSetup(BackupSecrets secrets) async {
    await _repo.writeSecrets(secrets);
    state = AsyncData(await _repo.load());
  }

  /// Switches [id] on or off. Switching the phone folder on asks for a
  /// folder first; returns false if the user backs out.
  Future<bool> setEnabled(BackupLocationId id, bool on) async {
    final current = await future;
    var next = current;
    if (on && id == BackupLocationId.deviceFolder) {
      final storage = ref.read(documentStorageProvider);
      final folder = current.folder;
      final usable = folder != null && await storage.canWrite(folder);
      if (!usable) {
        final picked = await storage.pickFolder();
        if (picked == null) return false;
        next = next.copyWith(folder: picked);
      }
    }
    if (on && id == BackupLocationId.drive) {
      final auth = ref.read(driveAuthProvider);
      if (await auth.currentAccount() == null && await auth.signIn() == null) {
        return false;
      }
    }
    await _save(
      next.copyWith(
        enabled: on ? {...next.enabled, id} : ({...next.enabled}..remove(id)),
      ),
    );
    return true;
  }

  /// Asks for a different folder for phone backups.
  Future<void> changeFolder() async {
    final picked = await ref.read(documentStorageProvider).pickFolder();
    if (picked == null) return;
    final current = await future;
    await _save(
      current.copyWith(
        folder: picked,
        enabled: {...current.enabled, BackupLocationId.deviceFolder},
      ),
    );
  }

  IOClient _pinnedClient() =>
      IOClient(ref.read(httpClientFactoryProvider).create());

  /// The location object for [id], or null if it cannot be used now.
  BackupLocation? locationFor(BackupLocationId id, BackupSettings settings) {
    switch (id) {
      case BackupLocationId.vault:
        final url = ref.read(vaultBaseUrlProvider);
        return url == null
            ? null
            : VaultBackupLocation(
                baseUrl: url,
                tokens: ref.read(vaultTokenSourceProvider),
                client: _pinnedClient(),
                integrity: ref.read(vaultIntegrityProvider),
              );
      case BackupLocationId.drive:
        final auth = ref.read(driveAuthProvider);
        return auth.isAvailable
            // Google's keys are not ours to pin; Drive uses system trust.
            ? DriveBackupLocation(
                auth,
                client: IOClient(
                  ref.read(httpClientFactoryProvider).createUnpinned(),
                ),
              )
            : null;
      case BackupLocationId.deviceFolder:
        final folder = settings.folder;
        return folder == null
            ? null
            : DeviceFolderLocation(ref.read(documentStorageProvider), folder);
    }
  }

  /// The switched-on locations that can be used now.
  List<BackupLocation> activeLocations(BackupSettings settings) => [
    for (final id in BackupLocationId.values)
      if (settings.enabled.contains(id)) ?locationFor(id, settings),
  ];

  /// Backs up to every switched-on location.
  Future<BackupRunReport> backUpNow() async {
    final settings = await future;
    final report = await ref
        .read(backupServiceProvider)
        .backUp(activeLocations(settings));
    state = AsyncData(await _repo.load());
    return report;
  }
}
