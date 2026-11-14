import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ujumbe/ujumbe.dart';

import '../../../data/database/app_database.dart';
import '../../../data/database/database_providers.dart';
import '../../../data/repositories/accounts_repository.dart';
import '../../../data/repositories/app_settings_repository.dart';
import '../../accounts/domain/institution.dart';
import '../data/sms_source.dart';
import 'sms_capture_providers.dart';
import 'sms_ingestor.dart';
import 'transaction_mapping.dart';

/// What a recheck fixed, for the note in Activity: [count] amounts now in
/// [accountId], in [currency]; [currencyChanged] when they were stored in
/// another currency before.
class RecheckNotice {
  const RecheckNotice({
    required this.count,
    required this.accountId,
    required this.currency,
    required this.currencyChanged,
  });

  static RecheckNotice? fromJson(Map<String, Object?>? json) {
    if (json == null) return null;
    final count = json['count'];
    final accountId = json['accountId'];
    final currency = json['currency'];
    if (count is! int || accountId is! int || currency is! String) return null;
    return RecheckNotice(
      count: count,
      accountId: accountId,
      currency: currency,
      currencyChanged: json['currencyChanged'] == true,
    );
  }

  final int count;
  final int accountId;
  final String currency;
  final bool currencyChanged;

  Map<String, Object?> toJson() => {
    'count': count,
    'accountId': accountId,
    'currency': currency,
    'currencyChanged': currencyChanged,
  };
}

/// Reads the messages still in the inbox again with the current packs, and
/// puts each transaction they made in the currency and account the message
/// shows: amounts read before packs knew a bank's other currencies, or
/// before accounts at the same bank were told apart. Runs once per set of
/// pack versions.
class MessageRecheck {
  MessageRecheck({
    required this._db,
    required this._source,
    required this._accounts,
    required this._settings,
    this._parse = parseInBackground,
  });

  final AppDatabase _db;
  final SmsSource _source;
  final AccountsRepository _accounts;
  final AppSettingsRepository _settings;
  final SmsParseBatch _parse;

  static const doneKey = 'sms.recheck';
  static const noticeKey = 'sms.recheckNotice';

  /// Before any phone kept messages: every message.
  static final _beginning = DateTime.utc(2000);

  /// Rechecks [selected] unless their current packs were rechecked before.
  /// Returns the note to show, if anything moved.
  Future<RecheckNotice?> runIfNeeded(List<Institution> selected) async {
    if (selected.isEmpty) return null;
    final version = [
      engineVersion,
      for (final i in selected) '${i.pack.id}@${i.pack.version}',
    ].join(',');
    final done = await _settings.readJson(doneKey);
    if (done?['version'] == version) return null;
    final notice = await recheck(selected);
    if (notice != null) await _settings.writeJson(noticeKey, notice.toJson());
    await _settings.writeJson(doneKey, {'version': version});
    return notice;
  }

  /// Rechecks [selected] now.
  Future<RecheckNotice?> recheck(List<Institution> selected) async {
    final moved = <(int, String), (int, bool)>{};
    for (final institution in selected) {
      final messages = await _source.readInbox(
        senders: institution.senderIds.toSet(),
        since: _beginning,
      );
      if (messages.isEmpty) continue;
      final parsed = [
        for (final r in await _parse([institution.pack], messages))
          if (r is ParsedTransaction) r,
      ]..sort((a, b) => a.time.compareTo(b.time));
      final stored = await _storedByHash({for (final p in parsed) p.rawHash});
      for (final p in parsed) {
        final row = stored[p.rawHash];
        if (row == null) continue;
        final accountId = await _accounts.accountForInstitution(
          institution.id,
          name: institution.name,
          type: institution.type,
          openingDate: p.time,
          currency: p.currency,
          reference: p.ownAccount,
        );
        final currencyChanged = row.currency != p.currency;
        if (!currencyChanged && row.accountId == accountId) continue;
        final fresh = transactionFromParsed(p, accountId: accountId);
        await (_db.update(
          _db.transactions,
        )..where((t) => t.id.equals(row.id))).write(
          TransactionsCompanion(
            accountId: Value(accountId),
            currency: fresh.currency,
            amountMinor: fresh.amountMinor,
            feeMinor: fresh.feeMinor,
            balanceAfterMinor: fresh.balanceAfterMinor,
            owedAfterMinor: fresh.owedAfterMinor,
            // A rate got for the old currency no longer describes it.
            fxRateCurrency: currencyChanged
                ? const Value(null)
                : const Value.absent(),
            fxRateMicros: currencyChanged
                ? const Value(null)
                : const Value.absent(),
          ),
        );
        final key = (accountId, p.currency);
        final (count, changed) = moved[key] ?? (0, false);
        moved[key] = (count + 1, changed || currencyChanged);
      }
    }
    if (moved.isEmpty) return null;
    final top = moved.entries.reduce((a, b) => b.value.$1 > a.value.$1 ? b : a);
    return RecheckNotice(
      count: top.value.$1,
      accountId: top.key.$1,
      currency: top.key.$2,
      currencyChanged: top.value.$2,
    );
  }

  Future<Map<String, TransactionRecord>> _storedByHash(
    Set<String> hashes,
  ) async {
    final found = <String, TransactionRecord>{};
    final list = hashes.toList();
    // SQLite caps the number of values in one query.
    for (var i = 0; i < list.length; i += 500) {
      final chunk = list.sublist(
        i,
        i + 500 > list.length ? list.length : i + 500,
      );
      final rows = await (_db.select(
        _db.transactions,
      )..where((t) => t.messageHash.isIn(chunk))).get();
      for (final row in rows) {
        found[row.messageHash!] = row;
      }
    }
    return found;
  }
}

final messageRecheckProvider = Provider<MessageRecheck>(
  (ref) => MessageRecheck(
    db: ref.watch(appDatabaseProvider),
    source: ref.watch(smsSourceProvider),
    accounts: ref.watch(accountsRepositoryProvider),
    settings: ref.watch(appSettingsRepositoryProvider),
    parse: ref.watch(smsParseBatchProvider),
  ),
);

/// The note in Activity after a recheck moved amounts, until it is closed.
final recheckNoticeProvider = FutureProvider<RecheckNotice?>(
  (ref) async => RecheckNotice.fromJson(
    await ref
        .watch(appSettingsRepositoryProvider)
        .readJson(MessageRecheck.noticeKey),
  ),
);
