import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/time/clock.dart';
import '../../../data/repositories/app_settings_repository.dart';
import '../../../domain/time/business_day.dart';
import '../../../domain/time/calendar.dart';

/// When the open space's business day ends, kept with the space.
class BusinessDayController extends AsyncNotifier<BusinessDay> {
  static const settingsKey = 'business.day';

  @override
  Future<BusinessDay> build() async => BusinessDay.fromJson(
    await ref.watch(appSettingsRepositoryProvider).readJson(settingsKey),
  );

  Future<void> save(BusinessDay next) async {
    await ref
        .read(appSettingsRepositoryProvider)
        .writeJson(settingsKey, next.toJson());
    state = AsyncData(next);
  }
}

final businessDayProvider =
    AsyncNotifierProvider<BusinessDayController, BusinessDay>(
      BusinessDayController.new,
    );

/// The business day it is now.
final businessTodayProvider = FutureProvider<CalendarDate>((ref) async {
  final business = await ref.watch(businessDayProvider.future);
  return business.dayOf(ref.watch(clockProvider)());
});
