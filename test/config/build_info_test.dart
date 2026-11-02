import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/config/build_info.dart';
import 'package:pesaclarity/src/config/flavor.dart';

void main() {
  test('shows the version with the flavour', () {
    expect(buildLabel('0.2.0', AppFlavor.play), '0.2.0 · play');
    expect(buildLabel('0.2.0-dev.31', AppFlavor.foss), '0.2.0-dev.31 · foss');
  });

  test('shows the flavour alone for local builds without a version', () {
    expect(buildLabel('', AppFlavor.foss), 'foss');
    expect(buildLabel('  ', AppFlavor.play), 'play');
  });
}
