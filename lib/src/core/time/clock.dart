import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The current time. Override in tests to fix "today".
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);
