import 'dart:convert';
import 'dart:html' as html;
import 'dart:js_interop';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'firebase_options.dart';

@JS('enableChatNotifications')
external JSPromise<JSString> _enableNotifications(
    JSString key, JSObject config);
@JS('disableChatNotifications')
external JSPromise<JSBoolean> _disableNotifications();

class CallNotifications {
  static bool _loaded = false;
  static DocumentReference<Map<String, dynamic>>? _device;
  static Future<void> enable(String uid) async {
    const key = String.fromEnvironment('FCM_VAPID_KEY');
    if (key.isEmpty)
      throw StateError(
          'Background notifications need Firebase setup. The open-app ringtone is enabled.');
    if (!_loaded) {
      final script = html.ScriptElement()..src = 'chat_notifications.js';
      final loaded = script.onLoad.first;
      html.document.head!.append(script);
      await loaded.timeout(const Duration(seconds: 15));
      _loaded = true;
    }
    final options = DefaultFirebaseOptions.web;
    final result = await _enableNotifications(
            key.toJS,
            {
              'apiKey': options.apiKey,
              'appId': options.appId,
              'projectId': options.projectId,
              'messagingSenderId': options.messagingSenderId,
              'authDomain': options.authDomain,
            }.jsify() as JSObject)
        .toDart;
    final token = result.toDart;
    if (token.isEmpty) throw StateError('No notification token was returned.');
    _device = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('pushTokens')
        .doc(base64Url.encode(utf8.encode(token)));
    html.window.localStorage['chatPlusPushDevice'] = _device!.path;
    await _device!
        .set({'token': token, 'updatedAt': FieldValue.serverTimestamp()});
  }

  static Future<void> disable() async {
    final storedPath = html.window.localStorage['chatPlusPushDevice'];
    final device = _device ??
        (storedPath == null
            ? null
            : FirebaseFirestore.instance.doc(storedPath));
    await device?.delete();
    html.window.localStorage.remove('chatPlusPushDevice');
    _device = null;
    if (_loaded) {
      await _disableNotifications().toDart;
    }
  }
}
