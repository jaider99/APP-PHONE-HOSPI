import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class BootstrapErrorApp extends StatelessWidget {
  const BootstrapErrorApp({
    required this.error,
    super.key,
  });

  final String error;

  @override
  Widget build(BuildContext context) {
    final message = kReleaseMode
        ? 'The app could not start. Please contact support.'
        : error;

    return MaterialApp(
      title: 'HospiDash',
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Startup configuration error',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SelectableText(message),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
