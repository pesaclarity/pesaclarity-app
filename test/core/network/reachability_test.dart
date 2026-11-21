import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/config/server_config.dart';
import 'package:pesaclarity/src/core/network/reachability.dart';

void main() {
  test('without a server, nothing is reachable', () async {
    final container = ProviderContainer(
      overrides: [serverBaseUrlProvider.overrideWithValue(null)],
    );
    addTearDown(container.dispose);
    expect(await container.read(serverReachableProvider)(), isFalse);
  });

  test(
    'a name that does not resolve counts as offline, without throwing',
    () async {
      final container = ProviderContainer(
        overrides: [
          serverBaseUrlProvider.overrideWithValue(
            Uri.parse('https://no-such-host.invalid'),
          ),
        ],
      );
      addTearDown(container.dispose);
      expect(await container.read(serverReachableProvider)(), isFalse);
    },
  );
}
