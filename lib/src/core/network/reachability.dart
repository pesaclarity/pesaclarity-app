import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../config/server_config.dart';

/// Answers quickly whether the phone can reach our server now. Never
/// throws: anything but an answer counts as offline.
typedef ReachabilityCheck = Future<bool> Function();

/// Looks up the server's name, giving up after a few seconds. A lookup
/// fails at once in airplane mode and with no signal.
final serverReachableProvider = Provider<ReachabilityCheck>((ref) {
  final host = ref.watch(serverBaseUrlProvider)?.host;
  return () async {
    if (host == null || host.isEmpty) return false;
    try {
      final found = await InternetAddress.lookup(host)
          .timeout(const Duration(seconds: 3));
      return found.isNotEmpty;
    } on Object {
      return false;
    }
  };
});
