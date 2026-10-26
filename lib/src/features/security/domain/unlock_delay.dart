/// Wrong PINs allowed before the first wait.
const freePinAttempts = 4;

/// How long to wait before the next PIN try after [failedAttempts] wrong
/// PINs in a row. The wait grows with each wrong PIN, up to an hour.
Duration unlockDelayAfter(int failedAttempts) {
  if (failedAttempts <= freePinAttempts) return Duration.zero;
  return switch (failedAttempts - freePinAttempts) {
    1 => const Duration(seconds: 30),
    2 => const Duration(minutes: 1),
    3 => const Duration(minutes: 5),
    4 => const Duration(minutes: 15),
    _ => const Duration(hours: 1),
  };
}
