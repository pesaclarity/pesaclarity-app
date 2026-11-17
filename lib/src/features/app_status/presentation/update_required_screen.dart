import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/build_info.dart';
import '../../../shared/widgets/marks.dart';
import '../../../theme/layout.dart';
import '../../../theme/pesa_colors.dart';
import '../application/app_status_providers.dart';
import '../application/update_links.dart';
import '../domain/app_status.dart';

/// Shows [UpdateRequiredScreen] over the whole app while a verified notice
/// says this version gets amounts wrong. Anything else, including no answer
/// or one that failed its checks, shows the app.
class UpdateRequiredGate extends ConsumerWidget {
  const UpdateRequiredGate({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notice = ref.watch(blockingNoticeProvider);
    if (notice == null) return child;
    return UpdateRequiredScreen(
      notice: notice,
      currentVersion: ref.watch(buildVersionProvider).trim(),
      onUpdate: () => openUpdate(ref),
    );
  }
}

/// "Please update Pesa Clarity": why, and Update now. Back cannot close it.
class UpdateRequiredScreen extends StatelessWidget {
  const UpdateRequiredScreen({
    required this.notice,
    required this.currentVersion,
    required this.onUpdate,
    super.key,
  });

  final AppNotice notice;
  final String currentVersion;
  final VoidCallback onUpdate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = PesaColors.of(context);
    final paragraphs = notice.body
        .split(RegExp(r'\n\s*\n'))
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty);
    return PopScope(
      canPop: false,
      child: Scaffold(
        key: const Key('update-required'),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: const EdgeInsets.all(Layout.gutter),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: (constraints.maxHeight - Layout.gutter * 2).clamp(
                    0,
                    double.infinity,
                  ),
                ),
                child: IntrinsicHeight(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Align(
                        alignment: Alignment.centerLeft,
                        child: AppMark(),
                      ),
                      const SizedBox(height: 96),
                      Semantics(
                        header: true,
                        child: Text(
                          'Please update Pesa Clarity',
                          style: theme.textTheme.headlineLarge!.copyWith(
                            fontWeight: FontWeight.w700,
                            fontVariations: const [FontVariation.weight(700)],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      for (final paragraph in paragraphs)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Text(
                            paragraph,
                            style: theme.textTheme.bodyLarge!.copyWith(
                              color: colors.textMuted,
                              height: 1.5,
                            ),
                          ),
                        ),
                      const Spacer(),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: onUpdate,
                        child: const Text('Update now'),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _versions(currentVersion, notice),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall!.copyWith(
                          color: colors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "You're on 0.3.0 · 0.3.2 or newer is needed".
String _versions(String current, AppNotice notice) =>
    "You're on $current · ${notice.minVersion} or newer is needed";
