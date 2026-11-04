import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/domain/privacy/privacy_policy.dart';
import 'package:pesaclarity/src/features/auth/application/auth_controller.dart';
import 'package:pesaclarity/src/features/auth/domain/auth_models.dart';
import 'package:pesaclarity/src/features/privacy/presentation/email_policy_sheet.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

class _FakeAuth extends AuthController {
  _FakeAuth({this.fail});

  final AuthFailure? fail;
  final sent = <(String, String)>[];

  @override
  Future<AccountSession?> build() async => null;

  @override
  Future<void> emailPolicyCopy({
    required String email,
    required String policy,
  }) async {
    if (fail case final failure?) throw failure;
    sent.add((email, policy));
  }
}

void main() {
  final policy = PrivacyPolicy.fromAssets(
    metadata: {'version': '1.4', 'updated': '2026-10-30', 'changes': []},
    markdown:
        '# Privacy policy\n\n## What stays on your phone\n\nYour messages.\n',
  );

  Future<_FakeAuth> open(WidgetTester tester, {AuthFailure? fail}) async {
    final auth = _FakeAuth(fail: fail);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authControllerProvider.overrideWith(() => auth)],
        child: MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showEmailPolicySheet(
                  context,
                  policy,
                  suggestedEmail: 'wanjiru@example.com',
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return auth;
  }

  testWidgets('sends the bundled policy to the address given', (tester) async {
    final auth = await open(tester);
    expect(find.text('Email me a copy'), findsOneWidget);
    expect(find.text('wanjiru@example.com'), findsOneWidget);
    await tester.tap(find.byKey(const Key('email-policy-send')));
    await tester.pumpAndSettle();
    expect(auth.sent.single.$1, 'wanjiru@example.com');
    expect(auth.sent.single.$2, startsWith('# Privacy policy'));
    expect(find.text('Sent. Check your inbox for the copy.'), findsOneWidget);
  });

  testWidgets('says why it could not send', (tester) async {
    await open(tester, fail: const AuthFailure(AuthFailureKind.rateLimited));
    await tester.tap(find.byKey(const Key('email-policy-send')));
    await tester.pumpAndSettle();
    expect(
      find.text("You have had today's copies. Try again tomorrow."),
      findsOneWidget,
    );
  });
}
