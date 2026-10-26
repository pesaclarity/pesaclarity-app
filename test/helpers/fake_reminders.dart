import 'package:pesaclarity/src/domain/reminders/reminder_schedule.dart';
import 'package:pesaclarity/src/features/privacy/data/policy_source.dart';
import 'package:pesaclarity/src/features/reminders/data/reminder_notifications.dart';

/// Records what would be scheduled on the phone.
class FakeReminderNotifications implements ReminderNotifications {
  FakeReminderNotifications({this.grant = true});

  /// What the permission dialog answers.
  bool grant;
  int permissionRequests = 0;
  int cancels = 0;

  /// Every list passed to [replaceAll], latest last.
  final schedules = <List<Reminder>>[];

  List<Reminder> get scheduled => schedules.isEmpty ? const [] : schedules.last;

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    return grant;
  }

  @override
  Future<void> replaceAll(List<Reminder> reminders) async =>
      schedules.add(reminders);

  @override
  Future<void> cancelAll() async {
    cancels++;
    schedules.add(const []);
  }
}

/// Records drafts instead of opening an email app.
class FakePolicyMailer implements PolicyMailer {
  FakePolicyMailer({this.opens = true});

  final bool opens;
  final drafts = <({String subject, String body})>[];

  @override
  Future<bool> compose({required String subject, required String body}) async {
    drafts.add((subject: subject, body: body));
    return opens;
  }
}
