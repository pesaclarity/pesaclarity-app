import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/config/server_config.dart';

void main() {
  test('accepts https and drops a trailing slash, query and credentials', () {
    expect(
      parseServerBaseUrl(' https://user:pw@api.example.org/base/?x=1 '),
      Uri.parse('https://api.example.org/base'),
    );
  });

  test('allows plain http only to local development hosts', () {
    expect(
      parseServerBaseUrl('http://10.0.2.2:8000'),
      Uri.parse('http://10.0.2.2:8000'),
    );
    expect(parseServerBaseUrl('http://api.example.org'), isNull);
  });

  test('treats a missing or broken value as no server', () {
    expect(parseServerBaseUrl(''), isNull);
    expect(parseServerBaseUrl('api.example.org'), isNull);
    expect(parseServerBaseUrl('ftp://api.example.org'), isNull);
  });
}
