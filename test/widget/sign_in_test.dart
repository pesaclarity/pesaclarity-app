import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/config/flavor.dart';
import 'package:pesaclarity/src/features/auth/data/session_store.dart';
import 'package:pesaclarity/src/features/auth/domain/auth_models.dart';
import 'package:pesaclarity/src/shared/semantic_ids.dart';

import '../helpers/fake_auth.dart';
import '../helpers/test_app.dart';

Finder _field(String hint) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.hintText == hint,
);

StoredSession _signedIn({String? displayName}) => StoredSession(
  refreshToken: 'refresh-0',
  accountId: 'account-1',
  deviceId: 'device-1',
  method: SignInMethod.phone,
  contact: '+254700000000',
  displayName: displayName,
);

/// Signs in from the welcome screen with the fake server's code.
Future<void> _signInByPhone(WidgetTester tester) async {
  await tester.enterText(_field('7XX XXX XXX'), '0700000000');
  await tester.tap(find.text('Send code'));
  await tester.pumpAndSettle();
  await tester.enterText(_field('6-digit code'), '123456');
  await tester.tap(find.text('Verify'));
  await tester.pumpAndSettle();
}

/// From My accounts to Home, as [finishOnboarding] does after Get started.
Future<void> _finishMyAccounts(WidgetTester tester) async {
  await tester.tap(find.text('M-Pesa'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Scan my messages'));
  await tester.pumpAndSettle();
  await tapText(tester, 'Allow access to messages');
  await tapText(tester, 'Continue');
}

Future<void> _openProfile(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Profile'));
  await tester.pumpAndSettle();
}

/// Scrolls Profile's list until [finder] is built, then taps it.
Future<void> _scrollAndTap(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

Future<void> _scrollBackUp(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.text('Using without an account'),
    -200,
    scrollable: find.byType(Scrollable).first,
  );
}

void main() {
  testAppWidgets('welcome matches the design and keeps Get started', (
    tester,
  ) async {
    await pumpApp(tester, db: openTestDatabase());

    expect(find.text('Know what you can spend today.'), findsOneWidget);
    expect(find.text('Phone number'), findsOneWidget);
    expect(find.text('+254'), findsOneWidget);
    expect(find.text('Send code'), findsOneWidget);
    expect(find.text('Continue with Google'), findsNothing);
    expect(find.textContaining('Use without an account'), findsOneWidget);
    expect(
      find.bySemanticsIdentifier(SemanticIds.onboardingGetStarted),
      findsOneWidget,
    );
    expect(
      find.bySemanticsIdentifier(SemanticIds.titleWelcome),
      findsOneWidget,
    );

    await tester.tap(find.text('Get started'));
    await tester.pumpAndSettle();
    expect(find.text('Which accounts do you use?'), findsOneWidget);
  });

  testAppWidgets('Get started fits on a phone screen without scrolling', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1080, 2340)
      ..devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await pumpApp(tester, db: openTestDatabase(), flavor: AppFlavor.play);

    final button = tester.getRect(find.text('Get started'));
    expect(button.bottom, lessThan(2340 / 2.625));
  });

  testAppWidgets('play builds also offer Google', (tester) async {
    await pumpApp(tester, db: openTestDatabase(), flavor: AppFlavor.play);
    expect(find.text('Send code'), findsOneWidget);
    expect(find.text('or'), findsOneWidget);
    expect(find.text('Continue with Google'), findsOneWidget);
  });

  testAppWidgets('Google sign-in continues onboarding', (tester) async {
    final api = FakeAuthApi();
    final sessions = InMemorySessionStore();
    await pumpApp(
      tester,
      db: openTestDatabase(),
      flavor: AppFlavor.play,
      auth: api,
      sessions: sessions,
      google: FakeGoogleIdTokenSource(),
    );

    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle();

    expect(find.text('Which accounts do you use?'), findsOneWidget);
    expect(sessions.session?.method, SignInMethod.google);
  });

  testAppWidgets('phone sign-in with an SMS code continues onboarding', (
    tester,
  ) async {
    final api = FakeAuthApi();
    final sessions = InMemorySessionStore();
    await pumpApp(
      tester,
      db: openTestDatabase(),
      auth: api,
      sessions: sessions,
    );

    await tester.enterText(_field('7XX XXX XXX'), '0700 000 000');
    await tester.tap(find.text('Send code'));
    await tester.pumpAndSettle();

    expect(
      find.text('Enter the code sent to +254 700 000 000'),
      findsOneWidget,
    );
    await tester.enterText(_field('6-digit code'), '000000');
    await tester.tap(find.text('Verify'));
    await tester.pumpAndSettle();
    expect(
      find.text(const AuthFailure(AuthFailureKind.invalidCode).message),
      findsOneWidget,
    );

    await tester.enterText(_field('6-digit code'), '123456');
    await tester.tap(find.text('Verify'));
    await tester.pumpAndSettle();

    expect(find.text('Which accounts do you use?'), findsOneWidget);
    expect(sessions.session?.contact, '+254700000000');
  });

  testAppWidgets('a bad number shows a plain message', (tester) async {
    await pumpApp(tester, db: openTestDatabase(), auth: FakeAuthApi());

    await tester.enterText(_field('7XX XXX XXX'), '12');
    await tester.tap(find.text('Send code'));
    await tester.pumpAndSettle();

    expect(
      find.text(const AuthFailure(AuthFailureKind.invalidPhone).message),
      findsOneWidget,
    );
  });

  testAppWidgets('without a server the app explains and carries on', (
    tester,
  ) async {
    await pumpApp(tester, db: openTestDatabase());

    await tester.enterText(_field('7XX XXX XXX'), '0700000000');
    await tester.tap(find.text('Send code'));
    await tester.pumpAndSettle();

    expect(
      find.text(const AuthFailure(AuthFailureKind.notConfigured).message),
      findsOneWidget,
    );
    await finishOnboarding(tester);
    expect(find.text('How am I doing today?'), findsOneWidget);
  });

  testAppWidgets('Profile offers sign-in when using without an account', (
    tester,
  ) async {
    final api = FakeAuthApi();
    await pumpApp(tester, db: openTestDatabase(), auth: api);
    await finishOnboarding(tester);
    await _openProfile(tester);

    expect(find.text('Using without an account'), findsOneWidget);
    expect(find.text('Delete account'), findsNothing);

    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();
    await tester.enterText(_field('7XX XXX XXX'), '700000000');
    await tester.tap(find.text('Send code'));
    await tester.pumpAndSettle();
    await tester.enterText(_field('6-digit code'), '123456');
    await tester.tap(find.text('Verify'));
    await tester.pumpAndSettle();

    expect(find.text('+254 700 000 000'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Sign out'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Sign out'), findsOneWidget);
  });

  testAppWidgets('signing out from Profile', (tester) async {
    final api = FakeAuthApi();
    final sessions = InMemorySessionStore();
    await pumpApp(
      tester,
      db: openTestDatabase(),
      auth: api,
      sessions: sessions,
    );
    await _signInByPhone(tester);
    await _finishMyAccounts(tester);
    await _openProfile(tester);

    await _scrollAndTap(tester, find.text('Sign out'));

    expect(sessions.session, isNull);
    expect(api.revoked, hasLength(1));
    await _scrollBackUp(tester);
    expect(find.text('Using without an account'), findsOneWidget);
  });

  testAppWidgets('delete account asks first and explains what goes', (
    tester,
  ) async {
    final api = FakeAuthApi();
    final sessions = InMemorySessionStore();
    await pumpApp(
      tester,
      db: openTestDatabase(),
      auth: api,
      sessions: sessions,
    );
    await _signInByPhone(tester);
    await _finishMyAccounts(tester);
    await _openProfile(tester);

    await _scrollAndTap(tester, find.text('Delete account'));
    expect(find.text('Delete your account?'), findsOneWidget);
    expect(
      find.textContaining('every backup kept in the Pesa Clarity vault'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Your money data on this phone stays here'),
      findsOneWidget,
    );

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(api.accountDeleted, isFalse);

    await _scrollAndTap(tester, find.text('Delete account'));
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Delete account'),
      ),
    );
    await tester.pumpAndSettle();

    expect(api.accountDeleted, isTrue);
    expect(sessions.session, isNull);
    await _scrollBackUp(tester);
    expect(find.text('Using without an account'), findsOneWidget);
  });

  testAppWidgets('lists phones and signs another one out', (tester) async {
    final api = FakeAuthApi();
    final sessions = InMemorySessionStore();
    await pumpApp(
      tester,
      db: openTestDatabase(),
      auth: api,
      sessions: sessions,
    );
    await _signInByPhone(tester);
    api.addOtherDevice('old', 'Infinix Hot 30', DateTime.utc(2026, 9, 3, 12));
    await _finishMyAccounts(tester);
    await _openProfile(tester);

    await _scrollAndTap(tester, find.text('Signed-in phones'));
    expect(find.text('Tecno Spark 20'), findsOneWidget);
    expect(find.text('This phone'), findsOneWidget);
    expect(find.text('Infinix Hot 30'), findsOneWidget);
    expect(find.text('Last active 3 Sep 2026'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Sign out'));
    await tester.pumpAndSettle();
    expect(find.text('Sign out Infinix Hot 30?'), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.text('Sign out'),
      ),
    );
    await tester.pumpAndSettle();

    expect(api.revoked, {'old'});
    expect(find.text('Infinix Hot 30'), findsNothing);
    expect(find.text('Infinix Hot 30 is signed out'), findsOneWidget);
  });

  testAppWidgets('a saved session shows in Profile on launch', (tester) async {
    await pumpApp(
      tester,
      db: openTestDatabase(),
      auth: FakeAuthApi(),
      sessions: InMemorySessionStore(_signedIn(displayName: 'John Kamau')),
    );
    await finishOnboarding(tester);
    await _openProfile(tester);

    expect(find.text('John Kamau'), findsOneWidget);
    expect(find.text('JK'), findsOneWidget);
    expect(find.text('+254 700 000 000'), findsOneWidget);
  });
}
