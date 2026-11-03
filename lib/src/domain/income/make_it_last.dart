import '../time/calendar.dart';

/// Days after money arrives that Home offers to make it last.
const makeItLastOfferDays = 3;

/// The daily amount the person chose to make money from [arrivalId] last
/// until [until].
class MakeItLastPin {
  const MakeItLastPin({
    required this.arrivalId,
    required this.dailyMinor,
    required this.until,
  });

  final int arrivalId;
  final int dailyMinor;
  final CalendarDate until;

  /// The pin holds through [until], until newer money arrives.
  bool appliesOn(CalendarDate today, {required int? latestArrivalId}) =>
      latestArrivalId == arrivalId && !today.isAfter(until);

  static MakeItLastPin? fromJson(Map<String, Object?>? json) {
    if (json == null) return null;
    final arrival = json['arrivalId'];
    final daily = json['dailyMinor'];
    final until = json['until'];
    if (arrival is! int || daily is! int || daily < 0 || until is! String) {
      return null;
    }
    final parts = until.split('-').map(int.tryParse).toList();
    if (parts.length != 3 || parts.contains(null)) return null;
    return MakeItLastPin(
      arrivalId: arrival,
      dailyMinor: daily,
      until: CalendarDate(parts[0]!, parts[1]!, parts[2]!),
    );
  }

  Map<String, Object?> toJson() => {
    'arrivalId': arrivalId,
    'dailyMinor': dailyMinor,
    'until': until.toString(),
  };
}
