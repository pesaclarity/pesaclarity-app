// A phone with two M-Pesa lines, for the screens' tests: "My line" (SIM 1)
// and "Shop line" (SIM 2), before or after the split, on Android or on
// iPhone. Made-up names, numbers and amounts only.
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/app_database.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/data/repositories/app_settings_repository.dart';
import 'package:pesaclarity/src/data/repositories/institutions_repository.dart';
import 'package:pesaclarity/src/domain/accounts/mpesa_lines.dart';
import 'package:pesaclarity/src/domain/spaces/space.dart';
import 'package:pesaclarity/src/features/accounts/application/mpesa_lines_providers.dart';
import 'package:pesaclarity/src/features/accounts/presentation/line_questions.dart';
import 'package:pesaclarity/src/features/accounts/presentation/mpesa_lines_screen.dart';
import 'package:pesaclarity/src/features/accounts/presentation/my_accounts_settings_screen.dart';
import 'package:pesaclarity/src/features/currency/application/currency_controller.dart';
import 'package:pesaclarity/src/features/sms/data/sms_source.dart';
import 'package:pesaclarity/src/features/spaces/application/spaces_providers.dart';
import 'package:pesaclarity/src/shared/widgets/app_sheet.dart';

import '../domain/fixtures.dart';
import 'fake_app_lock.dart';
import 'fake_sms_source.dart';
import 'test_app.dart';

/// Saturday 21 November 2026, 16:30 in Nairobi.
final linesNow = eat(2026, 11, 21, 16, 30);

const linesShop = Space(
  id: 'shop1',
  name: 'Green Basket Grocers',
  kind: SpaceKind.business,
);

/// What [seedLines] made.
class SeededLines {
  const SeededLines(this.db, {required this.iphone, this.waiting});

  final AppDatabase db;
  final bool iphone;

  /// A message waiting for "Which line was this?".
  final ReviewItem? waiting;
}

/// The iPhone's Shortcuts queue, with nothing in it.
class EmptyShortcutQueue extends FakeSmsSource implements ShortcutConnection {
  @override
  Future<DateTime?> lastArrival() async => null;

  @override
  Future<void> openShortcuts() async {}
}

/// Personal with M-Pesa, Equity and Cash, and two M-Pesa lines seen: read
/// as one, or, once [split], each its own account, the Shop line in Green
/// Basket Grocers (on [iphone], both in Personal, told apart by balance,
/// one message waiting for "Which line was this?"). Android's split has a
/// new SIM waiting for "Is this the same line?".
Future<SeededLines> seedLines({bool split = false, bool iphone = false}) async {
  final db = openTestDatabase();
  await DriftAppSettingsRepository(db).writeJson(
    SpacesController.settingsKey,
    spacesToJson([Space.personal, linesShop]),
  );
  final selected = DriftInstitutionsRepository(db);
  await selected.setSelected(mpesaInstitutionId, selected: true);
  await selected.setSelected('equity', selected: true);

  Future<int> account(
    String name,
    AccountType type, {
    String? institution,
    String? reference,
  }) => db
      .into(db.accounts)
      .insert(
        AccountsCompanion.insert(
          name: name,
          type: type,
          openingDate: eat(2026, 10, 1),
          institutionId: Value(institution),
          reference: Value(reference),
        ),
      );

  await account(
    'M-Pesa',
    AccountType.mpesa,
    institution: mpesaInstitutionId,
    reference: split ? lineReference('1') : null,
  );
  if (split) {
    await account(
      'M-Pesa',
      AccountType.mpesa,
      institution: mpesaInstitutionId,
      reference: lineReference('2'),
    );
  }
  await account(
    'Equity Bank ···4321',
    AccountType.bank,
    institution: 'equity',
    reference: '0170****4321',
  );
  await account('Cash', AccountType.cash);

  final lines = MpesaLines(
    split: split,
    surveyed: true,
    lines: [
      MpesaLine(
        id: '1',
        sims: iphone ? const {} : const {'sim:3'},
        name: split && !iphone ? 'My line' : null,
        balanceMinor: kes(12500),
        balanceAt: eat(2026, 11, 21, 10, 42),
        firstAt: eat(2026, 8, 1),
        lastAt: eat(2026, 11, 21, 10, 42),
        messages: 268,
      ),
      MpesaLine(
        id: '2',
        sims: iphone ? const {} : const {'sim:5'},
        name: split && !iphone ? 'Shop line' : null,
        spaceId: split && !iphone ? linesShop.id : personalSpaceId,
        balanceMinor: kes(24330),
        balanceAt: eat(2026, 11, 21, 9, 5),
        firstAt: eat(2026, 8, 3),
        lastAt: eat(2026, 11, 21, 9, 5),
        messages: 144,
      ),
    ],
    newSims: split && !iphone
        ? [
            NewSim(
              sim: 'sim:9',
              firstAt: eat(2026, 11, 21, 16, 5),
              firstBalanceMinor: kes(9150),
            ),
          ]
        : const [],
  );
  await DriftAppSettingsRepository(db).writeJson(mpesaLinesKey, lines.toJson());
  if (split) {
    await selected.setSelected(lineSelectionId('1'), selected: true);
    if (iphone) {
      await selected.setSelected(lineSelectionId('2'), selected: true);
    }
  }

  ReviewItem? waiting;
  if (iphone) {
    final at = eat(2026, 11, 21, 13, 20);
    await db
        .into(db.reviewItems)
        .insert(
          ReviewItemsCompanion.insert(
            institutionId: mpesaInstitutionId,
            sender: 'MPESA',
            receivedAt: at,
            messageHash: 'which-line-1',
            body: const Value(
              'TKB0000001 Confirmed. Ksh300.00 paid to SUNRISE CAFE. on '
              '21/11/26 at 1:20 PM.New M-PESA balance is Ksh5,000.00. '
              'Transaction cost, Ksh0.00. Amount you can transact within the '
              'day is 499,700.00.',
            ),
            reason: whichLineReason,
          ),
        );
    waiting = await db.select(db.reviewItems).getSingle();
  }
  return SeededLines(db, iphone: iphone, waiting: waiting);
}

/// The app's providers over [seeded], in Personal.
List<Override> linesOverrides(SeededLines seeded) => [
  appDatabaseProvider.overrideWithValue(seeded.db),
  personalDatabaseProvider.overrideWithValue(seeded.db),
  clockProvider.overrideWithValue(() => linesNow),
  deviceRegionProvider.overrideWithValue('KE'),
  smsSourceProvider.overrideWithValue(
    seeded.iphone ? EmptyShortcutQueue() : FakeSmsSource(),
  ),
  ...appLockOverrides(),
];

Widget myAccounts([SeededLines? _]) => const MyAccountsSettingsScreen();

Widget homeRows([SeededLines? _]) => Scaffold(
  body: ListView(
    padding: const EdgeInsets.all(20),
    children: const [LineQuestionRows()],
  ),
);

/// [sheet] as a sheet shows it, on an otherwise empty screen.
Widget asSheet(Widget sheet) => Scaffold(
  body: Align(
    alignment: Alignment.bottomCenter,
    child: Material(child: SheetFrame(child: sheet)),
  ),
);

Widget whichLine(SeededLines seeded) =>
    asSheet(WhichLineSheet(item: seeded.waiting!));

Widget sameLine([SeededLines? _]) => asSheet(const SameLineSheet());

/// Six M-Pesa lines on one phone, as on a phone that has held six SIMs:
/// "My line" today, SIM 5 three days ago, and four old SIMs (6, 4, 3, 2),
/// split, each its own account in Personal. SIM 4 has three records. With
/// [after], the quick setup was used, SIMs 6, 4, 3 and 2 not tracked; on
/// [iphone], no SIMs: the lines are told apart by balance.
Future<SeededLines> seedManyLines({
  bool after = false,
  bool iphone = false,
}) async {
  final db = openTestDatabase();
  final selected = DriftInstitutionsRepository(db);
  await selected.setSelected(mpesaInstitutionId, selected: true);
  MpesaLine line(
    String id,
    DateTime first,
    DateTime last,
    int messages,
    int balance, {
    String? name,
  }) => MpesaLine(
    id: id,
    sims: iphone ? const {} : {'sim:$id'},
    name: name,
    firstAt: first,
    lastAt: last,
    balanceAt: last,
    messages: messages,
    balanceMinor: kes(balance),
  );
  final all = [
    line(
      '1',
      eat(2024, 2, 3),
      eat(2026, 11, 21, 10),
      412,
      12500,
      name: 'My line',
    ),
    line('2', eat(2023, 6, 15), eat(2024, 9, 9), 132, 0),
    line('3', eat(2024, 1, 4), eat(2025, 3, 14), 116, 860),
    line('4', eat(2026, 1, 11), eat(2026, 6, 2), 38, 1020),
    line('5', eat(2026, 8, 2), eat(2026, 11, 18, 9), 96, 4210),
    line('6', eat(2026, 7, 28), eat(2026, 7, 30), 3, 150),
  ];
  var lines = MpesaLines(split: true, surveyed: true, lines: all);
  if (after) lines = lines.keepTwoMostRecent();
  await DriftAppSettingsRepository(db).writeJson(mpesaLinesKey, lines.toJson());
  for (final l in all) {
    await selected.setSelected(lineSelectionId(l.id), selected: true);
    final id = await db
        .into(db.accounts)
        .insert(
          AccountsCompanion.insert(
            name: 'M-Pesa',
            type: AccountType.mpesa,
            openingDate: eat(2023, 6, 1),
            institutionId: const Value(mpesaInstitutionId),
            reference: Value(lineReference(l.id)),
          ),
        );
    if (l.id == '4') {
      for (var i = 0; i < 3; i++) {
        await db
            .into(db.transactions)
            .insert(
              TransactionsCompanion.insert(
                accountId: id,
                amountMinor: kes(100),
                direction: TransactionDirection.outflow,
                occurredAt: eat(2026, 6, 1 + i),
                source: TransactionSource.sms,
                messageHash: Value('sim4-$i'),
              ),
            );
      }
    }
  }
  return SeededLines(db, iphone: iphone);
}

Widget manyLines([SeededLines? _]) => const MpesaLinesScreen();

Widget lineSheet(String id) => asSheet(LineSheet(lineId: id));

Widget quickSetup([SeededLines? _]) => asSheet(const QuickSetupSheet());
