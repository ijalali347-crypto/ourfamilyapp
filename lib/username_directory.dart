import 'package:cloud_firestore/cloud_firestore.dart';

class UsernameDirectory {
  const UsernameDirectory._();

  static String normalize(String value) => value.trim().toLowerCase();
  static bool isValid(String value) => RegExp(r'^[a-z0-9_]{3,20}$').hasMatch(normalize(value));

  static Future<void> claim({required String userId, required String username}) async {
    final cleanName = normalize(username);
    if (!isValid(cleanName)) throw const FormatException('Use 3–20 letters, numbers, or underscores for your username.');
    final firestore = FirebaseFirestore.instance;
    final usernameRef = firestore.collection('usernames').doc(cleanName);
    final profileRef = firestore.collection('users').doc(userId);
    await firestore.runTransaction((transaction) async {
      if ((await transaction.get(usernameRef)).exists) throw StateError('That username is already in use.');
      transaction.set(usernameRef, {'uid': userId, 'usernameLower': cleanName, 'createdAt': FieldValue.serverTimestamp()});
      transaction.set(profileRef, {'uid': userId, 'username': cleanName, 'usernameLower': cleanName, 'createdAt': FieldValue.serverTimestamp()});
    });
  }

  static Future<String?> findUserId(String username) async =>
      (await FirebaseFirestore.instance.collection('usernames').doc(normalize(username)).get()).data()?['uid'] as String?;
}

