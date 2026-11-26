import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/time/clock.dart';
import '../../../domain/firefly/firefly_server.dart';
import '../../../domain/time/calendar.dart';
import '../../../shared/adaptive/adaptive.dart';
import '../../../shared/semantic_ids.dart';
import '../../../shared/widgets/app_sheet.dart';
import '../../../shared/widgets/choice_menu.dart';
import '../../../shared/widgets/figures.dart';
import '../../../shared/widgets/form_fields.dart';
import '../../../shared/widgets/marks.dart';
import '../../../shared/widgets/sections.dart';
import '../../../shared/widgets/states.dart';
import '../../../theme/pesa_colors.dart';
import '../application/firefly_controller.dart';
import '../application/firefly_service.dart';
import '../application/firefly_settings.dart';

/// Firefly III, under Profile (decision 0029): setting up, then where it
/// sends, what waits and what went wrong. Problems with sending show here
/// and nowhere else.
class FireflyScreen extends ConsumerStatefulWidget {
  const FireflyScreen({super.key});

  @override
  ConsumerState<FireflyScreen> createState() => _FireflyScreenState();
}

class _FireflyScreenState extends ConsumerState<FireflyScreen> {
  final _address = TextEditingController();
  final _token = TextEditingController();
  bool _showToken = false;
  bool _busy = false;
  bool _filled = false;

  /// What the last Check connection found.
  FireflyCheck? _check;

  /// Setting up: which spaces to send, and from when.
  final _chosen = <String>{};
  bool _chosenSet = false;
  FireflySendFrom _from = FireflySendFrom.thisYear;
  int? _toSend;

  FireflyController get _controller =>
      ref.read(fireflyControllerProvider.notifier);

  @override
  void dispose() {
    _address.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _run(Future<void> Function() work) async {
    setState(() => _busy = true);
    try {
      await work();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _checkConnection({required bool typedToken}) => _run(() async {
    var result = await _controller.check(
      _address.text,
      token: typedToken ? _token.text : null,
    );
    if (result is FireflyNeedsPlainConfirm) {
      if (!mounted || !await _confirmPlain()) return;
      await _controller.confirmPlain(_address.text);
      result = await _controller.check(
        _address.text,
        token: typedToken ? _token.text : null,
      );
    }
    if (result case FireflyAskTrust(:final host, :final sha256)) {
      if (!mounted || !await _askTrust(host, sha256)) return;
      await _controller.trust(host, sha256);
      result = await _controller.check(
        _address.text,
        token: typedToken ? _token.text : null,
      );
    }
    if (result is FireflyConnected) _token.clear();
    if (mounted) setState(() => _check = result);
  });

  /// Asks with [sheet], the progress bar off while it is open.
  Future<bool> _ask(WidgetBuilder sheet) async {
    setState(() => _busy = false);
    final yes = await showAppSheet<bool>(context: context, builder: sheet);
    if (mounted) setState(() => _busy = true);
    return yes ?? false;
  }

  Future<bool> _confirmPlain() => _ask(
    (context) => SheetBody(
      title: 'Use a plain connection?',
      subtitle:
          'This connection is not encrypted. Use it only on your home '
          'network.',
      children: [
        ButtonPair(
          primary: FilledButton(
            key: const Key('firefly-plain-yes'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Use it'),
          ),
          secondary: OutlinedButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
        ),
      ],
    ),
  );

  Future<bool> _askTrust(String host, String sha256) =>
      _ask((context) => TrustCertificateSheet(host: host, sha256: sha256));

  Future<void> _turnOff(int waiting) async {
    final off = await showAppSheet<bool>(
      context: context,
      builder: (context) => TurnOffSheet(waiting: waiting),
    );
    if (off ?? false) await _run(_controller.turnOff);
  }

  Future<void> _countToSend(List<FireflySpaceChoice> spaces) async {
    final today = CalendarDate.local(ref.read(clockProvider)());
    final count = await ref
        .read(fireflyServiceProvider)
        .countToSend(_chosen, fireflyFromDay(_from, today));
    if (mounted) setState(() => _toSend = count);
  }

  @override
  Widget build(BuildContext context) {
    final view = ref.watch(fireflyControllerProvider);
    final value = view.value;
    return Scaffold(
      appBar: AppBar(
        title: Semantics(
          identifier: SemanticIds.titleFirefly,
          child: const Text('Firefly III'),
        ),
        actions: [
          if (value != null && value.settings.on)
            PopupMenuButton<String>(
              key: const Key('firefly-menu'),
              tooltip: 'More',
              onSelected: (_) =>
                  _run(() => _controller.sendNow(resendAll: true)),
              itemBuilder: (context) => const [
                PopupMenuItem(
                  value: 'again',
                  child: Text('Send everything again'),
                ),
              ],
            ),
        ],
      ),
      body: switch (view) {
        AsyncData(:final value) => _body(context, value),
        AsyncError() => ErrorView(
          'Firefly III could not load.',
          onRetry: () => ref.invalidate(fireflyControllerProvider),
        ),
        _ => const LoadingView(),
      },
    );
  }

  Widget _body(BuildContext context, FireflyView view) {
    final settings = view.settings;
    if (!_filled) {
      _filled = true;
      _address.text = settings.address ?? '';
      _from = settings.sendFrom;
    }
    if (!_chosenSet) {
      _chosenSet = true;
      _chosen.addAll([
        for (final s in view.spaces)
          if (s.sending || !settings.on) s.space.id,
      ]);
      if (!settings.on) Future.microtask(() => _countToSend(view.spaces));
    }
    final children = !settings.on
        ? _setUp(context, view)
        : settings.problem == FireflyProblem.tokenRefused
        ? _tokenRefused(context, view)
        : _sending(context, view);
    return ListView(
      key: const Key('firefly-list'),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      children: [
        ...children,
        if (_busy) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
        ],
      ],
    );
  }

  // Setting up (mockup 2).
  List<Widget> _setUp(BuildContext context, FireflyView view) {
    final theme = Theme.of(context);
    final connected = _check is FireflyConnected;
    return [
      Text(
        'Send your transactions to your own Firefly III server. They go only '
        'to the server you choose, never to Pesa Clarity.',
        style: theme.textTheme.bodyLarge!.copyWith(
          color: PesaColors.of(context).textMuted,
        ),
      ),
      const SectionLabel('Your server'),
      ..._serverFields(context),
      OutlinedButton(
        key: const Key('firefly-check'),
        onPressed: _busy ? null : () => _checkConnection(typedToken: true),
        child: const Text('Check connection'),
      ),
      if (_check != null) ...[const SizedBox(height: 12), _checkNotice()],
      ..._whatToSend(context, view, setUp: true),
      const SizedBox(height: 20),
      FilledButton(
        key: const Key('firefly-start'),
        onPressed: connected && !_busy && _chosen.isNotEmpty
            ? () => _run(() => _controller.start({..._chosen}, _from))
            : null,
        child: const Text('Start sending'),
      ),
      const SizedBox(height: 12),
      _note(
        context,
        _toSend == null
            ? 'If you close the app, it carries on next time.'
            : '${_count(_toSend!)} ${_toSend == 1 ? 'transaction' : 'transactions'} '
                  'to send. If you close the app, it carries on next time.',
      ),
    ];
  }

  Widget _checkNotice() => switch (_check) {
    FireflyConnected(:final version) => Notice(
      'Connected to Firefly III $version.',
      icon: Icons.check,
      key: const Key('firefly-connected'),
    ),
    FireflyCheckFailed(:final message) => Notice(
      message,
      icon: Icons.error_outline,
      problem: true,
      key: const Key('firefly-check-failed'),
    ),
    _ => const SizedBox.shrink(),
  };

  List<Widget> _serverFields(
    BuildContext context, {
    bool tokenRefused = false,
  }) {
    final failed = _check;
    final tokenError = tokenRefused
        ? 'The saved token was refused.'
        : failed is FireflyCheckFailed && failed.token
        ? failed.message
        : null;
    return [
      LabeledField(
        label: 'Server address',
        child: TextField(
          key: const Key('firefly-address'),
          controller: _address,
          keyboardType: TextInputType.url,
          autocorrect: false,
          enableSuggestions: false,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            hintText: 'https://firefly.example.home',
          ),
        ),
      ),
      const SizedBox(height: 16),
      LabeledField(
        label: 'Personal access token',
        child: TextField(
          key: const Key('firefly-token'),
          controller: _token,
          obscureText: !_showToken,
          autocorrect: false,
          enableSuggestions: false,
          keyboardType: TextInputType.visiblePassword,
          decoration: InputDecoration(
            hintText: tokenRefused ? 'Paste a new token' : null,
            errorText: tokenError,
            helperText: tokenError == null
                ? 'Make one in Firefly III under Profile, Remote access and '
                      'tokens. It stays on this phone and is never in backups.'
                : null,
            helperMaxLines: 3,
            suffixIcon: IconButton(
              tooltip: _showToken ? 'Hide token' : 'Show token',
              icon: Icon(
                _showToken
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
              ),
              onPressed: () => setState(() => _showToken = !_showToken),
            ),
          ),
        ),
      ),
      const SizedBox(height: 16),
    ];
  }

  List<Widget> _whatToSend(
    BuildContext context,
    FireflyView view, {
    required bool setUp,
  }) {
    final today = CalendarDate.local(ref.watch(clockProvider)());
    return [
      const SectionLabel('What to send'),
      GroupedSection(
        footer:
            'Accounts, payees and categories are made in Firefly III as they '
            'are needed.',
        children: [
          for (final choice in view.spaces)
            SwitchListTile.adaptive(
              key: Key('firefly-space-${choice.space.id}'),
              value: setUp ? _chosen.contains(choice.space.id) : choice.sending,
              onChanged: _busy
                  ? null
                  : (on) {
                      if (setUp) {
                        setState(() {
                          on
                              ? _chosen.add(choice.space.id)
                              : _chosen.remove(choice.space.id);
                        });
                        _countToSend(view.spaces);
                      } else {
                        _run(() => _controller.setSpace(choice, on));
                      }
                    },
              title: Text(choice.space.name),
              subtitle: Text('Tagged "${choice.space.name}"'),
            ),
          ChoiceTile<FireflySendFrom>(
            key: const Key('firefly-from'),
            title: const Text('Send from'),
            trailing: ChoiceMenu<FireflySendFrom>(
              name: 'Send from',
              options: [
                for (final f in FireflySendFrom.values)
                  (f, fireflyFromLabel(f, today)),
              ],
              value: _from,
              itemKey: (f) => Key('firefly-from-${f.name}'),
              onChanged: (f) {
                setState(() => _from = f);
                if (setUp) {
                  _countToSend(view.spaces);
                } else {
                  _run(() => _controller.setFrom(f));
                }
              },
            ),
          ),
        ],
      ),
    ];
  }

  Widget _waitingCard(String detail, int waiting) => Card(
    child: LabelValueRow(
      key: const Key('firefly-waiting'),
      label: 'Changes waiting',
      detail: detail,
      value: _count(waiting),
    ),
  );

  // On (mockup 3) and can't reach the server (mockup 4a).
  List<Widget> _sending(BuildContext context, FireflyView view) {
    final settings = view.settings;
    final host = _wrappable(settings.host ?? '');
    final now = ref.watch(clockProvider)();
    final last = settings.lastSentAt;
    final lastSent = last == null ? null : sentAgoLabel(last, now);
    final problem = settings.problem;
    final notice = switch (problem) {
      null => Notice(
        lastSent == null
            ? 'Sending to $host.'
            : 'Sending to $host. Last sent $lastSent.',
        icon: Icons.check,
      ),
      FireflyProblem.unreachable => Notice(
        'Is the server on, and is this phone on its network?'
        '${lastSent == null ? '' : ' Last sent $lastSent.'}',
        lead: "Can't reach $host.",
        icon: Icons.error_outline,
        problem: true,
      ),
      FireflyProblem.certificate => Notice(
        'Check connection to see it and decide whether to trust it.',
        lead: '$host has a certificate this phone doesn\'t know.',
        icon: Icons.error_outline,
        problem: true,
      ),
      FireflyProblem.redirected => Notice(
        'Change the address to where Firefly III itself is.',
        lead: '$host sends the app somewhere else.',
        icon: Icons.error_outline,
        problem: true,
      ),
      FireflyProblem.notFirefly || FireflyProblem.tokenRefused => Notice(
        'Check the address, then Check connection.',
        lead: "$host doesn't answer as Firefly III 6 or later.",
        icon: Icons.error_outline,
        problem: true,
      ),
    };
    final stuck = problem != null;
    return [
      KeyedSubtree(key: const Key('firefly-status'), child: notice),
      const SizedBox(height: 12),
      _waitingCard(
        stuck
            ? 'Kept on this phone until it answers'
            : 'Sent when the phone is online',
        view.waiting,
      ),
      if (view.refused.isNotEmpty) ...[
        const SectionLabel('Firefly III refused'),
        GroupedSection(
          children: [
            for (final r in view.refused)
              ListTile(
                title: Text(r.reason),
                subtitle: Text('${r.space} · transaction ${r.transactionId}'),
              ),
          ],
        ),
      ],
      const SizedBox(height: 12),
      _PairOrStack(
        labels: [stuck ? 'Try again' : 'Send now', 'Check connection'],
        primary: FilledButton(
          key: const Key('firefly-send-now'),
          onPressed: _busy ? null : () => _run(_controller.sendNow),
          child: Text(stuck ? 'Try again' : 'Send now'),
        ),
        secondary: OutlinedButton(
          key: const Key('firefly-check'),
          onPressed: _busy ? null : () => _checkConnection(typedToken: false),
          child: const Text('Check connection'),
        ),
      ),
      if (_check is FireflyCheckFailed) ...[
        const SizedBox(height: 12),
        _checkNotice(),
      ],
      ..._whatToSend(context, view, setUp: false),
      const SectionLabel('Your server'),
      GroupedSection(
        children: [
          ListTile(
            key: const Key('firefly-server-address'),
            title: const Text('Server address'),
            subtitle: Text(settings.address ?? ''),
            trailing: const Icon(Icons.chevron_right),
            onTap: _busy ? null : () => _editServer(view, token: false),
          ),
          ListTile(
            key: const Key('firefly-server-token'),
            title: const Text('Personal access token'),
            subtitle: Text(
              view.tokenSaved ? 'Saved on this phone' : 'Not saved',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: _busy ? null : () => _editServer(view, token: true),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: TextButton(
          key: const Key('firefly-turn-off'),
          onPressed: _busy ? null : () => _turnOff(view.waiting),
          child: const Text('Turn off'),
        ),
      ),
    ];
  }

  // Token rejected (mockup 4b).
  List<Widget> _tokenRefused(BuildContext context, FireflyView view) => [
    const KeyedSubtree(
      key: Key('firefly-status'),
      child: Notice(
        'It may have expired or been deleted. Paste a new one to carry on.',
        lead: "Firefly III didn't accept the token.",
        icon: Icons.error_outline,
        problem: true,
      ),
    ),
    const SectionLabel('Your server'),
    ..._serverFields(context, tokenRefused: _check is! FireflyConnected),
    OutlinedButton(
      key: const Key('firefly-check'),
      onPressed: _busy ? null : () => _checkConnection(typedToken: true),
      child: const Text('Check connection'),
    ),
    const SizedBox(height: 12),
    _note(
      context,
      '${_count(view.waiting)} ${view.waiting == 1 ? 'change waits' : 'changes wait'} '
      'on this phone. Nothing is lost.',
    ),
  ];

  /// Changes the address or the token, then checks the connection.
  Future<void> _editServer(FireflyView view, {required bool token}) async {
    final field = TextEditingController(
      text: token ? '' : view.settings.address ?? '',
    );
    final saved = await showAppSheet<String>(
      context: context,
      builder: (context) => SheetBody(
        title: token ? 'Personal access token' : 'Server address',
        children: [
          TextField(
            key: const Key('firefly-edit-field'),
            controller: field,
            autofocus: true,
            obscureText: token,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: token
                ? TextInputType.visiblePassword
                : TextInputType.url,
            decoration: InputDecoration(
              hintText: token
                  ? 'Paste a new token'
                  : 'https://firefly.example.home',
            ),
          ),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () => Navigator.pop(context, field.text),
            child: const Text('Check and save'),
          ),
        ],
      ),
    );
    field.dispose();
    if (saved == null || saved.trim().isEmpty || !mounted) return;
    if (token) {
      _token.text = saved;
    } else {
      _address.text = saved;
    }
    await _checkConnection(typedToken: token);
    if (token) _token.clear();
  }

  Widget _note(BuildContext context, String text) => Text(
    text,
    style: Theme.of(context).textTheme.bodySmall!
        .copyWith(color: PesaColors.of(context).textMuted),
  );

  static String _count(int n) {
    final digits = n.toString();
    final out = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) out.write(',');
      out.write(digits[i]);
    }
    return out.toString();
  }
}

/// Two buttons side by side, as [ButtonPair] lays them out, while both
/// labels fit on one line; at larger text, one under the other, so no word
/// is drawn across two lines.
class _PairOrStack extends StatelessWidget {
  const _PairOrStack({
    required this.labels,
    required this.primary,
    required this.secondary,
  });

  final List<String> labels;
  final Widget primary;
  final Widget secondary;

  static const _tight = EdgeInsets.symmetric(horizontal: 12);

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelLarge;
    final scaler = MediaQuery.textScalerOf(context);
    double width(String label) {
      final painter = TextPainter(
        text: TextSpan(text: label, style: style),
        textDirection: Directionality.of(context),
        textScaler: scaler,
      )..layout();
      return painter.width;
    }

    // Each button's padding and edge.
    const padding = 26.0;
    final widest = labels.map(width).reduce((a, b) => a > b ? a : b);
    return LayoutBuilder(
      builder: (context, constraints) =>
          widest + padding <= (constraints.maxWidth - 12) / 2
          ? Theme(
              // A little less padding, so both labels keep to one line
              // side by side, as in the mockup.
              data: Theme.of(context).copyWith(
                filledButtonTheme: FilledButtonThemeData(
                  style:
                      (Theme.of(context).filledButtonTheme.style ??
                              const ButtonStyle())
                          .copyWith(
                            padding: const WidgetStatePropertyAll(_tight),
                          ),
                ),
                outlinedButtonTheme: OutlinedButtonThemeData(
                  style:
                      (Theme.of(context).outlinedButtonTheme.style ??
                              const ButtonStyle())
                          .copyWith(
                            padding: const WidgetStatePropertyAll(_tight),
                          ),
                ),
              ),
              child: ButtonPair(primary: primary, secondary: secondary),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [primary, const SizedBox(height: 12), secondary],
            ),
    );
  }
}

/// A host name that may wrap at its dots rather than inside a word.
String _wrappable(String host) => host.replaceAll('.', '.\u200B');

/// "Trust this certificate?" (mockup 4c): the server's SHA-256 fingerprint,
/// to compare with the one on the server. Trusting it is for this server
/// only, and asked again if the certificate changes.
class TrustCertificateSheet extends StatelessWidget {
  const TrustCertificateSheet({
    required this.host,
    required this.sha256,
    super.key,
  });

  final String host;
  final String sha256;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = PesaColors.of(context).textMuted;
    return SheetBody(
      title: 'Trust this certificate?',
      subtitle:
          "${_wrappable(host)} uses a certificate this phone doesn't know. "
          'Check that this fingerprint matches the one on your server.',
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'SHA-256 fingerprint',
                  style: theme.textTheme.bodySmall!.copyWith(color: muted),
                ),
                const SizedBox(height: 2),
                SelectableText(
                  spacedFingerprint(sha256),
                  key: const Key('firefly-fingerprint'),
                  style: theme.textTheme.bodyLarge!.copyWith(
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Only for this server. If the certificate changes, you are asked '
          'again.',
          style: theme.textTheme.bodySmall!.copyWith(color: muted),
        ),
        const SizedBox(height: 20),
        ButtonPair(
          primary: FilledButton(
            key: const Key('firefly-trust'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Trust it'),
          ),
          secondary: OutlinedButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
        ),
      ],
    );
  }
}

/// "Stop sending to Firefly III?" (mockup 5).
class TurnOffSheet extends StatelessWidget {
  const TurnOffSheet({required this.waiting, super.key});

  final int waiting;

  @override
  Widget build(BuildContext context) => SheetBody(
    title: 'Stop sending to Firefly III?',
    subtitle: waiting == 0
        ? 'What is already in Firefly III stays there. The token is removed '
              'from this phone.'
        : 'What is already in Firefly III stays there. The token and the '
              '$waiting ${waiting == 1 ? 'change' : 'changes'} waiting are '
              'removed from this phone.',
    children: [
      const SizedBox(height: 4),
      ButtonPair(
        primary: FilledButton(
          key: const Key('firefly-turn-off-confirm'),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Turn off'),
        ),
        secondary: OutlinedButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Keep sending'),
        ),
      ),
    ],
  );
}
