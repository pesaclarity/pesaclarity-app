import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/domain/firefly/firefly_server.dart';
import 'package:pesaclarity/src/features/firefly/application/firefly_service.dart';
import 'package:pesaclarity/src/features/firefly/application/firefly_settings.dart';
import 'package:pesaclarity/src/features/firefly/presentation/firefly_labels.dart';
import 'package:pesaclarity/src/features/firefly/presentation/firefly_screen.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

import '../../helpers/fake_firefly_service.dart';

final _now = DateTime.utc(2026, 11, 21, 6, 41);
const _host = 'firefly.example.home';

/// The host as the screen draws it: free to wrap at its dots.
final _shown = _host.replaceAll('.', '.\u200B');

FireflySettings _on({FireflyProblem? problem, int minutesAgo = 2}) =>
    FireflySettings(
      address: 'https://$_host',
      on: true,
      lastSentAt: _now.subtract(Duration(minutes: minutesAgo)),
      problem: problem,
      version: '6.7.9',
    );

void main() {
  late FakeFireflyService service;

  Future<void> pump(
    WidgetTester tester,
    FakeFireflyService Function(Ref) make,
  ) async {
    // Tall enough to build the whole list.
    tester.view.physicalSize = const Size(1170, 6000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          fakeFireflyService((ref) => service = make(ref)),
          clockProvider.overrideWithValue(() => _now),
        ],
        child: MaterialApp(theme: AppTheme.light, home: const FireflyScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('setting up: check, choose, start', (tester) async {
    await pump(tester, FakeFireflyService.new);
    expect(find.text('Your server'.toUpperCase()), findsOneWidget);
    expect(find.text('Server address'), findsOneWidget);
    expect(find.text('Personal access token'), findsOneWidget);
    expect(find.textContaining('Remote access and tokens'), findsOneWidget);
    expect(find.text('Green Basket Grocers'), findsOneWidget);
    expect(find.text('Tagged "Green Basket Grocers"'), findsOneWidget);
    expect(find.text('1 Jan 2026'), findsOneWidget);
    expect(
      find.text(
        '2,316 transactions to send. If you close the app, it carries on '
        'next time.',
      ),
      findsOneWidget,
    );
    // Nothing starts before the connection works.
    final start = find.widgetWithText(FilledButton, 'Start sending');
    expect(tester.widget<FilledButton>(start).onPressed, isNull);

    await tester.enterText(
      find.byKey(const Key('firefly-address')),
      'https://$_host',
    );
    await tester.enterText(find.byKey(const Key('firefly-token')), 'made-up');
    // The token shows only as dots until asked.
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('firefly-token')))
          .obscureText,
      isTrue,
    );
    await tester.tap(find.byKey(const Key('firefly-check')));
    await tester.pumpAndSettle();
    expect(find.text('Connected to Firefly III 6.7.9.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('firefly-space-shop')));
    await tester.pumpAndSettle();
    expect(find.textContaining('1,158 transactions'), findsOneWidget);
    await tester.ensureVisible(start);
    await tester.tap(start);
    await tester.pumpAndSettle();
    expect(service.calls, contains('start personal FireflySendFrom.thisYear'));
    expect(find.text('Changes waiting'), findsOneWidget);
  });

  testWidgets('a certificate the phone does not know asks once', (
    tester,
  ) async {
    const sha =
        '3FA9127CE05B44D19A6E02BB71C83DF0582AE4169C07B36DA1FE20854CD9E37A';
    await pump(
      tester,
      (ref) => FakeFireflyService(
        ref,
        checks: const [
          FireflyAskTrust(host: _host, sha256: sha),
          FireflyConnected('6.7.9'),
        ],
      ),
    );
    await tester.enterText(
      find.byKey(const Key('firefly-address')),
      'https://$_host',
    );
    await tester.tap(find.byKey(const Key('firefly-check')));
    await tester.pumpAndSettle();
    expect(find.text('Trust this certificate?'), findsOneWidget);
    expect(find.text(spacedFingerprint(sha)), findsOneWidget);
    expect(
      find.text(
        'Only for this server. If the certificate changes, you are asked '
        'again.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('firefly-trust')));
    await tester.pumpAndSettle();
    expect(service.calls, contains('trust $_host $sha'));
    expect(find.text('Connected to Firefly III 6.7.9.'), findsOneWidget);
  });

  testWidgets('plain http asks first', (tester) async {
    await pump(
      tester,
      (ref) => FakeFireflyService(
        ref,
        checks: const [FireflyNeedsPlainConfirm(), FireflyConnected('6.7.9')],
      ),
    );
    await tester.enterText(
      find.byKey(const Key('firefly-address')),
      'http://192.168.1.20:8080',
    );
    await tester.tap(find.byKey(const Key('firefly-check')));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'This connection is not encrypted. Use it only on your home network.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('firefly-plain-yes')));
    await tester.pumpAndSettle();
    expect(service.calls, contains('plain http://192.168.1.20:8080'));
  });

  testWidgets('on: where it sends, what waits, and turning off', (
    tester,
  ) async {
    await pump(
      tester,
      (ref) => FakeFireflyService(
        ref,
        current: _on(),
        token: true,
        waitingCount: 3,
        sending: {'personal': true, 'shop': true},
      ),
    );
    expect(
      find.text('Sending to $_shown. Last sent 2 min ago.'),
      findsOneWidget,
    );
    expect(find.text('Changes waiting'), findsOneWidget);
    expect(find.text('Sent when the phone is online'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('Send now'), findsOneWidget);
    expect(find.text('Saved on this phone'), findsOneWidget);

    await tester.tap(find.text('Send now'));
    await tester.pumpAndSettle();
    expect(service.calls, contains('send'));

    // Send everything again, behind the menu.
    await tester.tap(find.byKey(const Key('firefly-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Send everything again'));
    await tester.pumpAndSettle();
    expect(service.calls, contains('send all'));

    final off = find.byKey(const Key('firefly-turn-off'));
    await tester.ensureVisible(off);
    await tester.tap(off);
    await tester.pumpAndSettle();
    expect(find.text('Stop sending to Firefly III?'), findsOneWidget);
    expect(
      find.text(
        'What is already in Firefly III stays there. The token and the 3 '
        'changes waiting are removed from this phone.',
      ),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const Key('firefly-turn-off-confirm')));
    await tester.pumpAndSettle();
    expect(service.calls, contains('off'));
    expect(find.text('Start sending'), findsOneWidget);
  });

  testWidgets("can't reach the server: shown here, with Try again", (
    tester,
  ) async {
    await pump(
      tester,
      (ref) => FakeFireflyService(
        ref,
        current: _on(
          problem: FireflyProblem.unreachable,
          minutesAgo: 3 * 24 * 60,
        ),
        token: true,
        waitingCount: 41,
        sending: {'personal': true, 'shop': true},
      ),
    );
    expect(
      find.textContaining(
        'Is the server on, and is this phone on its network?',
      ),
      findsOneWidget,
    );
    expect(find.textContaining("Can't reach $_shown."), findsOneWidget);
    expect(find.textContaining('Last sent 3 days ago.'), findsOneWidget);
    expect(find.text('Kept on this phone until it answers'), findsOneWidget);
    expect(find.text('41'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });

  testWidgets('a refused token opens the field for a new one', (tester) async {
    await pump(
      tester,
      (ref) => FakeFireflyService(
        ref,
        current: _on(problem: FireflyProblem.tokenRefused),
        waitingCount: 41,
        sending: {'personal': true},
      ),
    );
    expect(
      find.textContaining("Firefly III didn't accept the token."),
      findsOneWidget,
    );
    expect(find.text('The saved token was refused.'), findsOneWidget);
    expect(find.text('Paste a new token'), findsOneWidget);
    expect(
      find.text('41 changes wait on this phone. Nothing is lost.'),
      findsOneWidget,
    );
  });

  test("Profile's row says where it sends, never a problem", () {
    expect(fireflyRowSummary(null, _now), 'Off · Send to your own server');
    expect(
      fireflyRowSummary(const FireflySettings(), _now),
      'Off · Send to your own server',
    );
    expect(
      fireflyRowSummary(_on(), _now),
      'Sending to $_host · last sent 2 min ago',
    );
    expect(
      fireflyRowSummary(_on(problem: FireflyProblem.unreachable), _now),
      'Sending to $_host · last sent 2 min ago',
    );
  });
}
