import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pesaclarity/src/core/ml/model_engines.dart';
import 'package:pesaclarity/src/core/time/clock.dart';
import 'package:pesaclarity/src/data/database/database_providers.dart';
import 'package:pesaclarity/src/domain/ask/answer.dart';
import 'package:pesaclarity/src/domain/ask/engine.dart';
import 'package:pesaclarity/src/domain/ask/model_reply_writer.dart';
import 'package:pesaclarity/src/domain/ask/rule_question_reader.dart';
import 'package:pesaclarity/src/domain/categoriser/model_manifest.dart';
import 'package:pesaclarity/src/domain/ml/dart_ask_reader.dart';
import 'package:pesaclarity/src/domain/reader/rule_reader.dart';
import 'package:pesaclarity/src/domain/time/calendar.dart';
import 'package:pesaclarity/src/features/ask/application/ask_providers.dart';
import 'package:pesaclarity/src/features/ask/data/ask_model_store.dart';
import 'package:pesaclarity/src/features/ask/data/rayo_ask_runtimes.dart';
import 'package:pesaclarity/src/features/categoriser/data/model_store.dart';
import 'package:pesaclarity/src/features/categoriser/data/rayo_categoriser_runtime.dart';
import 'package:pesaclarity/src/features/profile/presentation/model_engine_tile.dart';
import 'package:pesaclarity/src/features/review/data/reader_store.dart';

import '../../helpers/test_app.dart';

Uint8List _file(String path) => File(path).readAsBytesSync();

Future<Uint8List?> _asset(String path) async {
  final f = File(path);
  return f.existsSync() ? f.readAsBytesSync() : null;
}

Map<String, Object?> _json(String path) =>
    (jsonDecode(File(path).readAsStringSync()) as Map).cast<String, Object?>();

bool _no() => false;

void main() {
  late ModelEngines engines;
  setUp(() => engines = ModelEngines());

  test('test builds are not rayo-only unless the define says so', () {
    expect(rayoOnly, isFalse);
  });

  test("rayo's kernels name the engine", () {
    expect(rayoEngineName('neon-dotprod'), 'Rayo (NEON, SDOT)');
    expect(rayoEngineName('neon'), 'Rayo (NEON)');
    expect(rayoEngineName('generic'), 'Rayo (generic)');
    expect(rayoEngineName('avx2'), 'Rayo (AVX2)');
  });

  group('the Ask reader', () {
    final bytes = _file('$askModelFolder/ask-reader.weights');

    test('runs on rayo and says which kernels', () {
      final reader = openAskReader(bytes, engines: engines);
      addTearDown(reader.close);
      expect(reader, isA<RayoAskReader>());
      expect(engines.of(OnPhoneModel.askReader).engine, startsWith('Rayo ('));
      expect(engines.of(OnPhoneModel.askReader).reason, isNull);
    });

    test('falls back to Dart in a release build, and says why', () {
      final reader = openAskReader(bytes, available: _no, engines: engines);
      addTearDown(reader.close);
      expect(reader, isA<DartAskReader>());
      final engine = engines.of(OnPhoneModel.askReader);
      expect(engine.engine, ModelEngine.dartFallback);
      expect(engine.reason, contains('cannot load'));
    });

    test('in a rayo-only build, throws why rayo failed', () {
      expect(
        () => openAskReader(
          bytes,
          onlyRayo: true,
          available: _no,
          engines: engines,
        ),
        throwsA(
          isA<RayoOnlyFailure>().having(
            (e) => '$e',
            'message',
            startsWith('Rayo failed: Ask reader: '),
          ),
        ),
      );
      expect(engines.of(OnPhoneModel.askReader).engine, ModelEngine.failed);
    });

    test('in a rayo-only build, a refused file is thrown too', () {
      expect(
        () => openAskReader(
          bytes,
          onlyRayo: true,
          openRayo: (_) => throw StateError('bad weights'),
          engines: engines,
        ),
        throwsA(
          isA<RayoOnlyFailure>().having(
            (e) => e.reason,
            'reason',
            contains('bad weights'),
          ),
        ),
      );
    });

    test('the loader passes the failure on in a rayo-only build', () async {
      final fallback = RuleQuestionReader(
        today: () => CalendarDate(2026, 11, 1),
      );
      await expectLater(
        loadAskReader(
          readAsset: _asset,
          openRuntime: (b) => openAskReader(
            b,
            onlyRayo: true,
            available: _no,
            engines: engines,
          ),
          fallback: fallback,
          onlyRayo: true,
          engines: engines,
        ),
        throwsA(isA<RayoOnlyFailure>()),
      );
      final loaded = await loadAskReader(
        readAsset: _asset,
        openRuntime: (b) => openAskReader(b, engines: engines),
        fallback: fallback,
        engines: engines,
      );
      addTearDown(loaded.close);
      expect(
        engines.of(OnPhoneModel.askReader).version,
        startsWith('weights '),
      );
    });
  });

  group('the Ask writer', () {
    final manifest = AskWriterManifest.fromJson(
      _json('$askModelFolder/$askWriterManifestFile'),
    );
    final bytes = _file('$askModelFolder/${manifest.weightsFile}');

    test(
      'without rayo, a release build words replies with templates',
      () async {
        final writer = await loadAskWriter(
          readAsset: _asset,
          openRuntime: (b, m) =>
              openAskWriter(b, m, available: _no, engines: engines),
          engines: engines,
        );
        expect(writer, isNull);
        expect(
          engines.of(OnPhoneModel.askWriter).engine,
          ModelEngine.templates,
        );
      },
    );

    test('in a rayo-only build, throws why rayo failed', () {
      expect(
        () => openAskWriter(
          bytes,
          manifest,
          onlyRayo: true,
          available: _no,
          engines: engines,
        ),
        throwsA(isA<RayoOnlyFailure>()),
      );
    });
  });

  group('the message reader', () {
    test('in a rayo-only build, the rules do not stand in', () async {
      await expectLater(
        loadReader(
          readAsset: _asset,
          openRuntime: (_) => throw StateError('no rayo'),
          onlyRayo: true,
          engines: engines,
        ),
        throwsA(isA<RayoOnlyFailure>()),
      );
      final reader = await loadReader(
        readAsset: _asset,
        openRuntime: (_) => throw StateError('no rayo'),
        engines: engines,
      );
      expect(reader, isA<RuleMessageReader>());
      expect(
        engines.of(OnPhoneModel.messageReader).reason,
        contains('no rayo'),
      );
    });
  });

  group('the categoriser', () {
    final manifest = ModelManifest.fromJson(
      _json('$categoriserModelFolder/$modelManifestFile'),
    );
    final bytes = _file('$categoriserModelFolder/${manifest.weightsFile}');

    test('falls back to Dart in a release build', () {
      final runtime = openCategoriserRuntime(
        bytes,
        manifest.featureConfig,
        available: _no,
        engines: engines,
      );
      addTearDown(runtime.close);
      expect(runtime, isNot(isA<RayoCategoriser>()));
      expect(
        engines.of(OnPhoneModel.categoriser).engine,
        ModelEngine.dartFallback,
      );
    });

    test('in a rayo-only build, is refused with rayo\'s reason', () async {
      final loaded = await loadCategoriser(
        readAsset: _asset,
        openRuntime: (b, c) => openCategoriserRuntime(
          b,
          c,
          onlyRayo: true,
          available: _no,
          engines: engines,
        ),
        engines: engines,
      );
      expect(loaded.status, ModelStatus.refused);
      expect(loaded.reasons.join(), contains('Rayo failed'));
      expect(engines.of(OnPhoneModel.categoriser).engine, ModelEngine.failed);
    });
  });

  test('Ask shows why rayo failed in place of an answer', () async {
    final db = openTestDatabase();
    addTearDown(db.close);
    final c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        clockProvider.overrideWithValue(() => DateTime(2026, 11, 13, 10)),
        askEngineProvider.overrideWith(
          (ref) => Future<AskEngine>.error(
            const RayoOnlyFailure(OnPhoneModel.askReader, 'no library'),
          ),
        ),
      ],
    );
    addTearDown(c.dispose);
    await c.read(askControllerProvider.notifier).ask('Food last month');
    final session = c.read(askControllerProvider);
    expect(session.busy, isFalse);
    final answer = session.messages.last.answer!;
    expect(answer.kind, ReplyKind.cant);
    expect(answer.template, 'Rayo failed: Ask reader: no library');
  });

  group('Profile › About', () {
    testWidgets('shows what runs each model', (tester) async {
      engines
        ..record(OnPhoneModel.askReader, const ModelEngine('Rayo (NEON, SDOT)'))
        ..version(OnPhoneModel.askReader, 'weights 1a2b3c4d')
        ..record(
          OnPhoneModel.categoriser,
          const ModelEngine(ModelEngine.dartFallback, reason: 'no library'),
        );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ModelEngineTile(engines: engines)),
        ),
      );
      expect(find.text('Model engine'), findsOneWidget);
      expect(
        find.text(
          'Ask reader: Rayo (NEON, SDOT) · weights 1a2b3c4d\n'
          'Ask writer: Not loaded\n'
          'Message reader: Not loaded\n'
          'Categoriser: Dart fallback · no library',
        ),
        findsOneWidget,
      );

      engines.record(
        OnPhoneModel.askWriter,
        const ModelEngine(ModelEngine.templates, reason: 'not bundled'),
      );
      await tester.pump();
      expect(
        find.textContaining('Ask writer: Templates (no writer)'),
        findsOneWidget,
      );
      expect(find.textContaining('Rayo only'), findsNothing);
    });

    testWidgets('says when the build is rayo-only', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ModelEngineTile(engines: engines, onlyRayo: true),
          ),
        ),
      );
      expect(find.textContaining('Rayo only: on'), findsOneWidget);
    });
  });
}
