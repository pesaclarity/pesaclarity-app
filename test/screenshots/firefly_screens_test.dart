// The Firefly III screen (decision 0029), for the accessibility check
// (tool/accessibility.sh): setting up, on, can't reach the server, the token
// refused, the certificate question and turning off, each at every text
// size, in light and dark. Not marketing screenshots, so tool/screenshots.sh
// skips them. A made-up server, token and fingerprint.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/features/firefly/application/firefly_service.dart';
import 'package:pesaclarity/src/features/firefly/application/firefly_settings.dart';
import 'package:pesaclarity/src/features/firefly/presentation/firefly_screen.dart';

import '../helpers/fake_firefly_service.dart';
import '../helpers/test_app.dart';
import 'harness.dart';

final _now = DateTime.utc(2026, 11, 21, 6, 41);
const _host = 'firefly.example.home';
const _sha = '3FA9127CE05B44D19A6E02BB71C83DF0582AE4169C07B36DA1FE20854CD9E37A';

FireflySettings _on({FireflyProblem? problem, int minutes = 2}) =>
    FireflySettings(
      address: 'https://$_host',
      on: true,
      lastSentAt: _now.subtract(Duration(minutes: minutes)),
      problem: problem,
      version: '6.7.9',
    );

Future<void> _pump(
  WidgetTester tester,
  FakeFireflyService Function(Ref ref) service,
) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        fakeFireflyService(service),
        clockProvider.overrideWithValue(() => _now),
      ],
      child: shotApp(const FireflyScreen()),
    ),
  );
  await settleFrames(tester);
}

/// Scrolls the screen's list until [key] is built and on screen.
Future<Finder> _reach(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  await tester.scrollUntilVisible(
    finder,
    200,
    scrollable: find
        .descendant(
          of: find.byKey(const Key('firefly-list')),
          matching: find.byType(Scrollable),
        )
        .first,
  );
  await tester.pumpAndSettle();
  return finder;
}

void main() {
  if (!checkAccessibility) return;

  screenshot('firefly-setup', (tester) async {
    await _pump(
      tester,
      (ref) => FakeFireflyService(
        ref,
        checks: const [
          FireflyAskTrust(host: _host, sha256: _sha),
          FireflyConnected('6.7.9'),
        ],
      ),
    );
    await tester.enterText(
      await _reach(tester, 'firefly-address'),
      'https://$_host',
    );
    await tester.enterText(
      await _reach(tester, 'firefly-token'),
      'made-up-token',
    );
    await tester.tap(await _reach(tester, 'firefly-check'));
    await settleFrames(tester);
    await snap(tester, variant: 'firefly-certificate');
    await tester.tap(find.byKey(const Key('firefly-trust')));
    await settleFrames(tester);
    FocusManager.instance.primaryFocus?.unfocus();
    await settleFrames(tester);
    await snap(tester);
  });

  screenshot('firefly-on', (tester) async {
    await _pump(
      tester,
      (ref) => FakeFireflyService(
        ref,
        current: _on(),
        token: true,
        waitingCount: 3,
        sending: {'personal': true, 'shop': true},
      ),
    );
    await snap(tester);
    await tester.tap(await _reach(tester, 'firefly-turn-off'));
    await settleFrames(tester);
    await snap(tester, variant: 'firefly-turn-off');
  });

  screenshot('firefly-unreachable', (tester) async {
    await _pump(
      tester,
      (ref) => FakeFireflyService(
        ref,
        current: _on(problem: FireflyProblem.unreachable, minutes: 3 * 24 * 60),
        token: true,
        waitingCount: 41,
        sending: {'personal': true, 'shop': true},
      ),
    );
    await snap(tester);
  });

  screenshot('firefly-token', (tester) async {
    await _pump(
      tester,
      (ref) => FakeFireflyService(
        ref,
        current: _on(problem: FireflyProblem.tokenRefused),
        waitingCount: 41,
        sending: {'personal': true, 'shop': true},
      ),
    );
    await snap(tester);
  });
}
