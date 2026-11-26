// Ask's screens for the marketing screenshots: the made-up salaried person
// of the personal screens asking about their money (README, Screenshots).
//
// Every reply is the app's own: Ask's engine reading the seeded records,
// with the rules question reader and the template sentences, which is what
// the app uses when its trained reader and writer cannot run.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/domain/spaces/space.dart';
import 'package:pesaclarity/src/features/ask/application/ask_providers.dart';
import 'package:pesaclarity/src/features/ask/model/ask_model_catalogue.dart';
import 'package:pesaclarity/src/features/ask/model/ask_model_controller.dart';
import 'package:pesaclarity/src/features/ask/model/ask_model_download.dart';
import 'package:pesaclarity/src/features/ask/presentation/ask_conversations_screen.dart';
import 'package:pesaclarity/src/features/ask/presentation/ask_screen.dart';
import 'package:pesaclarity/src/features/ask/presentation/ask_settings_screen.dart';
import 'package:pesaclarity/src/features/currency/application/currency_controller.dart';
import 'package:pesaclarity/src/features/spaces/application/spaces_providers.dart';
import 'package:pesaclarity/src/routing/app_routes.dart';

import '../domain/fixtures.dart';
import '../helpers/fake_app_lock.dart';
import '../helpers/test_app.dart';
import 'harness.dart';
import 'personal_records.dart';

/// The clock the app reads; moved back while the earlier conversations are
/// asked.
var _clock = personalNow;

/// Earlier conversations, asked through Ask itself at these times, so the
/// list has a week and more of them.
final _earlier = [
  (eat(2026, 10, 28, 20, 15), 'How much did I spend on eating out in October?'),
  (eat(2026, 11, 9, 7, 50), 'How much do I owe?'),
  (eat(2026, 11, 16, 21, 5), 'How much did I spend on transport last week?'),
  (eat(2026, 11, 18, 19, 30), 'How much did I spend on airtime this month?'),
];

/// Today's conversations, each renamed short (the conversation menu's
/// Rename) so its name fits beside the buttons above it.
final _today = [
  (
    personalNow.subtract(const Duration(minutes: 20)),
    'Nimetumia pesa ngapi kwa fare mwezi huu?',
    'Fare this month',
  ),
  (
    personalNow.subtract(const Duration(minutes: 5)),
    'How much did I spend on food last month?',
    'Food last month',
  ),
];

/// Pumps Ask at [location], given the ids of [_today]'s conversations.
Future<void> _pump(
  WidgetTester tester,
  String Function(List<int> today) location, {
  AskModelState? model,
}) async {
  _clock = personalNow;
  final db = openTestDatabase();
  final c = ProviderContainer(
    overrides: [
      appDatabaseProvider.overrideWithValue(db),
      clockProvider.overrideWithValue(() => _clock),
      deviceRegionProvider.overrideWithValue('KE'),
      activeSpaceProvider.overrideWithValue(Space.personal),
      ...appLockOverrides(),
      // The rules reader and the template sentences: what Ask uses when
      // the trained reader and writer cannot run, as in a widget test.
      askReaderRuntimeOpenerProvider.overrideWithValue(null),
      askWriterRuntimeOpenerProvider.overrideWithValue(null),
      if (model != null)
        askModelControllerProvider.overrideWith(() => _FixedModel(model)),
      // The replies are the rules' own; the model's are tested elsewhere.
      askModelGeneratorProvider.overrideWithValue(null),
    ],
  );
  addTearDown(c.dispose);
  final today = <int>[];
  await tester.runAsync(() async {
    await PersonalRecords(db).seed();
    final ask = c.read(askControllerProvider.notifier);
    for (final (at, question) in _earlier) {
      _clock = at;
      ask.startNew();
      await ask.ask(question);
    }
    for (final (at, question, title) in _today) {
      _clock = at;
      ask.startNew();
      await ask.ask(question);
      await ask.rename(title);
      today.add(c.read(askControllerProvider).conversationId!);
    }
    _clock = personalNow;
  });
  final router = GoRouter(
    initialLocation: location(today),
    routes: [
      GoRoute(
        path: AppRoutes.ask,
        builder: (_, _) => const AskScreen(),
        routes: [
          GoRoute(
            path: 'conversations',
            builder: (_, _) => const AskConversationsScreen(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (_, state) => AskScreen(
                  conversationId: int.parse(state.pathParameters['id']!),
                ),
              ),
            ],
          ),
          GoRoute(
            path: 'settings',
            builder: (_, _) => const AskSettingsScreen(),
          ),
        ],
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(container: c, child: shotRouterApp(router)),
  );
  await settleFrames(tester);
  await tester.pumpAndSettle();
}

/// Ask's money model as a capable phone sees it, made-up sizes.
class _FixedModel extends AskModelController {
  _FixedModel(this.fixed);

  final AskModelState fixed;

  @override
  AskModelState build() => fixed;
}

AskModelEntry _model(AskModelTier tier, String params, int mb, int ram) =>
    AskModelEntry(
      tier: tier,
      file: '${tier.name}.weights',
      url: '${askModelUrlPrefix}slm-models/${tier.name}.weights',
      sizeBytes: mb * 1000000,
      sha256: '0' * 64,
      minRamMb: ram,
      parameters: params,
      licence: 'Apache-2.0',
      credit: 'SmolLM2, fine-tuned for Pesa Clarity',
    );

final _light = _model(AskModelTier.light, '135M', 72, 3072);
final _full = _model(AskModelTier.full, '360M', 168, 4096);
final _catalogue = AskModelCatalogue([_light, _full]);
final _capable = AskModelState(
  loaded: true,
  catalogue: _catalogue,
  capable: [_light, _full],
  directory: '/models',
);

Future<void> _scrollToEnd(WidgetTester tester) async {
  await tester.drag(find.byType(ListView).first, const Offset(0, -2000));
  await tester.pumpAndSettle();
}

void main() {
  screenshot('ask-model-offer', (tester) async {
    await _pump(
      tester,
      (today) => AppRoutes.askConversation(today[1]),
      model: _capable,
    );
    await _scrollToEnd(tester);
    await snap(tester);
  });

  screenshot('ask-model-downloading', (tester) async {
    await _pump(
      tester,
      (today) => AppRoutes.askConversation(today[1]),
      model: _capable.copyWith(
        offerDone: true,
        phase: AskModelPhase.downloading,
        target: () => _light,
        progress: const AskModelProgress(30000000, 72000000),
        secondsLeft: () => 70,
      ),
    );
    await _scrollToEnd(tester);
    await snap(tester);
  });

  screenshot('ask-model-settings', (tester) async {
    await _pump(
      tester,
      (_) => AppRoutes.askSettings,
      model: _capable.copyWith(
        offerDone: true,
        installed: () => AskModelTier.light,
        selected: () => AskModelTier.light,
      ),
    );
    await snap(tester);
  });

  screenshot('ask', (tester) async {
    await _pump(tester, (today) => AppRoutes.askConversation(today[1]));
    await snap(tester);
  });

  screenshot('ask-swahili', (tester) async {
    await _pump(tester, (today) => AppRoutes.askConversation(today[0]));
    await snap(tester);
  });

  screenshot('ask-conversations', (tester) async {
    await _pump(tester, (_) => AppRoutes.askConversations);
    await snap(tester);
  });

  screenshot('ask-settings', (tester) async {
    await _pump(tester, (_) => AppRoutes.askSettings);
    await snap(tester);
  });
}
