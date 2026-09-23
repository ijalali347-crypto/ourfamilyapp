import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) return web;
    throw UnsupportedError('Firebase options are currently configured for web.');
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyAi2k2dK7nE7oFI3Y3ikfy5opSep-8Qb84',
    appId: '1:1066197684028:web:c7ecbb5e8d613f3da99839',
    messagingSenderId: '1066197684028',
    projectId: 'our-family-app-9e21a',
    authDomain: 'our-family-app-9e21a.firebaseapp.com',
    storageBucket: 'our-family-app-9e21a.firebasestorage.app',
  );
}
