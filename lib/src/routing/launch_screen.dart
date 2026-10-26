import 'package:flutter/material.dart';

/// Shown for the moment it takes to read saved onboarding state.
class LaunchScreen extends StatelessWidget {
  const LaunchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(
          semanticsLabel: 'Opening Pesa Clarity',
        ),
      ),
    );
  }
}
