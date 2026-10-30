import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../domain/privacy/privacy_policy.dart';

/// Loads the document [name] bundled under `assets/policy/`: its text from
/// `<name>.md` and its version and changes from `<name>.json`.
Future<PrivacyPolicy> loadBundledDocument(
  AssetBundle bundle,
  String name,
) async {
  final metadata = jsonDecode(
    await bundle.loadString('assets/policy/$name.json'),
  );
  final markdown = await bundle.loadString('assets/policy/$name.md');
  return PrivacyPolicy.fromAssets(
    metadata: metadata as Map<String, Object?>,
    markdown: markdown,
  );
}

/// Loads the privacy policy bundled under `assets/policy/`.
Future<PrivacyPolicy> loadBundledPolicy(AssetBundle bundle) =>
    loadBundledDocument(bundle, 'privacy_policy');

/// The privacy policy that ships with this build of the app.
final privacyPolicyProvider = FutureProvider<PrivacyPolicy>(
  (ref) => loadBundledPolicy(rootBundle),
);

/// The terms that ship with this build of the app.
final termsProvider = FutureProvider<PrivacyPolicy>(
  (ref) => loadBundledDocument(rootBundle, 'terms'),
);

/// Hands the policy to the phone's email app as a draft to the person.
abstract interface class PolicyMailer {
  /// Opens a draft with [subject] and [body]. Returns false when no email
  /// app could take it.
  Future<bool> compose({required String subject, required String body});
}

/// Opens a `mailto:` link, which Android sends to the chosen email app.
class MailtoPolicyMailer implements PolicyMailer {
  const MailtoPolicyMailer();

  @override
  Future<bool> compose({required String subject, required String body}) {
    // Uri's queryParameters encodes spaces as `+`, which mail apps show as is.
    final uri = Uri.parse(
      'mailto:?subject=${Uri.encodeComponent(subject)}'
      '&body=${Uri.encodeComponent(body)}',
    );
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }
}

final policyMailerProvider = Provider<PolicyMailer>(
  (ref) => const MailtoPolicyMailer(),
);
