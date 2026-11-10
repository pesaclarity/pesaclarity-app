import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/features/people/presentation/reminder_messages_screen.dart';
import 'package:pesaclarity/src/features/reminders/application/business_reminders.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

import '../../helpers/test_app.dart';

void main() {
  testAppWidgets('messages can be edited and added, with the till', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final db = openTestDatabase();
    final c = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    addTearDown(c.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: c,
        child: MaterialApp(
          theme: AppTheme.light,
          home: const ReminderMessagesScreen(),
        ),
      ),
    );
    await settleFrames(tester);
    expect(find.text('Friendly'), findsOneWidget);
    expect(find.text('Due today'), findsOneWidget);
    expect(find.text("It's been a while"), findsOneWidget);

    await tester.tap(find.text('Due today'));
    await settleFrames(tester);
    await tester.enterText(
      find.byKey(const Key('message-text')),
      'Hi {name}, KES {amount} today please. Thank you!',
    );
    await tester.tap(find.byKey(const Key('message-save')));
    await settleFrames(tester);

    await tester.tap(find.byKey(const Key('add-message')));
    await settleFrames(tester);
    await tester.enterText(find.byKey(const Key('message-name')), 'Short');
    await tester.enterText(
      find.byKey(const Key('message-text')),
      'Hi {name}, KES {amount} please.',
    );
    await tester.tap(find.byKey(const Key('message-save')));
    await settleFrames(tester);

    await tester.enterText(find.byKey(const Key('till')), '000000');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await settleFrames(tester);

    final setup = await tester.runAsync(
      () => c.read(reminderSetupProvider.future),
    );
    expect(setup!.templates, hasLength(4));
    expect(
      setup.templates.firstWhere((t) => t.id == 'due_today').text,
      'Hi {name}, KES {amount} today please. Thank you!',
    );
    expect(setup.templates.last.name, 'Short');
    expect(setup.till, '000000');

    // One action a row: Delete is in the message's own dialog.
    expect(find.byTooltip('Delete Short'), findsNothing);
    await tester.tap(find.text('Short'));
    await settleFrames(tester);
    await tester.tap(find.byKey(const Key('message-delete')));
    await settleFrames(tester);
    expect(find.text('Delete Short?'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await settleFrames(tester);
    final after = await tester.runAsync(
      () => c.read(reminderSetupProvider.future),
    );
    expect(after!.templates, hasLength(3));
    expect(find.text('Short'), findsNothing);
  });
}
