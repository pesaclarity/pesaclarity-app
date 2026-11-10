import 'package:flutter_test/flutter_test.dart';
import 'package:pesaclarity/src/features/support/domain/support.dart';

void main() {
  group('SupportConfig', () {
    test('needs an https giving page', () {
      expect(SupportConfig.parse(url: '', payees: '', costs: ''), isNull);
      expect(
        SupportConfig.parse(
          url: 'http://pay.example.org',
          payees: '',
          costs: '',
        ),
        isNull,
      );
      final config = SupportConfig.parse(
        url: ' https://pay.example.org/pay/@test?amount={amount} ',
        payees: ' Test Payee , 000000 ,',
        costs: 'ftp://example.org/costs',
      )!;
      expect(config.takesAmount, isTrue);
      expect(
        config.link(200).toString(),
        'https://pay.example.org/pay/@test?amount=200',
      );
      expect(config.payees, {'test payee', '000000'});
      expect(config.knowsGifts, isTrue);
      expect(config.costs, isNull, reason: 'only https');
    });

    test('a page without {amount} opens as it is', () {
      final config = SupportConfig.parse(
        url: 'https://pay.example.org/pay/@test',
        payees: '',
        costs: 'https://example.org/sponsor/',
      )!;
      expect(config.takesAmount, isFalse);
      expect(config.link().toString(), 'https://pay.example.org/pay/@test');
      expect(config.knowsGifts, isFalse);
      expect(config.costs.toString(), 'https://example.org/sponsor/');
    });

    test('a gift is a payment to one of the payees', () {
      final config = SupportConfig.parse(
        url: 'https://pay.example.org',
        payees: 'Test Payee,000000',
        costs: '',
      )!;
      expect(config.isGiftTo(name: 'TEST PAYEE'), isTrue);
      expect(config.isGiftTo(number: '000000'), isTrue);
      expect(config.isGiftTo(name: 'Green Basket'), isFalse);
      expect(config.isGiftTo(), isFalse);
    });
  });

  group('the Home card', () {
    final start = DateTime.utc(2026, 10);
    SupportCardTime at(
      DateTime now, {
      SupportState? state,
      bool tight = false,
      DateTime? lastGift,
    }) => supportCardTime(
      state: state ?? SupportState(firstSeenAt: start),
      now: now,
      moneyTight: tight,
      lastGiftAt: lastGift,
    );

    test('never asks in the first 30 days', () {
      expect(at(start.add(const Duration(days: 29))), SupportCardTime.hidden);
      expect(
        at(start.add(const Duration(days: 30))),
        SupportCardTime.startsNow,
      );
    });

    test('shows for 3 days, then rests until 60 days after it started', () {
      final shown = start.add(const Duration(days: 31));
      final state = SupportState(
        firstSeenAt: start,
        showingSince: shown,
        restUntil: shown.add(supportRestFor),
      );
      expect(
        at(shown.add(const Duration(days: 2)), state: state),
        SupportCardTime.showing,
      );
      expect(
        at(shown.add(const Duration(days: 3)), state: state),
        SupportCardTime.hidden,
      );
      expect(
        at(shown.add(const Duration(days: 59)), state: state),
        SupportCardTime.hidden,
      );
      expect(
        at(shown.add(const Duration(days: 60)), state: state),
        SupportCardTime.startsNow,
      );
    });

    test('a tap ends the showing at once', () {
      final shown = start.add(const Duration(days: 31));
      final tapped = SupportState(
        firstSeenAt: start,
        restUntil: shown.add(supportRestFor),
      );
      expect(
        at(shown.add(const Duration(days: 1)), state: tapped),
        SupportCardTime.hidden,
      );
    });

    test('never when money is tight, after a recent gift or once refused', () {
      final now = start.add(const Duration(days: 40));
      expect(at(now, tight: true), SupportCardTime.hidden);
      expect(
        at(now, lastGift: now.subtract(const Duration(days: 100))),
        SupportCardTime.hidden,
      );
      expect(
        at(now, lastGift: now.subtract(const Duration(days: 200))),
        SupportCardTime.startsNow,
      );
      expect(
        at(now, state: SupportState(firstSeenAt: start, optedOut: true)),
        SupportCardTime.hidden,
      );
      expect(at(now, state: const SupportState()), SupportCardTime.hidden);
    });
  });

  test('thanks the newest recent gift once', () {
    final now = DateTime.utc(2026, 11, 14, 9);
    final gifts = [
      Gift(
        id: 3,
        at: now.subtract(const Duration(hours: 1)),
        amountMinor: 20000,
      ),
      Gift(
        id: 2,
        at: now.subtract(const Duration(days: 30)),
        amountMinor: 5000,
      ),
    ];
    expect(giftToThank(gifts, const SupportState(), now)?.id, 3);
    expect(giftToThank(gifts, const SupportState(thanked: {3}), now), isNull);
    expect(giftToThank(const [], const SupportState(), now), isNull);
  });

  test('what the app remembers survives a save', () {
    final state = SupportState(
      firstSeenAt: DateTime.utc(2026, 10),
      showingSince: DateTime.utc(2026, 11),
      restUntil: DateTime.utc(2026, 12, 31),
      optedOut: true,
      thanked: const {4, 2},
    );
    final back = SupportState.fromJson(state.toJson());
    expect(back.firstSeenAt, state.firstSeenAt);
    expect(back.showingSince, state.showingSince);
    expect(back.restUntil, state.restUntil);
    expect(back.optedOut, isTrue);
    expect(back.thanked, {2, 4});
    expect(SupportState.fromJson(null).firstSeenAt, isNull);
  });
}
