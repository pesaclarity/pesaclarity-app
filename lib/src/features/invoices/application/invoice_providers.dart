import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/time/clock.dart';
import '../../../data/repositories/accounts_repository.dart';
import '../../../data/repositories/app_settings_repository.dart';
import '../../../data/repositories/documents_repository.dart';
import '../../../data/repositories/hours_repository.dart';
import '../../../data/repositories/invoices_repository.dart';
import '../../../data/repositories/quick_records_repository.dart';
import '../../../data/repositories/sales_repository.dart';
import '../../../data/repositories/tax_repository.dart';
import '../../../data/repositories/transactions_repository.dart';
import '../../../domain/documents/invoice.dart';
import '../../../domain/enums.dart';
import '../../../domain/hours/hours.dart';
import '../../../domain/spaces/space.dart';
import '../../../domain/time/calendar.dart';
import '../../documents/application/document_providers.dart';
import '../../sales/application/sales_providers.dart';
import '../../spaces/application/spaces_providers.dart';

/// An invoice with what has been paid on it.
class InvoiceView {
  const InvoiceView(
    this.invoice, {
    required this.paidMinor,
    required this.status,
    this.attached = 0,
  });

  final StoredInvoice invoice;
  final int paidMinor;
  final InvoiceStatus status;

  /// How many documents go with it.
  final int attached;

  int get leftMinor {
    final left = invoice.totals.toPayMinor - paidMinor;
    return left < 0 ? 0 : left;
  }
}

/// Every invoice, newest first, with its status today.
final invoicesProvider = FutureProvider<List<InvoiceView>>((ref) async {
  ref.watch(ledgerChangesProvider);
  final repo = ref.watch(invoicesRepositoryProvider);
  final today = CalendarDate.local(ref.watch(clockProvider)());
  final paid = await repo.paidBySale();
  final attached = await ref
      .watch(documentsRepositoryProvider)
      .attachmentCounts();
  return [
    for (final i in await repo.all())
      () {
        // What the client pays is the invoice less what they withhold; the
        // withheld share is paid as tax, so it counts as paid here too.
        final onSale = paid[i.saleId] ?? 0;
        final paidMinor = onSale >= i.totals.totalMinor
            ? i.totals.toPayMinor
            : onSale;
        return InvoiceView(
          i,
          paidMinor: paidMinor,
          attached: attached[i.id] ?? 0,
          status: invoiceStatus(
            toPayMinor: i.totals.toPayMinor,
            paidMinor: paidMinor,
            dueOn: i.dueOn,
            today: today,
          ),
        );
      }(),
  ];
});

/// How each client handles withholding tax, remembered from invoices.
class ClientWithholdingController
    extends AsyncNotifier<Map<String, Withholding>> {
  static const settingsKey = 'invoices.clientWithholding';

  @override
  Future<Map<String, Withholding>> build() async {
    final json = await ref
        .watch(appSettingsRepositoryProvider)
        .readJson(settingsKey);
    return {
      for (final MapEntry(:key, :value) in (json ?? const {}).entries)
        key: ?Withholding.values.where((w) => w.name == value).firstOrNull,
    };
  }

  Future<void> remember(String client, Withholding w) async {
    final next = {...?state.value, client.trim().toLowerCase(): w};
    await ref.read(appSettingsRepositoryProvider).writeJson(settingsKey, {
      for (final MapEntry(:key, :value) in next.entries) key: value.name,
    });
    state = AsyncData(next);
  }
}

final clientWithholdingProvider =
    AsyncNotifierProvider<
      ClientWithholdingController,
      Map<String, Withholding>
    >(ClientWithholdingController.new);

/// Makes invoices and settles them when a payment message matches.
class InvoicesController {
  InvoicesController(this._ref);

  final Ref _ref;
  Future<void> _matching = Future.value();

  /// Keeps [draft] as the next numbered invoice, with a credit sale for
  /// what the client owes, and returns its id.
  Future<int> create(
    InvoiceDraft draft, {
    List<PickedDocument> attachments = const [],
  }) async {
    final settings = await _ref.read(documentSettingsProvider.future);
    final space = _ref.read(activeSpaceProvider).name;
    final number = settings.invoiceLabel(space, settings.nextInvoice);
    final now = _ref.read(clockProvider)();
    final repo = _ref.read(invoicesRepositoryProvider);
    final id = await repo.create(draft, number: number, at: now);
    await _ref
        .read(documentSettingsProvider.notifier)
        .save(settings.copyWith(nextInvoice: settings.nextInvoice + 1));
    final sale = await _ref
        .read(salesControllerProvider)
        .sell(
          [SalePart(SalePaymentMethod.credit, draft.totals.totalMinor)],
          note: 'Invoice $number',
          credit: CreditTerms(customer: draft.client, dueDate: draft.dueOn),
        );
    await repo.setSale(id, sale.saleId);
    final files = _ref.read(documentsRepositoryProvider);
    for (final a in attachments) {
      await files.attach(
        id,
        name: a.name,
        mimeType: a.mimeType,
        bytes: a.bytes,
        at: now,
      );
    }
    return id;
  }

  /// The hours [invoice] billed, in order.
  Future<List<HourEntry>> hoursOf(StoredInvoice invoice) async {
    final all = await _ref
        .read(hoursRepositoryProvider)
        .between(CalendarDate(1970, 1, 1), CalendarDate(2200, 1, 1));
    return [
      for (final e in all)
        if (e.invoiceId == invoice.id) e,
    ];
  }

  /// Settles open invoices from payment messages: money in that is exactly
  /// what is left to pay, from a sender whose name matches the client.
  Future<int> matchPayments() {
    final run = _matching.then((_) => _match());
    _matching = run.then<Object?>((_) => null, onError: (_) => null);
    return run;
  }

  Future<int> _match() async {
    final open = [
      for (final v in await _ref.read(invoicesProvider.future))
        if (v.status != InvoiceStatus.paid && v.paidMinor == 0) v,
    ];
    if (open.isEmpty) return 0;
    final from = open
        .map((v) => v.invoice.issuedOn)
        .reduce((a, b) => a.isBefore(b) ? a : b);
    final entries = await _ref
        .read(transactionsRepositoryProvider)
        .ledgerEntries(
          from: from.startInstant,
          to: _ref.read(clockProvider)().add(const Duration(days: 1)),
        );
    final types = {
      for (final a in await _ref.read(accountsRepositoryProvider).openings())
        a.id: a.type,
    };
    final linked = {
      ...await _ref.read(salesRepositoryProvider).linkedTransactions(),
      ...await _ref.read(quickRecordsRepositoryProvider).linkedTransactions(),
    };
    final used = <int>{};
    var settled = 0;
    for (final v in open.reversed) {
      final i = v.invoice;
      final match = entries
          .where(
            (e) =>
                e.isInflow &&
                !linked.contains(e.id) &&
                !used.contains(e.id) &&
                (types[e.accountId] == AccountType.mpesa ||
                    types[e.accountId] == AccountType.bank) &&
                !e.occurredAt.isBefore(i.issuedOn.startInstant) &&
                e.amountMinor == i.totals.toPayMinor &&
                _sameClient(e.payeeName ?? e.counterpartyName, i.client),
          )
          .firstOrNull;
      if (match == null) continue;
      used.add(match.id);
      await _ref.read(salesControllerProvider).customerPaidBy(match, i.client);
      if (i.totals.withheldMinor > 0) {
        await _ref
            .read(taxRepositoryProvider)
            .withhold(
              person: i.client,
              amountMinor: i.totals.withheldMinor,
              at: match.occurredAt,
            );
      }
      settled++;
    }
    return settled;
  }
}

/// Whether [sender] names [client]: their first words agree.
bool _sameClient(String? sender, String client) {
  if (sender == null) return false;
  String first(String s) => s.trim().toLowerCase().split(RegExp(r'\s+')).first;
  return first(sender) == first(client);
}

final invoicesControllerProvider = Provider<InvoicesController>(
  InvoicesController.new,
);

/// Settles invoices as payment messages come in; the app shell keeps it.
final invoiceMatcherProvider = Provider<void>((ref) {
  if (ref.watch(activeSpaceProvider).kind != SpaceKind.business) return;
  ref.listen(ledgerChangesProvider, (_, _) async {
    try {
      await ref.read(invoicesControllerProvider).matchPayments();
    } on Object catch (error) {
      if (kDebugMode) debugPrint('Matching invoices failed: $error');
    }
  }, fireImmediately: true);
});
