import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Whether [error] means the server could not be reached: no network, a
/// timeout, a dropped or refused connection, a TLS failure (a captive
/// portal, say), or the `http` package's wrapper around any of these.
///
/// These are what airplane mode and poor coverage throw, and the app
/// treats them all as "offline".
bool isConnectionError(Object error) =>
    error is IOException ||
    error is OSError ||
    error is TimeoutException ||
    error is TlsException ||
    error is http.ClientException;
