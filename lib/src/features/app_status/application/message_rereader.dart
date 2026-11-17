import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Reads the phone's messages again from a day, when a notice asks for it,
/// such as after a bank changed its messages and some payments were missed.
abstract interface class MessageRereader {
  /// Starts reading messages again from [from] (a day; the time is ignored).
  /// Returns whether the request was taken, so a notice that could not be
  /// handled asks again next time.
  Future<bool> requestReread(DateTime from);
}

/// Takes no request, for builds without a re-reader.
class NoMessageRereader implements MessageRereader {
  const NoMessageRereader();

  @override
  Future<bool> requestReread(DateTime from) async => false;
}

/// The re-reader app status hands `reread_from` to. The "Read messages
/// again" service overrides this.
final messageRereaderProvider = Provider<MessageRereader>(
  (ref) => const NoMessageRereader(),
);
