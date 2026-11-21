import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/features/auth/application/auth_controller.dart';
import 'package:pesaclarity/src/features/auth/data/auth_api.dart';
import 'package:pesaclarity/src/features/auth/data/session_store.dart';
import 'package:pesaclarity/src/features/auth/domain/auth_models.dart';
import 'package:pesaclarity/src/features/auth/presentation/devices_screen.dart';
import 'package:pesaclarity/src/features/auth/presentation/sign_in_panel.dart';
import 'package:pesaclarity/src/shared/widgets/states.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

import '../../helpers/fake_auth.dart';

/// A server that cannot be reached: every call fails as offline.
class _OfflineAuthApi implements AuthApi {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      Future<Never>.error(const AuthFailure(AuthFailureKind.network));
}

const _session = StoredSession(
  refreshToken: 'refresh-made-up-0001',
  accountId: 'account-test-1',
  deviceId: 'device-test-1',
  method: SignInMethod.email,
  contact: 'wanjiru@example.com',
);

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  StoredSession? session,
}) async {
  final container = ProviderContainer(
    overrides: [
      authApiProvider.overrideWithValue(_OfflineAuthApi()),
      sessionStoreProvider.overrideWithValue(InMemorySessionStore(session)),
      deviceNameSourceProvider.overrideWithValue(const FakeDeviceNameSource()),
    ],
  );
  addTearDown(container.dispose);
  // Signed in from a previous launch, as when the screen opens.
  await tester.runAsync(() => container.read(authControllerProvider.future));
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: AppTheme.light, home: child),
    ),
  );
}

void main() {
  testWidgets('signing in offline says it needs a connection', (tester) async {
    await _pump(tester, Scaffold(body: SignInPanel(onSignedIn: () {})));
    await tester.enterText(find.byType(TextField), 'wanjiru@example.com');
    await tester.tap(find.text('Send code'));
    await tester.pumpAndSettle();

    expect(
      find.text(
        'Signing in needs a connection. Everything else works offline.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('Signed-in phones offline says the list needs a connection, '
      'never anything about signing in', (tester) async {
    await _pump(tester, const DevicesScreen(), session: _session);
    await tester.pumpAndSettle();

    expect(find.text('This list needs a connection.'), findsOneWidget);
    expect(find.widgetWithText(ErrorView, 'Try again'), findsOneWidget);
    expect(find.textContaining('Sign'), findsOneWidget); // the title only
    expect(find.text('Signed-in phones'), findsOneWidget);
  });
}
