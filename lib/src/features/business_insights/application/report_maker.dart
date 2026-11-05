import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/time/clock.dart';
import '../../../data/repositories/accounts_repository.dart';
import '../../../data/repositories/app_settings_repository.dart';
import '../../../data/repositories/categories_repository.dart';
import '../../../data/repositories/documents_repository.dart';
import '../../../domain/books/business_report.dart';
import '../../../domain/books/report_setup.dart';
import '../../../domain/time/calendar.dart';
import '../../documents/application/document_providers.dart';
import '../../insights/application/report_sharer.dart';
import '../../spaces/application/spaces_providers.dart';
import '../../tax/application/tax_providers.dart';
import '../presentation/report_preview_screen.dart';
import 'business_report_pdf.dart';
import 'business_report_providers.dart';
import 'report_content.dart';

/// The open space's report cover and saved reports.
class ReportSettingsController extends AsyncNotifier<ReportSettings> {
  static const settingsKey = 'reports.settings';

  @override
  Future<ReportSettings> build() async => ReportSettings.fromJson(
    await ref.watch(appSettingsRepositoryProvider).readJson(settingsKey),
  );

  Future<void> save(ReportSettings next) async {
    await ref
        .read(appSettingsRepositoryProvider)
        .writeJson(settingsKey, next.toJson());
    state = AsyncData(next);
  }
}

final reportSettingsProvider =
    AsyncNotifierProvider<ReportSettingsController, ReportSettings>(
      ReportSettingsController.new,
    );

/// Shows a finished PDF before it is shared; tests swap in a stand-in.
typedef ReportPreviewer = Future<void> Function(
  BuildContext context,
  ReportDocument doc,
  Uint8List pdf,
);

final reportPreviewerProvider = Provider<ReportPreviewer>(
  (ref) =>
      (context, doc, pdf) => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ReportPreviewScreen(doc: doc, pdf: pdf),
        ),
      ),
);

/// Makes and shares the open business's reports.
class ReportMaker {
  ReportMaker(this._ref);

  final Ref _ref;

  /// The report for [period] with [sections], titled [title].
  Future<ReportDocument> make({
    required ReportPeriod period,
    required Set<ReportSection> sections,
    String title = 'Business report',
    ReportDetail detail = ReportDetail.everyEntry,
  }) async {
    final report = await _ref.read(businessReportProvider(period).future);
    final cashBook = sections.contains(ReportSection.cashBook)
        ? await _ref.read(reportCashBookProvider(period).future)
        : null;
    final accounts = await _ref
        .read(accountsRepositoryProvider)
        .watchAll()
        .first;
    final categories = await _ref
        .read(categoriesRepositoryProvider)
        .watchAll()
        .first;
    final tax = sections.contains(ReportSection.tax)
        ? await _ref.read(taxViewProvider.future)
        : null;
    final settings = await _ref.read(reportSettingsProvider.future);
    final space = _ref.read(activeSpaceProvider).name;
    return reportDocument(
      report: report,
      sections: sections,
      title: title,
      business: settings.cover.business ?? space,
      coverLine: settings.cover.line(space),
      today: CalendarDate.local(_ref.read(clockProvider)()),
      cashBook: cashBook,
      tax: tax,
      detail: detail,
      logo: await _logo(),
      accountNames: {for (final a in accounts) a.id: a.name},
      categoryNames: {for (final c in categories) c.id: c.name},
    );
  }

  Future<Uint8List?> _logo() async {
    final logo = await _ref.read(
      documentFileProvider(DocumentFileKind.logo).future,
    );
    return logo != null && logo.isImage ? logo.bytes : null;
  }

  Future<Uint8List> pdf(ReportDocument doc) =>
      _ref.read(businessReportRendererProvider)(doc);

  Future<void> sharePdf(ReportDocument doc) async => _ref
      .read(reportSharerProvider)
      .sharePdf(
        await pdf(doc),
        fileName: doc.fileName('pdf'),
        subject: '${doc.title}, ${doc.periodLine}',
      );

  Future<void> shareCsv(ReportDocument doc) => _ref
      .read(reportSharerProvider)
      .shareFile(
        Uint8List.fromList(utf8.encode(reportCsv(doc))),
        fileName: doc.fileName('csv'),
        mimeType: 'text/csv',
        subject: '${doc.title}, ${doc.periodLine}',
      );
}

final reportMakerProvider = Provider<ReportMaker>(ReportMaker.new);
