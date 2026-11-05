import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/money/money.dart';
import '../../../core/money/money_format.dart';
import '../../../data/repositories/app_settings_repository.dart';
import '../../../domain/people/people.dart';
import '../../../domain/people/phone_number.dart';
import '../../../domain/people/reminder_text.dart';
import '../../../domain/time/calendar.dart';
import '../../../domain/time/date_labels.dart';

/// A business's reminder messages, default app, till and daily nudge.
class ReminderSetupController extends AsyncNotifier<ReminderSetup> {
  static const settingsKey = 'reminders.setup';

  @override
  Future<ReminderSetup> build() async => ReminderSetup.fromJson(
    await ref.watch(appSettingsRepositoryProvider).readJson(settingsKey),
    BaseCurrency.code,
  );

  Future<void> save(ReminderSetup next) async {
    await ref
        .read(appSettingsRepositoryProvider)
        .writeJson(settingsKey, next.toJson());
    state = AsyncData(next);
  }
}

final reminderSetupProvider =
    AsyncNotifierProvider<ReminderSetupController, ReminderSetup>(
      ReminderSetupController.new,
    );

/// The fields a reminder for [c] fills in.
Map<String, String?> reminderValues(
  CustomerAccount c, {
  required String business,
  required CalendarDate today,
  String? till,
}) {
  final due = c.nextDue;
  final what = c.history
      .where((l) => l.amountMinor > 0 && l.label != 'On credit')
      .map((l) => l.label.replaceFirst(RegExp(r' on credit$'), ''))
      .firstOrNull;
  return {
    'name': c.name,
    'business': business,
    'amount': formatMoney(Money(c.owedMinor), withCurrency: false),
    'what': what,
    'due': due == null
        ? null
        : due == today
        ? 'today'
        : dayLabel(due, thisYear: today.year),
    'date': c.since == null ? null : dayLabel(c.since!, thisYear: today.year),
    'till': till,
  };
}

/// A phone number picked from the phone's own contact list.
typedef PickedContact = ({String number, String name});

/// The phone's contact picker: it hands back only the contact chosen, so
/// no contacts permission is needed.
abstract interface class ContactPicker {
  /// Null when nothing was chosen.
  Future<PickedContact?> pickPhone();
}

class PlatformContactPicker implements ContactPicker {
  const PlatformContactPicker();

  static const _channel = MethodChannel('com.pesaclarity.app/share');

  @override
  Future<PickedContact?> pickPhone() async {
    final picked = await _channel.invokeMapMethod<String, Object?>('pickPhone');
    final number = picked?['number'];
    if (number is! String || number.trim().isEmpty) return null;
    final name = picked?['name'];
    return (number: number, name: name is String ? name : '');
  }
}

final contactPickerProvider = Provider<ContactPicker>(
  (ref) => const PlatformContactPicker(),
);

/// Opens WhatsApp or the SMS app with the message filled in; the owner taps
/// send there.
abstract interface class MessageLauncher {
  /// Returns false when no app could open it.
  Future<bool> open(SendWith app, String international, String text);
}

class PlatformMessageLauncher implements MessageLauncher {
  const PlatformMessageLauncher();

  @override
  Future<bool> open(SendWith app, String international, String text) {
    final uri = switch (app) {
      SendWith.whatsapp => whatsAppLink(international, text),
      SendWith.sms => smsLink(
        international,
        text,
        iPhone: defaultTargetPlatform == TargetPlatform.iOS,
      ),
    };
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

final messageLauncherProvider = Provider<MessageLauncher>(
  (ref) => const PlatformMessageLauncher(),
);
