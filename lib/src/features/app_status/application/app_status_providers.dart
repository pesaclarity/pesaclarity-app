import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/build_info.dart';
import '../../../config/server_config.dart';
import '../../../core/network/pinned_http_client.dart';
import '../../../core/time/clock.dart';
import '../../../data/repositories/app_settings_repository.dart';
import '../../auth/data/json_transport.dart';
import '../../counting/application/counting.dart';
import '../data/app_status_memo.dart';
import '../data/app_status_source.dart';
import '../data/app_status_verifier.dart';
import '../domain/app_status.dart';
import '../domain/pinned_keys.dart';
import 'message_rereader.dart';
import 'update_links.dart';

/// How often the app asks the server at most.
const appStatusInterval = Duration(days: 1);

/// The server's app status, or null when the build has no server address.
final appStatusSourceProvider = Provider<AppStatusSource?>((ref) {
  final baseUrl = ref.watch(serverBaseUrlProvider);
  if (baseUrl == null) return null;
  return HttpAppStatusSource(
    baseUrl: baseUrl,
    transport: IoJsonTransport(
      client: ref.watch(httpClientFactoryProvider).create(),
    ),
  );
});

/// The public keys a response must be signed with (pinned in source).
final appStatusPublicKeysProvider = Provider<List<String>>(
  (ref) => appStatusPublicKeys,
);

/// The verified status and the closed cards, for Home and the update gate.
class AppStatusView {
  const AppStatusView(this.status, this.dismissed);

  final AppStatus status;
  final Set<String> dismissed;

  AppNotice? get blocking => status.blocking;

  List<AppNotice> get cards => status.cards(dismissed);
}

/// Asks the server once when the app opens, and at most once a day, using
/// the last verified answer in between. Null, never an error, whenever there
/// is nothing verified to show: no server, no pinned key, no version,
/// offline, or a response that failed its checks.
class AppStatusController extends AsyncNotifier<AppStatusView?> {
  AppStatusMemo _memo = const AppStatusMemo();

  AppSettingsRepository get _settings =>
      ref.read(mainSettingsRepositoryProvider);

  @override
  Future<AppStatusView?> build() async {
    final source = ref.watch(appStatusSourceProvider);
    final version = ref.watch(buildVersionProvider).trim();
    final verifier = AppStatusVerifier(ref.watch(appStatusPublicKeysProvider));
    if (source == null || version.isEmpty || !verifier.hasKeys) return null;
    final build = ref.watch(updateChannelProvider).name;
    final platform = ref.watch(appStatusPlatformProvider);
    try {
      return await _load(source, verifier, version, build, platform);
    } on Object {
      return null;
    }
  }

  Future<AppStatusView?> _load(
    AppStatusSource source,
    AppStatusVerifier verifier,
    String version,
    String build,
    String platform,
  ) async {
    final now = ref.read(clockProvider)().toUtc();
    _memo = AppStatusMemo.fromJson(
      await _settings.readJson(AppStatusMemo.settingsKey),
    );
    Future<AppStatus?> check(Object? envelope) => verifier.verify(
      envelope,
      version: version,
      build: build,
      platform: platform,
      now: now,
      notBefore: _memo.issuedAt,
    );

    final fetchedAt = _memo.fetchedAt;
    final fresh =
        fetchedAt != null &&
        _memo.fetchedFor == version &&
        !fetchedAt.isAfter(now) &&
        now.difference(fetchedAt) < appStatusInterval;
    AppStatus? status;
    if (fresh) {
      status = await check(_memo.envelope);
    } else {
      final envelope = await source.fetch(
        version: version,
        build: build,
        platform: platform,
        countToken: await _countToken(),
      );
      // Offline: try again next time the app opens.
      if (envelope == null) return null;
      status = await check(envelope);
      _memo = status == null
          ? _memo.copyWith(
              fetchedAt: now,
              fetchedFor: version,
              clearEnvelope: true,
            )
          : _memo.copyWith(
              envelope: envelope as Map<String, Object?>,
              fetchedAt: now,
              fetchedFor: version,
              issuedAt: status.issuedAt,
            );
      await _save();
    }
    if (status == null) return null;
    await _askForRereads(status);
    return AppStatusView(status, _memo.dismissed);
  }

  /// This month's counting token, or null; a failure never stops the check.
  Future<String?> _countToken() async {
    try {
      return await ref.read(countTokenIssuerProvider).tokenForCheckIn();
    } on Object {
      return null;
    }
  }

  /// Hands each notice's `reread_from` to the re-reader once.
  Future<void> _askForRereads(AppStatus status) async {
    final rereader = ref.read(messageRereaderProvider);
    final taken = {..._memo.reread};
    for (final notice in status.notices) {
      final from = notice.rereadFrom;
      if (from == null || taken.contains(notice.id)) continue;
      if (await rereader.requestReread(from)) taken.add(notice.id);
    }
    if (taken.length != _memo.reread.length) {
      _memo = _memo.copyWith(reread: taken);
      await _save();
    }
  }

  /// Closes [notice]'s card. An update's card comes back for a newer
  /// version.
  Future<void> dismiss(AppNotice notice) async {
    final view = state.value;
    if (view == null) return;
    final dismissed = {..._memo.dismissed, notice.dismissKey};
    _memo = _memo.copyWith(dismissed: dismissed);
    state = AsyncData(AppStatusView(view.status, dismissed));
    try {
      await _save();
    } on Object {
      // Closed for this launch even if it could not be saved.
    }
  }

  Future<void> _save() =>
      _settings.writeJson(AppStatusMemo.settingsKey, _memo.toJson());
}

final appStatusProvider =
    AsyncNotifierProvider<AppStatusController, AppStatusView?>(
      AppStatusController.new,
    );

/// The notice that blocks this build, if a verified one does.
final blockingNoticeProvider = Provider<AppNotice?>(
  (ref) => ref.watch(appStatusProvider).value?.blocking,
);
