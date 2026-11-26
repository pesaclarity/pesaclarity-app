import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../../core/network/pinned_http_client.dart';
import '../../../data/repositories/app_settings_repository.dart';
import '../application/ask_providers.dart';
import 'ask_model_capability.dart';
import 'ask_model_catalogue.dart';
import 'ask_model_device.dart';
import 'ask_model_download.dart';
import 'slm_facts.dart';
import 'slm_generator.dart';

/// Where a model download is.
enum AskModelPhase { idle, waitingForWifi, downloading, checking, failed }

/// Why the last download did not give a model.
enum AskModelProblem { network, space, tooSlow, mismatch }

/// Ask's money model on this phone: what it can run, what is downloaded and
/// chosen, and any download under way.
class AskModelState {
  const AskModelState({
    this.loaded = false,
    this.catalogue = AskModelCatalogue.empty,
    this.capable = const [],
    this.installed,
    this.selected,
    this.mobileData = false,
    this.offerDone = false,
    this.tooSlow = const {},
    this.phase = AskModelPhase.idle,
    this.target,
    this.progress = const AskModelProgress(0, 0),
    this.onWifi = true,
    this.secondsLeft,
    this.problem,
    this.directory,
  });

  final bool loaded;
  final AskModelCatalogue catalogue;

  /// The models this phone can run; empty means no offer anywhere.
  final List<AskModelEntry> capable;

  /// The checked model on the phone (only one is kept).
  final AskModelTier? installed;

  /// The person's choice; null is "No model".
  final AskModelTier? selected;
  final bool mobileData;

  /// The offer card was answered (downloaded or "Not now").
  final bool offerDone;
  final Set<AskModelTier> tooSlow;
  final AskModelPhase phase;

  /// The model being fetched.
  final AskModelEntry? target;
  final AskModelProgress progress;

  /// Whether the download runs over Wi-Fi (else mobile data).
  final bool onWifi;
  final int? secondsLeft;
  final AskModelProblem? problem;
  final String? directory;

  /// Whether Ask shows "Get better answers".
  bool get offerVisible =>
      loaded &&
      capable.isNotEmpty &&
      !offerDone &&
      installed == null &&
      phase == AskModelPhase.idle;

  /// Whether Ask shows the download card.
  bool get downloadVisible => phase != AskModelPhase.idle;

  /// Whether Ask settings has the Answers section.
  bool get settingsVisible => capable.isNotEmpty || installed != null;

  /// The model Ask answers with, or null for Ask as it is without one.
  AskModelEntry? get active =>
      selected != null && selected == installed ? catalogue[selected!] : null;

  /// Where [active]'s file is.
  String? get activePath {
    final model = active;
    final dir = directory;
    return model == null || dir == null ? null : p.join(dir, model.file);
  }

  AskModelState copyWith({
    bool? loaded,
    AskModelCatalogue? catalogue,
    List<AskModelEntry>? capable,
    AskModelTier? Function()? installed,
    AskModelTier? Function()? selected,
    bool? mobileData,
    bool? offerDone,
    Set<AskModelTier>? tooSlow,
    AskModelPhase? phase,
    AskModelEntry? Function()? target,
    AskModelProgress? progress,
    bool? onWifi,
    int? Function()? secondsLeft,
    AskModelProblem? Function()? problem,
    String? directory,
  }) => AskModelState(
    loaded: loaded ?? this.loaded,
    catalogue: catalogue ?? this.catalogue,
    capable: capable ?? this.capable,
    installed: installed == null ? this.installed : installed(),
    selected: selected == null ? this.selected : selected(),
    mobileData: mobileData ?? this.mobileData,
    offerDone: offerDone ?? this.offerDone,
    tooSlow: tooSlow ?? this.tooSlow,
    phase: phase ?? this.phase,
    target: target == null ? this.target : target(),
    progress: progress ?? this.progress,
    onWifi: onWifi ?? this.onWifi,
    secondsLeft: secondsLeft == null ? this.secondsLeft : secondsLeft(),
    problem: problem == null ? this.problem : problem(),
    directory: directory ?? this.directory,
  );
}

/// Reads the phone's memory, free space and network.
final askModelDeviceProvider = Provider<AskModelDevice>(
  (ref) => const PlatformAskModelDevice(),
);

/// The signed catalogue bundled with the app, checked; empty when the
/// signature or any entry does not check out.
final askModelCatalogueProvider = FutureProvider<AskModelCatalogue>((
  ref,
) async {
  final bytes = await ref.watch(askAssetReaderProvider)(askModelCatalogueAsset);
  if (bytes == null) return AskModelCatalogue.empty;
  try {
    return await AskModelCatalogue.verify(jsonDecode(utf8.decode(bytes)));
  } on FormatException {
    return AskModelCatalogue.empty;
  }
});

/// `ask-models/` in app support storage.
final askModelDirectoryProvider = FutureProvider<Directory>(
  (ref) async => Directory(
    p.join((await getApplicationSupportDirectory()).path, 'ask-models'),
  ),
);

/// GitHub is not our server, so the download uses the phone's own
/// certificate checks, not our pinning.
final askModelHttpClientProvider = Provider<http.Client Function()>(
  (ref) =>
      () => IOClient(ref.read(httpClientFactoryProvider).createUnpinned()),
);

/// Opens the model at a path and times a short reply: true when it is
/// quick enough on this phone.
typedef AskModelWarmUp = Future<bool> Function(String path);

final askModelWarmUpProvider = Provider<AskModelWarmUp>((ref) => _warmUp);

Future<bool> _warmUp(String path) async {
  final generator = RayoSlmGenerator(path: path);
  try {
    const facts = SlmFacts([
      SlmFactSection('This month', ['Spent: KES 1,000']),
    ]);
    await for (final event
        in generator
            .ask(system: slmSystem(facts), question: 'How much did I spend?')
            .timeout(const Duration(seconds: 60))) {
      switch (event) {
        case SlmPiece():
          break;
        case SlmDone(:final stats):
          return fastEnough(stats.tokensPerSecond);
        case SlmFailed():
          return false;
      }
    }
    return false;
  } on Object {
    return false;
  } finally {
    await generator.close();
  }
}

/// Ask's model on this phone, kept for the whole app (not per space).
class AskModelController extends Notifier<AskModelState> {
  static const key = 'ask.model';

  AskModelCancel? _cancel;
  Timer? _wifiWait;

  @override
  AskModelState build() {
    ref.onDispose(() {
      _cancel?.cancel();
      _wifiWait?.cancel();
    });
    unawaited(_load());
    return const AskModelState();
  }

  AppSettingsRepository get _settings =>
      ref.read(mainSettingsRepositoryProvider);

  AskModelDevice get _device => ref.read(askModelDeviceProvider);

  Future<void> _load() async {
    try {
      final saved = await _settings.readJson(key) ?? const {};
      final catalogue = await ref.read(askModelCatalogueProvider.future);
      final dir = await ref.read(askModelDirectoryProvider.future);
      final files = AskModelFiles(dir);
      AskModelTier? installed;
      for (final m in catalogue.models) {
        if (files.has(m)) installed = m.tier;
      }
      final tooSlow = {
        for (final t in saved['tooSlow'] as List? ?? const [])
          ?AskModelTier.values.asNameMap()[t],
      };
      final capable = catalogue.models.isEmpty
          ? const <AskModelEntry>[]
          : capableModels(
              catalogue,
              memoryBytes: await _device.memoryBytes(),
              freeBytes: await _freeBytes(dir),
              tooSlow: tooSlow,
            );
      if (!ref.mounted) return;
      state = state.copyWith(
        loaded: true,
        catalogue: catalogue,
        capable: capable,
        installed: () => installed,
        selected: () => AskModelTier.values.asNameMap()[saved['selected']],
        mobileData: saved['mobileData'] as bool? ?? false,
        offerDone: saved['offerDone'] as bool? ?? false,
        tooSlow: tooSlow,
        directory: dir.path,
      );
    } on Object {
      // No storage or no platform: no model, Ask as it is.
      if (ref.mounted) state = state.copyWith(loaded: true);
    }
  }

  Future<int?> _freeBytes(Directory dir) async {
    var at = dir;
    while (!at.existsSync() && at.parent.path != at.path) {
      at = at.parent;
    }
    return _device.freeBytes(at.path);
  }

  Future<void> _save() => _settings.writeJson(key, {
    'selected': ?state.selected?.name,
    'mobileData': state.mobileData,
    'offerDone': state.offerDone,
    'tooSlow': [for (final t in state.tooSlow) t.name],
  });

  /// "Not now": the offer goes for good; Ask settings still has it.
  Future<void> notNow() async {
    state = state.copyWith(offerDone: true);
    await _save();
  }

  Future<void> setMobileData(bool on) async {
    state = state.copyWith(mobileData: on);
    await _save();
    if (on && state.phase == AskModelPhase.waitingForWifi) {
      final target = state.target;
      if (target != null) await download(target.tier);
    }
  }

  /// Picks [tier], downloading it first when it is not here; null is
  /// "No model".
  Future<void> choose(AskModelTier? tier) async {
    if (tier == null || tier == state.installed) {
      state = state.copyWith(selected: () => tier);
      await _save();
      return;
    }
    await download(tier);
  }

  /// Fetches [tier] (Wi-Fi only unless mobile data is on), checks it, times
  /// a warm-up reply, and then makes it Ask's model.
  Future<void> download(AskModelTier tier) async {
    final model = state.catalogue[tier];
    final dirPath = state.directory;
    if (model == null || dirPath == null) return;
    if (state.phase == AskModelPhase.downloading ||
        state.phase == AskModelPhase.checking) {
      return;
    }
    _wifiWait?.cancel();
    state = state.copyWith(
      offerDone: true,
      target: () => model,
      problem: () => null,
    );
    await _save();
    final onWifi = await _device.onUnmeteredNetwork();
    if (!onWifi && !state.mobileData) {
      state = state.copyWith(phase: AskModelPhase.waitingForWifi);
      _wifiWait = Timer.periodic(const Duration(seconds: 20), (_) async {
        if (await _device.onUnmeteredNetwork() &&
            state.phase == AskModelPhase.waitingForWifi) {
          _wifiWait?.cancel();
          await download(tier);
        }
      });
      return;
    }
    final dir = Directory(dirPath);
    final files = AskModelFiles(dir);
    await dir.create(recursive: true);
    await _device.excludeFromBackup(dir.path);
    final have = files.partBytes(model);
    if (!fitsSpace(model, await _freeBytes(dir), alreadyHave: have)) {
      state = state.copyWith(
        phase: AskModelPhase.failed,
        problem: () => AskModelProblem.space,
      );
      return;
    }
    final cancel = _cancel = AskModelCancel();
    final started = DateTime.now();
    var last = DateTime(0);
    state = state.copyWith(
      phase: AskModelPhase.downloading,
      onWifi: onWifi,
      progress: AskModelProgress(have, model.sizeBytes),
      secondsLeft: () => null,
    );
    final client = ref.read(askModelHttpClientProvider)();
    try {
      final file = await files.download(
        model,
        client: client,
        cancel: cancel,
        onProgress: (progress) {
          final now = DateTime.now();
          if (now.difference(last) < const Duration(milliseconds: 250) &&
              progress.received < progress.total) {
            return;
          }
          last = now;
          final seconds = now.difference(started).inMilliseconds / 1000;
          final got = progress.received - have;
          state = state.copyWith(
            progress: progress,
            secondsLeft: () => seconds < 2 || got <= 0
                ? null
                : ((progress.total - progress.received) * seconds / got)
                      .round(),
          );
        },
      );
      await _device.excludeFromBackup(file.path);
      state = state.copyWith(phase: AskModelPhase.checking);
      if (!await ref.read(askModelWarmUpProvider)(file.path)) {
        await file.delete();
        state = state.copyWith(
          phase: AskModelPhase.failed,
          problem: () => AskModelProblem.tooSlow,
          tooSlow: {...state.tooSlow, tier},
          capable: [
            for (final m in state.capable)
              if (m.tier != tier) m,
          ],
        );
        await _save();
        return;
      }
      await files.deleteOthers(model);
      state = state.copyWith(
        phase: AskModelPhase.idle,
        installed: () => tier,
        selected: () => tier,
        target: () => null,
      );
      await _save();
    } on AskModelDownloadFailure catch (e) {
      state = cancel.cancelled
          ? state.copyWith(phase: AskModelPhase.idle, target: () => null)
          : state.copyWith(
              phase: AskModelPhase.failed,
              problem: () => e.reason == 'the file did not match'
                  ? AskModelProblem.mismatch
                  : AskModelProblem.network,
            );
    } finally {
      client.close();
      if (identical(_cancel, cancel)) _cancel = null;
    }
  }

  /// Stops the download (what was fetched is kept to carry on later).
  void cancel() {
    _wifiWait?.cancel();
    _cancel?.cancel();
    if (state.phase == AskModelPhase.waitingForWifi ||
        state.phase == AskModelPhase.failed) {
      state = state.copyWith(phase: AskModelPhase.idle, target: () => null);
    }
  }

  /// Deletes the model and any half-fetched file; Ask goes back to
  /// answering without one.
  Future<void> deleteModel() async {
    cancel();
    final dir = state.directory;
    if (dir != null) await AskModelFiles(Directory(dir)).deleteAll();
    state = state.copyWith(installed: () => null, selected: () => null);
    await _save();
  }
}

final askModelControllerProvider =
    NotifierProvider<AskModelController, AskModelState>(AskModelController.new);

/// The model Ask answers with, opened on first use and closed when the
/// choice changes; null for Ask as it is without one.
final askModelGeneratorProvider = Provider<SlmGenerator?>((ref) {
  final path = ref.watch(
    askModelControllerProvider.select((s) => s.activePath),
  );
  if (path == null) return null;
  final generator = RayoSlmGenerator(path: path);
  ref.onDispose(generator.close);
  return generator;
});
