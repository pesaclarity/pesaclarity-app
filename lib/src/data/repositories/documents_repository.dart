import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/documents/receipt.dart';
import '../database/app_database.dart';
import '../database/database_providers.dart';

/// Kinds of file kept for documents.
abstract final class DocumentFileKind {
  static const logo = 'logo';
  static const mpesaQr = 'mpesaQr';
  static const attachment = 'attachment';
}

/// A picture or document kept with the business.
class StoredFile {
  const StoredFile({
    required this.id,
    required this.kind,
    required this.name,
    required this.mimeType,
    required this.bytes,
  });

  final int id;
  final String kind;
  final String name;
  final String mimeType;
  final Uint8List bytes;

  bool get isImage => mimeType.startsWith('image/');
}

/// A sale as its receipt needs it.
class SaleForReceipt {
  const SaleForReceipt({
    required this.id,
    required this.soldAt,
    required this.totalMinor,
    required this.currency,
    required this.lines,
    required this.payments,
    this.receiptNo,
    this.customer,
  });

  final int id;
  final DateTime soldAt;
  final int totalMinor;
  final String currency;
  final List<ReceiptLine> lines;
  final List<ReceiptPayment> payments;
  final String? receiptNo;
  final String? customer;
}

/// Files kept for receipts and invoices, and sales as receipts show them.
abstract interface class DocumentsRepository {
  /// The newest file of [kind], such as the logo.
  Future<StoredFile?> file(String kind);

  /// Keeps [bytes] as the one file of [kind], replacing any before.
  Future<int> putFile(
    String kind, {
    required String name,
    required String mimeType,
    required Uint8List bytes,
    required DateTime at,
  });

  Future<void> removeFile(String kind);

  /// Sale [saleId] with its lines and payments; null if it is gone.
  Future<SaleForReceipt?> sale(int saleId);

  /// Gives sale [saleId] its receipt [number].
  Future<void> setReceiptNo(int saleId, String number);

  /// The sale that transaction [transactionId] paid, if any.
  Future<int?> saleOf(int transactionId);

  /// Keeps [bytes] attached to invoice [invoiceId], after those already
  /// there.
  Future<int> attach(
    int invoiceId, {
    required String name,
    required String mimeType,
    required Uint8List bytes,
    required DateTime at,
  });

  /// Invoice [invoiceId]'s attachments, in order.
  Future<List<StoredFile>> attachments(int invoiceId);

  /// How many attachments each invoice has, by invoice id.
  Future<Map<int, int>> attachmentCounts();
}

class DriftDocumentsRepository implements DocumentsRepository {
  DriftDocumentsRepository(this._db);

  final AppDatabase _db;

  StoredFile _file(DocumentFileRecord r) => StoredFile(
    id: r.id,
    kind: r.kind,
    name: r.name,
    mimeType: r.mimeType,
    bytes: r.bytes,
  );

  @override
  Future<StoredFile?> file(String kind) async {
    final row =
        await (_db.select(_db.documentFiles)
              ..where((f) => f.kind.equals(kind))
              ..orderBy([(f) => OrderingTerm.desc(f.id)])
              ..limit(1))
            .getSingleOrNull();
    return row == null ? null : _file(row);
  }

  @override
  Future<int> putFile(
    String kind, {
    required String name,
    required String mimeType,
    required Uint8List bytes,
    required DateTime at,
  }) => _db.transaction(() async {
    await removeFile(kind);
    return _db
        .into(_db.documentFiles)
        .insert(
          DocumentFilesCompanion.insert(
            kind: kind,
            name: name,
            mimeType: mimeType,
            bytes: bytes,
            addedAt: at,
          ),
        );
  });

  @override
  Future<void> removeFile(String kind) =>
      (_db.delete(_db.documentFiles)..where((f) => f.kind.equals(kind))).go();

  @override
  Future<SaleForReceipt?> sale(int saleId) async {
    final sale = await (_db.select(
      _db.sales,
    )..where((s) => s.id.equals(saleId))).getSingleOrNull();
    if (sale == null) return null;
    final lineRows = await (_db.select(_db.saleLines).join([
      leftOuterJoin(_db.items, _db.items.id.equalsExp(_db.saleLines.itemId)),
    ])..where(_db.saleLines.saleId.equals(saleId))).get();
    final lines = [
      for (final r in lineRows)
        ReceiptLine(
          name: r.readTable(_db.saleLines).name,
          totalMinor: r.readTable(_db.saleLines).totalMinor,
          quantityMilli: r.readTable(_db.saleLines).quantityMilli,
          // A tot or a crate is named in the line itself.
          unit: r.readTable(_db.saleLines).measureId == null
              ? r.readTableOrNull(_db.items)?.unit
              : null,
        ),
    ];
    final payRows = await (_db.select(_db.salePayments).join([
      leftOuterJoin(
        _db.transactions,
        _db.transactions.id.equalsExp(_db.salePayments.transactionId),
      ),
      leftOuterJoin(
        _db.lentLoans,
        _db.lentLoans.id.equalsExp(_db.salePayments.lentLoanId),
      ),
    ])..where(_db.salePayments.saleId.equals(saleId))).get();
    String? customer;
    final payments = <ReceiptPayment>[];
    for (final r in payRows) {
      final p = r.readTable(_db.salePayments);
      final t = r.readTableOrNull(_db.transactions);
      customer ??=
          r.readTableOrNull(_db.lentLoans)?.person ?? t?.counterpartyName;
      payments.add(
        ReceiptPayment(
          method: p.method,
          amountMinor: p.amountMinor,
          code: t?.receiptNo,
        ),
      );
    }
    return SaleForReceipt(
      id: sale.id,
      soldAt: sale.soldAt,
      totalMinor: sale.totalMinor,
      currency: sale.currency,
      lines: lines.isEmpty
          ? [
              ReceiptLine(
                name: sale.note ?? 'Sale',
                totalMinor: sale.totalMinor,
              ),
            ]
          : lines,
      payments: payments,
      receiptNo: sale.receiptNo,
      customer: customer,
    );
  }

  @override
  Future<int> attach(
    int invoiceId, {
    required String name,
    required String mimeType,
    required Uint8List bytes,
    required DateTime at,
  }) async {
    final count = (await attachments(invoiceId)).length;
    return _db
        .into(_db.documentFiles)
        .insert(
          DocumentFilesCompanion.insert(
            kind: DocumentFileKind.attachment,
            name: name,
            mimeType: mimeType,
            bytes: bytes,
            addedAt: at,
            invoiceId: Value(invoiceId),
            position: Value(count),
          ),
        );
  }

  @override
  Future<List<StoredFile>> attachments(int invoiceId) async => [
    for (final r
        in await (_db.select(_db.documentFiles)
              ..where(
                (f) =>
                    f.kind.equals(DocumentFileKind.attachment) &
                    f.invoiceId.equals(invoiceId),
              )
              ..orderBy([(f) => OrderingTerm.asc(f.position)]))
            .get())
      _file(r),
  ];

  @override
  Future<Map<int, int>> attachmentCounts() async {
    final out = <int, int>{};
    for (final r
        in await (_db.select(_db.documentFiles)..where(
              (f) =>
                  f.kind.equals(DocumentFileKind.attachment) &
                  f.invoiceId.isNotNull(),
            ))
            .get()) {
      out[r.invoiceId!] = (out[r.invoiceId!] ?? 0) + 1;
    }
    return out;
  }

  @override
  Future<int?> saleOf(int transactionId) async =>
      (await (_db.select(_db.salePayments)
                ..where((p) => p.transactionId.equals(transactionId))
                ..limit(1))
              .getSingleOrNull())
          ?.saleId;

  @override
  Future<void> setReceiptNo(int saleId, String number) =>
      (_db.update(_db.sales)..where((s) => s.id.equals(saleId))).write(
        SalesCompanion(receiptNo: Value(number)),
      );
}

final documentsRepositoryProvider = Provider<DocumentsRepository>(
  (ref) => DriftDocumentsRepository(ref.watch(appDatabaseProvider)),
);
