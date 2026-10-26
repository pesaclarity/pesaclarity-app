import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the domain layer is pure Dart', () {
    final offenders = [
      for (final file in Directory('lib/src/domain').listSync(recursive: true))
        if (file is File && file.path.endsWith('.dart'))
          for (final line in file.readAsLinesSync())
            if (RegExp(
              r'''^import 'package:(flutter|drift|flutter_riverpod|sqlite3)[/:]|^import '.*/data/''',
            ).hasMatch(line))
              '${file.path}: $line',
    ];
    expect(offenders, isEmpty);
  });
}
