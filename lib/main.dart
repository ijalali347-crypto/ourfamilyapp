import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'glass_ui.dart';

import 'family_home.dart';
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
    const blue = Color(0xFF5B5FEF);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Chat Plus',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: blue, brightness: Brightness.light),
        scaffoldBackgroundColor: Colors.transparent,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          color: Colors.white.withOpacity(.50),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: const Color(0xFFF4F5FF).withOpacity(.94),
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: Colors.white.withOpacity(.72),
          indicatorColor: const Color(0xFF5B5FEF).withOpacity(.16),
          elevation: 0,
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: Color(0xFF5B5FEF),
          foregroundColor: Colors.white,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white.withOpacity(.58),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: Colors.white.withOpacity(.70))),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: BorderSide(color: Colors.white.withOpacity(.72))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(20), borderSide: const BorderSide(color: Color(0xFF5B5FEF), width: 1.5)),
        ),
      ),
      builder: (context, child) => GlassBackground(child: child ?? const SizedBox.shrink()),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) => StreamBuilder<User?>(
    stream: FirebaseAuth.instance.authStateChanges(),
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting)
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      return snapshot.data == null ? const WelcomeScreen() : const FamilyHome();
    },
  );
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
                    decoration: const BoxDecoration(
                      color: Color(0xFFE0F1FC),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.chat_bubble_outline,
                      size: 54,
                      color: Color(0xFF1F6AA5),
                    ),
                  ),
                  const SizedBox(height: 28),
                  const Text(
                    'Chat Plus',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF163B5C),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Your account. Your chats. Message anyone by username.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 17, color: Colors.black54),
                  ),
                  const SizedBox(height: 36),
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: FilledButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (context) => const LoginScreen(),
                          ),
                        );
                      },
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
