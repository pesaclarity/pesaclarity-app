import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderException;

import '../../domain/ml/rayo_only.dart';

/// The [RayoOnlyFailure] in [error], unwrapping a provider's rethrow.
RayoOnlyFailure? rayoFailureIn(Object error) => switch (error) {
  final RayoOnlyFailure failure => failure,
  ProviderException(:final exception) => rayoFailureIn(exception),
  _ => null,
};

/// A provider's retry: none for a rayo-only failure, which the same build
/// on the same phone always repeats, else Riverpod's.
Duration? noRetryOnRayoFailure(int count, Object error) =>
    rayoFailureIn(error) != null
    ? null
    : ProviderContainer.defaultRetry(count, error);
