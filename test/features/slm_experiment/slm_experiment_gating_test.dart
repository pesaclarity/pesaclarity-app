import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/features/slm_experiment/slm_experiment_flag.dart';

/// The experiment is in test builds only: the flag is off unless a test
/// build sets it, and no release build sets it or adds the model file.
void main() {
  test('off unless the build sets SLM_EXPERIMENT', () {
    expect(slmExperiment, isFalse);
  });

  test('the model file is never a Flutter asset', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, isNot(contains('.weights')));
    expect(pubspec, isNot(contains('slm')));
    expect(
      Directory('assets')
          .listSync(recursive: true)
          .where((f) => f.path.endsWith('smollm2-360m-instruct-q4.weights')),
      isEmpty,
    );
  });

  test('release workflows never set the flag or add the model', () {
    for (final name in [
      'release-play.yml',
      'foss-build.yml',
      'reproducible-build.yml',
      'release-gate.yml',
    ]) {
      final text = File('.github/workflows/$name').readAsStringSync();
      expect(text, isNot(contains('SLM_EXPERIMENT')), reason: name);
      expect(text, isNot(contains('slm-models')), reason: name);
    }
  });

  test('test builds set it: iPhone always, APK only off main', () {
    final ios = File('.github/workflows/ios-build.yml').readAsStringSync();
    expect(ios, contains('--dart-define=SLM_EXPERIMENT=true'));
    expect(ios, contains('Runner.app/slm/'));
    final apk = File('.github/workflows/test-apk.yml').readAsStringSync();
    expect(
      apk,
      contains("SLM_EXPERIMENT: \${{ github.ref != 'refs/heads/main' }}"),
    );
    expect(apk, contains(r'--dart-define=SLM_EXPERIMENT="$SLM_EXPERIMENT"'));
  });
}
