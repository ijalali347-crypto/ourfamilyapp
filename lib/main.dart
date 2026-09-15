import 'package:flutter/material.dart';

void main() {
  runApp(const OurFamilyApp());
}

class OurFamilyApp extends StatelessWidget {
  const OurFamilyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Our Family App',
      theme: ThemeData(
        useMaterial3: true,
      ),
      home: const WelcomeScreen(),
    );
  }
}

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.family_restroom,
                size: 100,
              ),
              const SizedBox(height: 24),
              const Text(
                'Our Family App',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Private communication for our family',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18),
              ),
              const SizedBox(height: 40),
              FilledButton(
                onPressed: () {},
                child: const Text('Get Started'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
