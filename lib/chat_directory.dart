import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

/// Stable for both participants, including simultaneous first messages.
String directChatId(String first, String second) {
  if (first == second)
    throw ArgumentError('Choose another account to chat with.');
  final ids = [first, second]..sort();
  return 'direct.${ids.map((id) => base64Url.encode(utf8.encode(id))).join('.')}';
}

class ChatDirectory {
  static Future<DocumentSnapshot<Map<String, dynamic>>> openDirect({
    required String currentUserId,
    required String otherUserId,
  }) async {
    final db = FirebaseFirestore.instance;
    final ref = db
        .collection('conversations')
        .doc(directChatId(currentUserId, otherUserId));
    final ids = [currentUserId, otherUserId]..sort();
    await db.runTransaction((transaction) async {
      final existing = await transaction.get(ref);
      if (!existing.exists) {
        transaction.set(ref, {
          'type': 'direct',
          'memberIds': ids,
          'adminIds': [currentUserId],
          'createdBy': currentUserId,
          'title': 'Private chat',
          'lastMessage': 'Start the conversation',
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    });
    return ref.get();
  }
}
