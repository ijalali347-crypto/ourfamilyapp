import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'login_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const OurFamilyApp());
}

class OurFamilyApp extends StatelessWidget {
  const OurFamilyApp({super.key});

  @override
  Widget build(BuildContext context) {
    const blue = Color(0xFF1F6AA5);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Our Family',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: blue),
        scaffoldBackgroundColor: const Color(0xFFF7FAFC),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
        ),
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
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 96,
                    height: 96,
                    decoration: const BoxDecoration(color: Color(0xFFE0F1FC), shape: BoxShape.circle),
                    child: const Icon(Icons.family_restroom, size: 54, color: Color(0xFF1F6AA5)),
                  ),
                  const SizedBox(height: 28),
                  const Text('Our Family', textAlign: TextAlign.center, style: TextStyle(fontSize: 34, fontWeight: FontWeight.bold, color: Color(0xFF163B5C))),
                  const SizedBox(height: 12),
                  const Text('Private chats and groups for the people you love.', textAlign: TextAlign.center, style: TextStyle(fontSize: 17, color: Colors.black54)),
                  const SizedBox(height: 36),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: FilledButton(
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const LoginScreen())),
                      child: const Text('Continue securely'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
