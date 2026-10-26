import 'package:flutter/material.dart';

/// Shown while app lock settings and saved onboarding state load.
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
