import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Every network client must get its [HttpClient] from HttpClientFactory, so
/// certificate pinning covers all of them.
void main() {
  test('HttpClient is created only by the pinned factory', () {
    const factoryFile = 'lib/src/core/network/pinned_http_client.dart';
    final direct = RegExp(r'\bHttpClient\s*\(');
    final offenders = [
      for (final file in Directory('lib').listSync(recursive: true))
        if (file is File &&
            file.path.endsWith('.dart') &&
            file.path.replaceAll(r'\', '/') != factoryFile &&
            direct.hasMatch(file.readAsStringSync()))
          file.path,
    ];
    expect(offenders, isEmpty, reason: 'Use httpClientFactoryProvider');
  });

  test('unpinned clients are used for Google Drive and public rates only', () {
    final users = [
      for (final file in Directory('lib').listSync(recursive: true))
        if (file is File &&
            file.path.endsWith('.dart') &&
            file.readAsStringSync().contains('.createUnpinned('))
          file.path.replaceAll(r'\', '/'),
    ]..sort();
    expect(users, [
      'lib/src/features/backup/application/backup_providers.dart',
      'lib/src/features/currency/data/rates_client.dart',
    ]);
    final rates = File(users.last).readAsStringSync();
    expect('.createUnpinned('.allMatches(rates), hasLength(1));
    expect(rates, isNot(contains('Authorization')));
    final providers = File(users.first).readAsStringSync();
    expect('.createUnpinned('.allMatches(providers), hasLength(1));
    expect(
      providers.indexOf('.createUnpinned('),
      greaterThan(providers.indexOf('DriveBackupLocation(')),
    );
  });
}
