/// Set by the test builds (`--dart-define=RAYO_ONLY=true`), never by
/// release builds. When on, the on-phone models run on rayo or not at all:
/// no Dart, rules or template stand-in hides a rayo failure.
const bool rayoOnly = bool.fromEnvironment('RAYO_ONLY');

/// A model that rayo could not run in a rayo-only build, and why.
class RayoOnlyFailure implements Exception {
  const RayoOnlyFailure(this.model, this.reason);

  final OnPhoneModel model;
  final String reason;

  @override
  String toString() => 'Rayo failed: ${model.label}: $reason';
}

/// The models the app runs on the phone.
enum OnPhoneModel {
  askReader('Ask reader'),
  askWriter('Ask writer'),
  messageReader('Message reader'),
  categoriser('Categoriser');

  const OnPhoneModel(this.label);

  final String label;
}
