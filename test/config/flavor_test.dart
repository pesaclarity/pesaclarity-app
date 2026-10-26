import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/config/flavor.dart';

void main() {
  test('resolves known flavours', () {
    expect(AppFlavor.fromName('play'), AppFlavor.play);
    expect(AppFlavor.fromName('foss'), AppFlavor.foss);
  });

  test('falls back to the restrictive foss flavour', () {
    expect(AppFlavor.fromName(null), AppFlavor.foss);
    expect(AppFlavor.fromName('unknown'), AppFlavor.foss);
  });

  test('only play may use Google services', () {
    expect(AppFlavor.play.allowsGoogleServices, isTrue);
    expect(AppFlavor.foss.allowsGoogleServices, isFalse);
  });
}
