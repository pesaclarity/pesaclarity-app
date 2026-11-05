import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money/money.dart';
import '../../domain/documents/invoice.dart';
import '../../domain/time/calendar.dart';
import '../database/app_database.dart';
import '../database/database_providers.dart';

/// An invoice as kept, with its lines.
class StoredInvoice {
  const StoredInvoice({
    required this.id,
    required this.number,
    required this.client,
    required this.issuedOn,
    required this.billBy,
    required this.hoursDetail,
    required this.timesheet,
    required this.withholding,
    required this.totals,
    required this.currency,
    required this.lines,
    this.dueOn,
    this.notes,
    this.saleId,
  });

  final int id;
  final String number;
  final String client;
  final CalendarDate issuedOn;
  final CalendarDate? dueOn;
  final BillBy billBy;
  final HoursDetail hoursDetail;
  final bool timesheet;
  final Withholding withholding;
  final InvoiceTotals totals;
  final String currency;
  final List<InvoiceLine> lines;
  final String? notes;
  final int? saleId;
}

/// What a new invoice holds, before it has a number.
class InvoiceDraft {
  const InvoiceDraft({
    required this.client,
    required this.issuedOn,
    required this.billBy,
    required this.hoursDetail,
    required this.withholding,
    required this.totals,
    required this.lines,
    this.dueOn,
    this.timesheet = false,
    this.notes,
    this.hourIds = const [],
  });

  final String client;
  final CalendarDate issuedOn;
  final CalendarDate? dueOn;
  final BillBy billBy;
  final HoursDetail hoursDetail;
  final bool timesheet;
  final Withholding withholding;
  final InvoiceTotals totals;
  final List<InvoiceLine> lines;
  final String? notes;

  /// The hours it bills.
  final List<int> hourIds;
}

abstract interface class InvoicesRepository {
  /// Keeps [draft] as invoice [number], marks its hours billed, and returns
  /// its id.
  Future<int> create(
    InvoiceDraft draft, {
    required String number,
    required DateTime at,
  });

  Future<void> setSale(int invoiceId, int saleId);

  /// Every invoice, newest first.
  Future<List<StoredInvoice>> all();

  Future<StoredInvoice?> byId(int id);

  /// What has been paid on each sale's credit, by sale id.
  Future<Map<int, int>> paidBySale();
}

class DriftInvoicesRepository implements InvoicesRepository {
  DriftInvoicesRepository(this._db);

  final AppDatabase _db;

  T _enum<T extends Enum>(List<T> values, String name, T fallback) =>
      values.where((v) => v.name == name).firstOrNull ?? fallback;

  StoredInvoice _invoice(InvoiceRecord r, List<InvoiceLineRecord> lines) =>
      StoredInvoice(
        id: r.id,
        number: r.number,
        client: r.client,
        issuedOn: CalendarDate.local(r.issuedOn),
        dueOn: r.dueOn == null ? null : CalendarDate.local(r.dueOn!),
        billBy: _enum(BillBy.values, r.billBy, BillBy.hours),
        hoursDetail: _enum(
          HoursDetail.values,
          r.hoursDetail,
          HoursDetail.total,
        ),
        timesheet: r.timesheet,
        withholding: _enum(Withholding.values, r.withholding, Withholding.none),
        totals: InvoiceTotals(
          feesMinor: r.feesMinor,
          feesShownMinor: r.feesShownMinor,
          costsMinor: r.costsMinor,
          discountMinor: r.discountMinor,
          vatMinor: r.vatMinor,
          withheldMinor: r.withheldMinor,
        ),
        currency: r.currency,
        notes: r.notes,
        saleId: r.saleId,
        lines: [
          for (final l in lines)
            InvoiceLine(
              kind: _enum(InvoiceLineKind.values, l.kind, InvoiceLineKind.fees),
              name: l.name,
              detail: l.detail,
              amountMinor: l.amountMinor,
              quantityMilli: l.quantityMilli,
              unitMinor: l.unitMinor,
            ),
        ],
      );

  @override
  Future<int> create(
    InvoiceDraft d, {
    required String number,
    required DateTime at,
  }) => _db.transaction(() async {
    final t = d.totals;
    final id = await _db
        .into(_db.invoices)
        .insert(
          InvoicesCompanion.insert(
            number: number,
            client: d.client.trim(),
            issuedOn: d.issuedOn.startInstant,
            dueOn: Value(d.dueOn?.startInstant),
            billBy: d.billBy.name,
            hoursDetail: d.hoursDetail.name,
            timesheet: Value(d.timesheet),
            withholding: d.withholding.name,
            feesMinor: t.feesMinor,
            feesShownMinor: t.feesShownMinor,
            costsMinor: Value(t.costsMinor),
            discountMinor: Value(t.discountMinor),
            vatMinor: Value(t.vatMinor),
            withheldMinor: Value(t.withheldMinor),
            currency: Value(BaseCurrency.code),
            notes: Value(d.notes),
            createdAt: at,
          ),
        );
    for (final l in d.lines) {
      await _db
          .into(_db.invoiceLines)
          .insert(
            InvoiceLinesCompanion.insert(
              invoiceId: id,
              kind: l.kind.name,
              name: l.name,
              detail: Value(l.detail),
              amountMinor: l.amountMinor,
              quantityMilli: Value(l.quantityMilli),
              unitMinor: Value(l.unitMinor),
            ),
          );
    }
    if (d.hourIds.isNotEmpty) {
      await (_db.update(_db.hourEntries)..where((h) => h.id.isIn(d.hourIds)))
          .write(HourEntriesCompanion(invoiceId: Value(id)));
    }
    return id;
  });

  @override
  Future<void> setSale(int invoiceId, int saleId) =>
      (_db.update(_db.invoices)..where((i) => i.id.equals(invoiceId))).write(
        InvoicesCompanion(saleId: Value(saleId)),
      );

  Future<Map<int, List<InvoiceLineRecord>>> _lines() async {
    final out = <int, List<InvoiceLineRecord>>{};
    for (final l in await (_db.select(
      _db.invoiceLines,
    )..orderBy([(l) => OrderingTerm.asc(l.id)])).get()) {
      out.putIfAbsent(l.invoiceId, () => []).add(l);
    }
    return out;
  }

  @override
  Future<List<StoredInvoice>> all() async {
    final lines = await _lines();
    return [
      for (final r in await (_db.select(
        _db.invoices,
      )..orderBy([(i) => OrderingTerm.desc(i.id)])).get())
        _invoice(r, lines[r.id] ?? const []),
    ];
  }

  @override
  Future<Map<int, int>> paidBySale() async {
    final credits = await (_db.select(
      _db.salePayments,
    )..where((p) => p.lentLoanId.isNotNull())).get();
    final paid = <int, int>{};
    for (final p in await (_db.select(
      _db.loanPayments,
    )..where((p) => p.lentLoanId.isNotNull())).get()) {
      paid[p.lentLoanId!] = (paid[p.lentLoanId!] ?? 0) + p.amountMinor;
    }
    final out = <int, int>{};
    for (final c in credits) {
      out[c.saleId] = (out[c.saleId] ?? 0) + (paid[c.lentLoanId!] ?? 0);
    }
    return out;
  }

  @override
  Future<StoredInvoice?> byId(int id) async {
    final r = await (_db.select(
      _db.invoices,
    )..where((i) => i.id.equals(id))).getSingleOrNull();
    if (r == null) return null;
    final lines = await (_db.select(
      _db.invoiceLines,
    )..where((l) => l.invoiceId.equals(id))).get();
    return _invoice(r, lines);
  }
}

final invoicesRepositoryProvider = Provider<InvoicesRepository>(
  (ref) => DriftInvoicesRepository(ref.watch(appDatabaseProvider)),
);
