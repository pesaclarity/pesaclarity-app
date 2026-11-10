import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/spaces/space.dart';
import '../../../routing/app_routes.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../activity/presentation/add_transaction_sheet.dart';
import '../../sales/presentation/records_sheets.dart';
import '../../spaces/application/spaces_providers.dart';
import '../../statements/data/pdf_text_extractor.dart';

/// Add a transaction or import a statement; a business can also pay its
/// owner. Without a PDF engine (the F-Droid build) there is no import.
Future<void> showAddMenu(BuildContext context, {bool business = false}) async {
  final canImport = ProviderScope.containerOf(
    context,
    listen: false,
  ).read(statementImportAvailableProvider);
  final choice = await showAppSheet<_AddChoice>(
    context: context,
    builder: (context) => SheetBody(
      title: business ? 'More ways to record' : 'Add or import',
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.add_circle_outline),
          title: const Text('Add a transaction'),
          subtitle: const Text('Cash or anything a message missed'),
          onTap: () => Navigator.pop(context, _AddChoice.manual),
        ),
        if (business)
          ListTile(
            key: const Key('add-pay-yourself'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.person_outline),
            title: const Text('Pay yourself'),
            subtitle: const Text('Move money to Personal as income'),
            onTap: () => Navigator.pop(context, _AddChoice.payYourself),
          ),
        if (canImport)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.upload_file_outlined),
            title: const Text('Import a statement'),
            subtitle: const Text('M-Pesa or bank PDF, for older history'),
            onTap: () => Navigator.pop(context, _AddChoice.import),
          ),
      ],
    ),
  );
  if (!context.mounted) return;
  switch (choice) {
    case _AddChoice.manual:
      await showAddTransactionSheet(context);
    case _AddChoice.import:
      context.go(AppRoutes.importStatement);
    case _AddChoice.payYourself:
      await showPayYourselfSheet(context);
    case null:
      break;
  }
}

enum _AddChoice { manual, import, payYourself }

/// The one round button, beside the tab bar on every tab: Sell in a
/// business, add a transaction (or import a statement) everywhere else.
/// Solid red with a white +, so it reads as the main action.
class MainAddButton extends ConsumerWidget {
  const MainAddButton({super.key});

  static const size = 56.0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final business = ref.watch(activeSpaceProvider).kind == SpaceKind.business;
    final canImport = ref.watch(statementImportAvailableProvider);
    // Without a PDF engine (the F-Droid build) there is only one choice.
    final tooltip = business
        ? 'Sell'
        : canImport
        ? 'Add or import'
        : 'Add a transaction';
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        excludeSemantics: true,
        child: Material(
          key: const Key('home-add'),
          color: scheme.primary,
          shape: const CircleBorder(),
          elevation: 3,
          shadowColor: scheme.primary.withValues(alpha: 0.4),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => business
                ? context.push(AppRoutes.sell)
                : canImport
                ? showAddMenu(context)
                : showAddTransactionSheet(context),
            child: SizedBox.square(
              dimension: size,
              child: Icon(Icons.add, size: 28, color: scheme.onPrimary),
            ),
          ),
        ),
      ),
    );
  }
}
