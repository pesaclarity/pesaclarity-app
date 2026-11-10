import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/flavor.dart';
import '../../../core/time/clock.dart';
import '../../../data/database/app_database.dart';
import '../../../data/database/database_providers.dart';
import '../../../data/repositories/app_settings_repository.dart';
import '../domain/support.dart';

/// The build's giving settings, as set with `--dart-define`.
final supportDefinesProvider =
    Provider<({String url, String payees, String costs})>(
      (ref) => (
        url: supportUrlDefine,
        payees: supportPayeesDefine,
        costs: supportCostsUrlDefine,
      ),
    );

/// How giving is set up. Only the F-Droid build asks in the app; Play and
/// iPhone show nothing, and giving there is on the website.
final supportConfigProvider = Provider<SupportConfig?>((ref) {
  if (ref.watch(appFlavorProvider) != AppFlavor.foss) return null;
  final defines = ref.watch(supportDefinesProvider);
  return SupportConfig.parse(
    url: defines.url,
    payees: defines.payees,
    costs: defines.costs,
  );
});

/// What the app remembers about giving, kept with Personal.
class SupportStateController extends AsyncNotifier<SupportState> {
  static const settingsKey = 'support.state';

  @override
  Future<SupportState> build() async {
    final saved = SupportState.fromJson(
      await ref.watch(mainSettingsRepositoryProvider).readJson(settingsKey),
    );
    if (saved.firstSeenAt != null) return saved;
    // The 30 days start the first time this build runs.
    final first = saved.copyWith(firstSeenAt: ref.read(clockProvider)());
    await _write(first);
    return first;
  }

  Future<void> _write(SupportState next) => ref
      .read(mainSettingsRepositoryProvider)
      .writeJson(settingsKey, next.toJson());

  Future<void> _save(SupportState Function(SupportState) change) async {
    final next = change(await future);
    await _write(next);
    state = AsyncData(next);
  }

  /// A showing starts: the card shows for 3 days, then rests for 60.
  Future<void> startShowing(DateTime now) => _save(
    (s) =>
        s.copyWith(showingSince: () => now, restUntil: now.add(supportRestFor)),
  );

  /// The card was tapped: it rests from now.
  Future<void> rest() => _save((s) => s.copyWith(showingSince: () => null));

  /// "Don't ask me again".
  Future<void> setOptedOut(bool optedOut) =>
      _save((s) => s.copyWith(optedOut: optedOut));

  /// [gift] has been thanked.
  Future<void> markThanked(Gift gift) =>
      _save((s) => s.copyWith(thanked: {...s.thanked, gift.id}));
}

final supportStateProvider =
    AsyncNotifierProvider<SupportStateController, SupportState>(
      SupportStateController.new,
    );

/// The person's gifts, newest first, from their own M-Pesa messages in
/// Personal. Nothing is asked of the payment service.
final giftsProvider = StreamProvider<List<Gift>>((ref) {
  final config = ref.watch(supportConfigProvider);
  if (config == null || !config.knowsGifts) return Stream.value(const []);
  final db = ref.watch(mainDatabaseProvider);
  final payees = config.payees.toList();
  final query = db.select(db.transactions)
    ..where(
      (t) =>
          t.direction.equalsValue(TransactionDirection.outflow) &
          (t.counterpartyName.lower().isIn(payees) |
              t.counterpartyValue.lower().isIn(payees)),
    )
    ..orderBy([(t) => OrderingTerm.desc(t.occurredAt)]);
  return query.watch().map(
    (rows) => [
      for (final r in rows)
        Gift(
          id: r.id,
          at: r.occurredAt,
          amountMinor: r.amountMinor,
          code: r.receiptNo,
        ),
    ],
  );
});

/// The newest gift to say thank you for, or null.
final giftToThankProvider = Provider<Gift?>((ref) {
  final gifts = ref.watch(giftsProvider).value;
  final state = ref.watch(supportStateProvider).value;
  if (gifts == null || state == null) return null;
  return giftToThank(gifts, state, ref.watch(clockProvider)());
});

/// Opens a giving or costs page in the browser.
abstract interface class SupportOpener {
  Future<bool> open(Uri uri);
}

class BrowserSupportOpener implements SupportOpener {
  const BrowserSupportOpener();

  @override
  Future<bool> open(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);
}

final supportOpenerProvider = Provider<SupportOpener>(
  (ref) => const BrowserSupportOpener(),
);
