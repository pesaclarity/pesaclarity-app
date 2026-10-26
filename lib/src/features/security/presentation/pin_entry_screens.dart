import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/app_lock_controller.dart';
import '../domain/pin_hasher.dart';
import 'pin_pad.dart';

/// Asks for a new PIN twice. Pops with the PIN once both match.
class ChoosePinScreen extends StatefulWidget {
  const ChoosePinScreen({super.key});

  @override
  State<ChoosePinScreen> createState() => _ChoosePinScreenState();
}

class _ChoosePinScreenState extends State<ChoosePinScreen> {
  String? _first;
  bool _mismatch = false;

  Future<void> _onPin(String pin) async {
    final first = _first;
    if (first == null) {
      setState(() {
        _first = pin;
        _mismatch = false;
      });
    } else if (first == pin) {
      Navigator.of(context).pop(pin);
    } else {
      setState(() {
        _first = null;
        _mismatch = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return _PinScaffold(
      title: 'App lock',
      pad: PinPad(
        key: ValueKey(_first == null),
        title: _first == null
            ? 'Choose a $pinLength-digit PIN'
            : 'Enter the PIN again',
        message: _mismatch
            ? 'The PINs did not match. Choose a PIN again.'
            : _first == null
            ? 'You will use it to open Pesa Clarity.'
            : null,
        messageIsError: _mismatch,
        onCompleted: _onPin,
      ),
    );
  }
}

/// Asks for the current PIN. Pops with true once it is right.
class ConfirmPinScreen extends ConsumerStatefulWidget {
  const ConfirmPinScreen({super.key});

  @override
  ConsumerState<ConfirmPinScreen> createState() => _ConfirmPinScreenState();
}

class _ConfirmPinScreenState extends ConsumerState<ConfirmPinScreen> {
  PinCheck? _last;

  Future<void> _onPin(String pin) async {
    final result = await ref
        .read(appLockControllerProvider.notifier)
        .enterPin(pin);
    if (!mounted) return;
    if (result == PinCheck.correct) {
      Navigator.of(context).pop(true);
    } else {
      setState(() => _last = result);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(appLockControllerProvider);
    final waiting =
        ref.read(appLockControllerProvider.notifier).retryAt != null;
    return _PinScaffold(
      title: 'App lock',
      pad: PinPad(
        title: 'Enter your current PIN',
        message: waiting
            ? 'Too many wrong PINs. Try again later.'
            : _last == PinCheck.wrong
            ? 'Wrong PIN.'
            : null,
        messageIsError: waiting || _last == PinCheck.wrong,
        enabled: !waiting,
        onCompleted: _onPin,
      ),
    );
  }
}

class _PinScaffold extends StatelessWidget {
  const _PinScaffold({required this.title, required this.pad});

  final String title;
  final Widget pad;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: pad,
          ),
        ),
      ),
    );
  }
}
