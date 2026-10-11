import 'dart:convert';
import 'dart:html' as html;
import 'dart:js_util' as js;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';

class CallNotifications {
  static DocumentReference<Map<String, dynamic>>? _device;
  static Future<void> enable(String uid) async {
    const key = String.fromEnvironment('FCM_VAPID_KEY');
    if (key.isEmpty)
      throw StateError(
          'Background notifications need Firebase setup. The open-app ringtone is enabled.');
    if (!js.hasProperty(html.window, 'enableChatNotifications')) {
      final script = html.ScriptElement()..src = 'chat_notifications.js';
      final loaded = script.onLoad.first;
      html.document.head!.append(script);
      await loaded.timeout(const Duration(seconds: 15));
    }
    final options = DefaultFirebaseOptions.web;
    final token = await js.promiseToFuture<String>(
        js.callMethod(html.window, 'enableChatNotifications', [
      key,
      js.jsify({
        'apiKey': options.apiKey,
        'appId': options.appId,
        'projectId': options.projectId,
        'messagingSenderId': options.messagingSenderId,
        'authDomain': options.authDomain,
      })
    ]));
    if (token.isEmpty) throw StateError('No notification token was returned.');
    _device = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('pushTokens')
        .doc(base64Url.encode(utf8.encode(token)));
    await _device!
        .set({'token': token, 'updatedAt': FieldValue.serverTimestamp()});
  }

  static Future<void> disable() async {
    await _device?.delete();
    _device = null;
    if (js.hasProperty(html.window, 'disableChatNotifications')) {
      await js.promiseToFuture(
          js.callMethod(html.window, 'disableChatNotifications', []));
    }
  }
}
