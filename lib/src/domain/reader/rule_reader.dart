import 'message_reading.dart';
import 'reader_tokens.dart';

/// Reads messages with plain rules when no trained reader is installed:
/// money next to a currency, dates and times by their shape, the payee
/// after "to", "from" or "at". Every field it finds gets confidence 0.5, so
/// the screen asks the person to check it.
class RuleMessageReader implements MessageReader {
  const RuleMessageReader();

  static const _confidence = 0.5;
  static const _currencies = {'kes', 'ksh', 'kshs', 'sh', 'shs'};
  static const _balanceWords = {'bal', 'balance'};
  static const _feeWords = {'cost', 'fee', 'fees', 'charge', 'charges'};
  static const _referenceWords = {'ref', 'reference', 'txn', 'trx', 'id'};
  static const _partyStarts = {'to', 'from', 'at', 'by', 'payee', 'merchant'};
  static const _partyStops = {
    'on',
    'at',
    'for',
    'via',
    'ref',
    'date',
    'amount',
    'new',
  };
  static const _outWords = {
    'debited',
    'sent',
    'paid',
    'spent',
    'withdrawn',
    'withdrawal',
    'purchase',
    'payment',
    'transferred',
    'charged',
  };
  static const _inWords = {
    'credited',
    'received',
    'deposit',
    'deposited',
    'refund',
    'salary',
    'reversal',
  };
  static const _noneWords = {
    'otp',
    'code',
    'limit',
    'win',
    'failed',
    'declined',
  };

  @override
  MessageReading read(String message) {
    final tokens = tokenise(message);
    final keys = [for (final t in tokens) hashKey(t.text)];
    final fields = <ReaderField, FieldReading>{};

    FieldReading span(ReaderField field, int from, int to) => FieldReading(
      field: field,
      text: message.substring(tokens[from].start, tokens[to].end),
      start: tokens[from].start,
      end: tokens[to].end,
      confidence: _confidence,
    );

    bool isMoney(int i) =>
        i < tokens.length &&
        const {
          TokenShape.integer,
          TokenShape.decimal,
          TokenShape.grouped,
        }.contains(tokens[i].shape);

    bool near(int i, Set<String> words) {
      for (var k = i - 1; k >= 0 && k >= i - 4; k--) {
        if (words.contains(keys[k])) return true;
      }
      return false;
    }

    // Money: a currency word, an optional dot, then a number.
    for (var i = 0; i < tokens.length; i++) {
      if (!_currencies.contains(keys[i])) continue;
      final n = i + 1 < tokens.length && keys[i + 1] == '.' ? i + 2 : i + 1;
      if (!isMoney(n)) continue;
      final field = near(i, _balanceWords)
          ? ReaderField.balance
          : near(i, _feeWords)
          ? ReaderField.fee
          : ReaderField.amount;
      fields.putIfAbsent(field, () => span(field, i, n));
    }

    for (var i = 0; i < tokens.length; i++) {
      final shape = tokens[i].shape;
      if (shape == TokenShape.date) {
        fields.putIfAbsent(
          ReaderField.date,
          () => span(ReaderField.date, i, i),
        );
      } else if (shape == TokenShape.time) {
        final end =
            i + 1 < tokens.length && const {'am', 'pm'}.contains(keys[i + 1])
            ? i + 1
            : i;
        fields.putIfAbsent(
          ReaderField.time,
          () => span(ReaderField.time, i, end),
        );
      } else if (shape == TokenShape.mixed && tokens[i].text.length >= 8 ||
          near(i, _referenceWords) &&
              (shape == TokenShape.mixed || shape == TokenShape.integer)) {
        fields.putIfAbsent(
          ReaderField.reference,
          () => span(ReaderField.reference, i, i),
        );
      }
    }

    // The payee: names after "to", "from" or "at", up to the next stop word.
    for (var i = 0; i < tokens.length - 1; i++) {
      if (!_partyStarts.contains(keys[i])) continue;
      var start = i + 1;
      if (start < tokens.length && keys[start] == ':') start++;
      var end = start;
      while (end < tokens.length &&
          end - start < 8 &&
          !_partyStops.contains(keys[end]) &&
          tokens[end].shape != TokenShape.punct &&
          tokens[end].shape != TokenShape.date) {
        end++;
      }
      if (end > start && tokens[start].shape != TokenShape.lower) {
        fields[ReaderField.counterparty] = span(
          ReaderField.counterparty,
          start,
          end - 1,
        );
        break;
      }
    }

    final words = keys.toSet();
    final MessageKind kind;
    if (!fields.containsKey(ReaderField.amount) ||
        words.intersection(_noneWords).isNotEmpty) {
      kind = MessageKind.notTransaction;
    } else if (words.contains('you') && words.contains('sent') ||
        words.intersection(_inWords).isNotEmpty &&
            words.intersection(_outWords).isEmpty) {
      kind = MessageKind.moneyIn;
    } else {
      kind = MessageKind.moneyOut;
    }
    return MessageReading(
      kind: kind,
      kindConfidence: _confidence,
      fields: fields,
    );
  }

  @override
  void close() {}
}
