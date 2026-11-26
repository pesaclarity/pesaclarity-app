import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/features/ask/model/ask_model_catalogue.dart';
import 'package:pesaclarity/src/features/ask/model/ask_model_controller.dart';
import 'package:pesaclarity/src/features/ask/model/ask_model_download.dart';
import 'package:pesaclarity/src/features/ask/presentation/ask_model_card.dart';
import 'package:pesaclarity/src/theme/app_theme.dart';

/// Holds a set state and records what the screens asked for.
class _Fake extends AskModelController {
  _Fake(this.initial);

  final AskModelState initial;
  final calls = <String>[];

  @override
  AskModelState build() => initial;

  @override
  Future<void> notNow() async {
    calls.add('notNow');
    state = state.copyWith(offerDone: true);
  }

  @override
  Future<void> download(AskModelTier tier) async =>
      calls.add('download ${tier.name}');

  @override
  Future<void> choose(AskModelTier? tier) async =>
      calls.add('choose ${tier?.name}');

  @override
  void cancel() => calls.add('cancel');

  @override
  Future<void> setMobileData(bool on) async => calls.add('mobile $on');

  @override
  Future<void> deleteModel() async => calls.add('delete');
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
      credit: 'A made-up model',
    );

final _light = _model(AskModelTier.light, '135M', 72, 3072);
final _full = _model(AskModelTier.full, '360M', 168, 4096);
final _capable = AskModelState(
  loaded: true,
  catalogue: AskModelCatalogue([_light, _full]),
  capable: [_light, _full],
  directory: '/models',
);

Future<_Fake> _pump(WidgetTester tester, AskModelState state, Widget w) async {
  final fake = _Fake(state);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [askModelControllerProvider.overrideWith(() => fake)],
      child: MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: ListView(children: [w])),
      ),
    ),
  );
  await tester.pump();
  return fake;
}

void main() {
  testWidgets('a phone that cannot run a model sees nothing', (tester) async {
    await _pump(
      tester,
      const AskModelState(loaded: true),
      const Column(children: [AskModelCard(), AskAnswersSection()]),
    );
    expect(find.byKey(const Key('ask-model-card')), findsNothing);
    expect(find.text('Answers'), findsNothing);
  });

  testWidgets('the offer downloads Light, and Not now hides it', (
    tester,
  ) async {
    final fake = await _pump(tester, _capable, const AskModelCard());
    expect(find.text('Get better answers'), findsOneWidget);
    expect(
      find.text(
        'Light · 135M · ~72 MB · faster\n'
        'Full · 360M · ~168 MB · needs 4 GB memory',
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Download Light (72 MB)'));
    expect(fake.calls, ['download light']);
    await tester.tap(find.text('Not now'));
    await tester.pump();
    expect(find.byKey(const Key('ask-model-card')), findsNothing);
  });

  testWidgets('shows the download with progress and cancel', (tester) async {
    final fake = await _pump(
      tester,
      _capable.copyWith(
        offerDone: true,
        phase: AskModelPhase.downloading,
        target: () => _light,
        progress: const AskModelProgress(30000000, 72000000),
        secondsLeft: () => 70,
      ),
      const AskModelCard(),
    );
    expect(find.text('Getting better answers'), findsOneWidget);
    expect(find.text('30 of 72 MB · Wi-Fi · about 1 min left'), findsOneWidget);
    final bar = tester.widget<LinearProgressIndicator>(
      find.byKey(const Key('ask-model-progress')),
    );
    expect(bar.value, closeTo(30 / 72, 0.001));
    await tester.tap(find.text('Cancel'));
    expect(fake.calls, ['cancel']);
  });

  testWidgets('settings: choose, mobile data, delete and the licence', (
    tester,
  ) async {
    final fake = await _pump(
      tester,
      _capable.copyWith(
        offerDone: true,
        installed: () => AskModelTier.light,
        selected: () => AskModelTier.light,
      ),
      const AskAnswersSection(),
    );
    expect(find.text('Answers'), findsOneWidget);
    expect(find.text('135M · 72 MB · faster'), findsOneWidget);
    expect(find.text('360M · 168 MB · needs 4 GB memory'), findsOneWidget);
    expect(find.text('Quick answers, as before'), findsOneWidget);
    expect(find.text('Frees 72 MB'), findsOneWidget);
    expect(find.text('Model: A made-up model (Apache-2.0)'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('ask-model-light')),
        matching: find.byIcon(Icons.check),
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('Full model'));
    await tester.tap(find.text('No model'));
    await tester.tap(find.text('Download on mobile data'));
    await tester.pump();
    expect(fake.calls, ['choose full', 'cancel', 'choose null', 'mobile true']);
  });
}
