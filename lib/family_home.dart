import 'dart:async';
import 'dart:typed_data';
import 'dart:html' as html;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import 'package:record/record.dart';
import 'package:audioplayers/audioplayers.dart';

import 'username_directory.dart';

class FamilyHome extends StatelessWidget {
  const FamilyHome({super.key});

  @override
  Widget build(BuildContext context) => const _FamilyGate();
}

class _FamilyGate extends StatelessWidget {
  const _FamilyGate();

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const Scaffold(body: Center(child: Text('Please sign in again.')));
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) return const Scaffold(body: Center(child: CircularProgressIndicator()));
        if (snapshot.hasError) return _ErrorScreen(message: snapshot.error.toString());
        if (!(snapshot.data?.exists ?? false)) return _ChooseUsername(user: user);
        final profile = snapshot.data!.data() ?? const <String, dynamic>{};
        final profileUid = profile['uid'] as String?;
        if (profileUid != user.uid) {
          return const _ErrorScreen(message: 'This account profile does not match the signed-in account. Please sign out and sign in again.');
        }
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          // All devices signed in to this Firebase account use the same UID,
          // so they subscribe to the same cloud family/chat data.
          stream: FirebaseFirestore.instance.collection('families').where('memberIds', arrayContains: user.uid).snapshots(),
          builder: (context, familySnapshot) {
            if (familySnapshot.connectionState == ConnectionState.waiting) return const Scaffold(body: Center(child: CircularProgressIndicator()));
            if (familySnapshot.hasError) return _ErrorScreen(message: familySnapshot.error.toString());
            final families = familySnapshot.data?.docs ?? [];
            if (families.isEmpty) return _CreateFamily(user: user);
            return _ChatListScreen(family: families.first, user: user);
          },
        );
      },
    );
  }
}

class _ChooseUsername extends StatefulWidget {
  const _ChooseUsername({required this.user});
  final User user;

  @override
  State<_ChooseUsername> createState() => _ChooseUsernameState();
}

class _ChooseUsernameState extends State<_ChooseUsername> {
  final _controller = TextEditingController();
  bool _saving = false;

  @override
  void dispose() { _controller.dispose(); super.dispose(); }

  Future<void> _save() async {
    if (!UsernameDirectory.isValid(_controller.text) || _saving) return;
    setState(() => _saving = true);
    try {
      await UsernameDirectory.claim(userId: widget.user.uid, username: _controller.text);
    } on StateError catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    } on FormatException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message!)));
    } finally { if (mounted) setState(() => _saving = false); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(body: Center(child: ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 460),
    child: Padding(padding: const EdgeInsets.all(28), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Icon(Icons.alternate_email, size: 72, color: Color(0xFF1F6AA5)),
      const SizedBox(height: 20), const Text('Choose your username', style: TextStyle(fontSize: 27, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8), const Text('Family members use this to find and add you. It is not your sign-in password.', textAlign: TextAlign.center),
      const SizedBox(height: 24), TextField(controller: _controller, autofocus: true, autocorrect: false, textCapitalization: TextCapitalization.none, decoration: const InputDecoration(labelText: 'Username', hintText: 'example_family')),
      const SizedBox(height: 16), SizedBox(width: double.infinity, height: 52, child: FilledButton(onPressed: _saving ? null : _save, child: _saving ? const CircularProgressIndicator() : const Text('Save username'))),
    ])),
  )));
}

class _CreateFamily extends StatefulWidget {
  const _CreateFamily({required this.user});
  final User user;

  @override
  State<_CreateFamily> createState() => _CreateFamilyState();
}

class _CreateFamilyState extends State<_CreateFamily> {
  bool _busy = false;

  Future<void> _create() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Create your family space'),
        content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(labelText: 'Family name', hintText: 'The Jalali Family')),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Create'))],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    setState(() => _busy = true);
    try {
      await FirebaseFirestore.instance.collection('families').add({
        'name': name,
        'ownerId': widget.user.uid,
        'memberIds': [widget.user.uid],
        'adminIds': [widget.user.uid],
        'createdAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message ?? 'Could not create family.')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 500),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Icon(Icons.family_restroom, color: Color(0xFF1F6AA5), size: 82),
          const SizedBox(height: 24),
          const Text('Create your private family space', textAlign: TextAlign.center, style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          const Text('You control who can join. Groups and messages are visible only to their members.', textAlign: TextAlign.center),
          const SizedBox(height: 28),
          SizedBox(width: double.infinity, height: 52, child: FilledButton(onPressed: _busy ? null : _create, child: _busy ? const CircularProgressIndicator() : const Text('Create family space'))),
        ]),
      ),
    )),
  );
}

class _ChatListScreen extends StatelessWidget {
  const _ChatListScreen({required this.family, required this.user});
  final QueryDocumentSnapshot<Map<String, dynamic>> family;
  final User user;

  @override
  Widget build(BuildContext context) {
    final familyName = family.data()['name'] as String? ?? 'Our Family';
    final isAdmin = List<String>.from(family.data()['adminIds'] ?? const []).contains(user.uid);
    return Scaffold(
      appBar: AppBar(
        title: Text(familyName, style: const TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(tooltip: 'My username', onPressed: () => _showUsername(context), icon: const Icon(Icons.alternate_email)),
          if (isAdmin) IconButton(tooltip: 'Add family member', onPressed: () => _addFamilyMember(context), icon: const Icon(Icons.person_add_alt_1)),
          IconButton(tooltip: 'Sign out', onPressed: () => FirebaseAuth.instance.signOut(), icon: const Icon(Icons.logout)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _newConversation(context), icon: const Icon(Icons.add), label: const Text('New chat')),
      body: Column(children: [
        Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: const Color(0xFFE1F2FC), borderRadius: BorderRadius.circular(16)),
          child: const Row(children: [Icon(Icons.lock_outline, color: Color(0xFF1F6AA5)), SizedBox(width: 10), Expanded(child: Text('Only people added to a chat can see its name, messages, or members.'))]),
        ),
        Expanded(child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: family.reference.collection('conversations').where('memberIds', arrayContains: user.uid).snapshots(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());
            if (snapshot.hasError) return _ErrorScreen(message: snapshot.error.toString());
            final chats = snapshot.data?.docs ?? [];
            if (chats.isEmpty) return const Center(child: Text('No chats yet. Start a private chat or group.'));
            chats.sort((a, b) => _time(b.data()['updatedAt']).compareTo(_time(a.data()['updatedAt'])));
            return ListView.separated(
              padding: const EdgeInsets.only(bottom: 92), itemCount: chats.length, separatorBuilder: (_, __) => const Divider(height: 1, indent: 78),
              itemBuilder: (context, index) {
                final chat = chats[index]; final data = chat.data(); final group = data['type'] == 'group';
                return ListTile(
                  leading: CircleAvatar(backgroundColor: group ? const Color(0xFF1F6AA5) : const Color(0xFFE1F2FC), child: Icon(group ? Icons.groups : Icons.person, color: group ? Colors.white : const Color(0xFF1F6AA5))),
                  title: Text(data['title'] as String? ?? 'Private chat', style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(data['lastMessage'] as String? ?? 'Start the conversation', maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _ConversationScreen(family: family, conversation: chat, user: user))),
                );
              },
            );
          },
        )),
      ]),
    );
  }

  Future<void> _showUsername(BuildContext context) async {
    final profile = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    if (!context.mounted) return;
    final username = profile.data()?['username'] as String? ?? 'Not set';
    final email = user.email ?? 'No email';
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Your synced account'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText('@$username', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            SelectableText(email),
            const SizedBox(height: 14),
            const Text('Use this same email account on every device. Your family, chats and messages are stored in the cloud and will load automatically.'),
          ],
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
      ),
    );
  }

  Future<void> _addFamilyMember(BuildContext context) async {
    final controller = TextEditingController();
    final username = await showDialog<String>(context: context, builder: (dialogContext) => AlertDialog(
      title: const Text('Add family member'),
      content: TextField(controller: controller, autofocus: true, autocorrect: false, textCapitalization: TextCapitalization.none, decoration: const InputDecoration(labelText: 'Their username', hintText: 'example_family')),
      actions: [TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(dialogContext, controller.text), child: const Text('Add'))],
    ));
    controller.dispose();
    if (username == null || username.trim().isEmpty) return;
    try {
      final userId = await UsernameDirectory.findUserId(username);
      if (userId == null) throw StateError('No account was found with that username.');
      if (userId == user.uid) throw StateError('You cannot add yourself as a family member.');
      await family.reference.update({'memberIds': FieldValue.arrayUnion([userId])});

      // Adding a family member should immediately make them available for messaging.
      // Reuse an existing direct chat between the same two people when possible.
      final directChats = await family.reference
          .collection('conversations')
          .where('memberIds', arrayContains: user.uid)
          .get();
      DocumentSnapshot<Map<String, dynamic>>? directChat;
      for (final chat in directChats.docs) {
        final data = chat.data();
        final memberIds = List<String>.from(data['memberIds'] ?? const []);
        if (data['type'] == 'direct' &&
            memberIds.length == 2 &&
            memberIds.contains(userId)) {
          directChat = chat;
          break;
        }
      }

      if (directChat == null) {
        final memberProfile =
            await FirebaseFirestore.instance.collection('users').doc(userId).get();
        final memberUsername =
            memberProfile.data()?['username'] as String? ?? username.trim();
        final chatRef = await family.reference.collection('conversations').add({
          'title': '@$memberUsername',
          'type': 'direct',
          'memberIds': [user.uid, userId],
          'adminIds': [user.uid],
          'createdBy': user.uid,
          'lastMessage': 'Start the conversation',
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        final created = await chatRef.get();
        directChat = created;
      }

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Family member added. Chat is ready.')),
        );
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => _ConversationScreen(
              family: family,
              conversation: directChat!,
              user: user,
            ),
          ),
        );
      }
    } on StateError catch (error) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    } on FirebaseException catch (error) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message ?? 'Could not add that person.')));
    }
  }

  Future<void> _newConversation(BuildContext context) async {
    final title = TextEditingController(); final members = TextEditingController(); bool group = true;
    final values = await showDialog<List<String>>(context: context, builder: (dialogContext) => StatefulBuilder(builder: (context, setDialogState) => AlertDialog(
      title: const Text('New private conversation'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        SwitchListTile(value: group, title: Text(group ? 'Family group' : 'One-to-one chat'), onChanged: (value) => setDialogState(() => group = value)),
        TextField(controller: title, decoration: InputDecoration(labelText: group ? 'Group name' : 'Chat name')),
        const SizedBox(height: 12), TextField(controller: members, maxLines: 3, autocorrect: false, textCapitalization: TextCapitalization.none, decoration: const InputDecoration(labelText: 'Member usernames', hintText: 'One username per line or use commas')),
        const SizedBox(height: 8), const Text('Add people to the family space first, then use their usernames here.', style: TextStyle(fontSize: 12)),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, [title.text.trim(), members.text.trim(), group ? 'group' : 'direct']), child: const Text('Create'))],
    )));
    title.dispose(); members.dispose();
    if (values == null || values[0].isEmpty) return;
    final names = values[1].split(RegExp(r'[,\n]')).map((name) => name.trim()).where((name) => name.isNotEmpty).toSet();
    try {
      final ids = <String>{user.uid};
      for (final name in names) {
        final userId = await UsernameDirectory.findUserId(name);
        if (userId == null) throw StateError('No account was found for @$name.');
        ids.add(userId);
      }
      await family.reference.collection('conversations').add({'title': values[0], 'type': values[2], 'memberIds': ids.toList(), 'adminIds': [user.uid], 'createdBy': user.uid, 'lastMessage': 'Conversation created', 'createdAt': FieldValue.serverTimestamp(), 'updatedAt': FieldValue.serverTimestamp()});
    } on StateError catch (error) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message)));
    } on FirebaseException catch (error) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message ?? 'Could not create conversation.')));
    }
  }
}

class _ConversationScreen extends StatefulWidget {
  const _ConversationScreen({required this.family, required this.conversation, required this.user});
  final QueryDocumentSnapshot<Map<String, dynamic>> family;
  final DocumentSnapshot<Map<String, dynamic>> conversation;
  final User user;

  @override
  State<_ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<_ConversationScreen> {
  final _composer = TextEditingController();
  final AudioRecorder _recorder = AudioRecorder();
  final List<int> _voiceBytes = <int>[];
  StreamSubscription<Uint8List>? _voiceSubscription;
  bool _sending = false;
  bool _recording = false;
  final Set<String> _readReceiptUpdates = <String>{};

  @override
  void dispose() {
    _voiceSubscription?.cancel();
    _composer.dispose();
    _recorder.dispose();
    super.dispose();
  }

  Future<html.File?> _pickWebFile(String accept) async {
    final input = html.FileUploadInputElement()
      ..accept = accept
      ..multiple = false;
    final completer = Completer<html.File?>();
    late StreamSubscription<html.Event> sub;
    sub = input.onChange.listen((_) {
      final file = input.files?.isNotEmpty == true ? input.files!.first : null;
      if (!completer.isCompleted) completer.complete(file);
      sub.cancel();
    });
    input.click();
    return completer.future.timeout(
      const Duration(minutes: 2),
      onTimeout: () {
        sub.cancel();
        return null;
      },
    );
  }

  Future<Uint8List> _readWebFile(html.File file) async {
    final reader = html.FileReader();
    final done = Completer<Uint8List>();
    reader.onLoad.listen((_) {
      final result = reader.result;
      if (result is ByteBuffer) {
        done.complete(result.asUint8List());
      } else if (result is Uint8List) {
        done.complete(result);
      } else {
        done.completeError(StateError('Browser could not read this file.'));
      }
    });
    reader.onError.listen((_) => done.completeError(StateError('Browser could not read this file.')));
    reader.readAsArrayBuffer(file);
    return done.future.timeout(const Duration(seconds: 30));
  }

  Future<void> _sendPhoto() async {
    try {
      final file = await _pickWebFile('image/*');
      if (file == null) return;
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Photo selected. Uploading…'), duration: Duration(seconds: 2)));
      final bytes = await _readWebFile(file);
      if (mounted) setState(() => _sending = true);
      final safeName = file.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final path = 'chat_media/' + widget.family.id + '/' + widget.conversation.id + '/' + DateTime.now().millisecondsSinceEpoch.toString() + '_' + safeName;
      final storage = Supabase.instance.client.storage.from('family-media');
      await storage.uploadBinary(
        path,
        bytes,
        fileOptions: FileOptions(
          contentType: file.type.isNotEmpty ? file.type : _imageContentType(file.name),
          upsert: false,
        ),
      ).timeout(const Duration(seconds: 45));
      final url = await storage.createSignedUrl(path, 315360000).timeout(const Duration(seconds: 20));
      await _saveMediaMessage('image', url, file.name, path, '📷 Photo');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Photo sent.')));
    } on StorageException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Photo failed: ' + error.message), duration: const Duration(seconds: 8)));
    } on TimeoutException {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Photo upload timed out.'), duration: Duration(seconds: 8)));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Photo failed: $error'), duration: const Duration(seconds: 8)));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _sendVideo() async {
    try {
      final file = await _pickWebFile('video/*');
      if (file == null) return;
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Video selected. Uploading…'), duration: Duration(seconds: 2)));
      final bytes = await _readWebFile(file);
      if (mounted) setState(() => _sending = true);
      final safeName = file.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final path = 'chat_media/' + widget.family.id + '/' + widget.conversation.id + '/' + DateTime.now().millisecondsSinceEpoch.toString() + '_' + safeName;
      final storage = Supabase.instance.client.storage.from('family-media');
      await storage.uploadBinary(
        path,
        bytes,
        fileOptions: FileOptions(
          contentType: file.type.isNotEmpty ? file.type : _videoContentType(file.name),
          upsert: false,
        ),
      ).timeout(const Duration(seconds: 90));
      final url = await storage.createSignedUrl(path, 315360000).timeout(const Duration(seconds: 20));
      await _saveMediaMessage('video', url, file.name, path, '🎥 Video');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Video sent.')));
    } on StorageException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Video failed: ' + error.message), duration: const Duration(seconds: 8)));
    } on TimeoutException {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Video upload timed out.'), duration: Duration(seconds: 8)));
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Video failed: $error'), duration: const Duration(seconds: 8)));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _saveMediaMessage(String type, String url, String fileName, String storagePath, String preview) async {
    // Firestore conversation rules validate message membership by sender/member IDs.
    // Include the current conversation members on media messages as well as the sender.
    final conversationData = widget.conversation.data() ?? const <String, dynamic>{};
    final memberIds = List<String>.from(conversationData['memberIds'] ?? const <String>[]);

    await widget.conversation.reference.collection('messages').add({
      'senderId': widget.user.uid,
      'memberIds': memberIds,
      'type': type,
      'mediaUrl': url,
      'fileName': fileName,
      'storagePath': storagePath,
      'createdAt': FieldValue.serverTimestamp(),
    });

    try {
      await widget.conversation.reference.update({
        'lastMessage': preview,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException {
      // The media message has already been sent. A preview update must not make
      // the UI report the whole send as failed.
    }
  }

  String _imageContentType(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.heic')) return 'image/heic';
    return 'image/jpeg';
  }

  String _videoContentType(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.webm')) return 'video/webm';
    if (lower.endsWith('.mov')) return 'video/quicktime';
    if (lower.endsWith('.mkv')) return 'video/x-matroska';
    return 'video/mp4';
  }

  Future<void> _toggleRecording() async {
    if (_recording) {
      try {
        final recordedUrl = await _recorder.stop();
        if (mounted) setState(() => _recording = false);
        if (recordedUrl == null || recordedUrl.isEmpty) {
          throw StateError('The browser did not return the recorded audio.');
        }

        if (mounted) setState(() => _sending = true);

        // On Flutter Web the record package returns a browser blob URL.
        // Read that blob back into bytes before uploading it to Supabase.
        final request = await html.HttpRequest.request(
          recordedUrl,
          responseType: 'arraybuffer',
        );
        final response = request.response;
        if (response is! ByteBuffer) {
          throw StateError('The browser could not read the recorded audio.');
        }
        final bytes = response.asUint8List();
        if (bytes.isEmpty) {
          throw StateError('The recorded voice message is empty.');
        }

        final storagePath =
            'chat_media/' + widget.family.id + '/' + widget.conversation.id + '/' +
            DateTime.now().millisecondsSinceEpoch.toString() + '_voice.webm';
        final storage = Supabase.instance.client.storage.from('family-media');

        await storage.uploadBinary(
          storagePath,
          bytes,
          fileOptions: const FileOptions(contentType: 'audio/webm', upsert: false),
        ).timeout(const Duration(seconds: 60));

        final url = await storage
            .createSignedUrl(storagePath, 315360000)
            .timeout(const Duration(seconds: 20));

        await _saveMediaMessage(
          'audio',
          url,
          'Voice message.webm',
          storagePath,
          '🎤 Voice message',
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Voice message sent.')),
          );
        }
      } on StorageException catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Voice upload failed: ' + error.message)),
          );
        }
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Voice message failed: ' + error.toString())),
          );
        }
      } finally {
        if (mounted) setState(() => _sending = false);
      }
      return;
    }

    try {
      if (!await _recorder.hasPermission()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Microphone permission is required.')),
          );
        }
        return;
      }

      // startStream is not supported by record_web on this browser.
      // Normal start/stop uses the browser MediaRecorder implementation.
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.opus,
          bitRate: 64000,
          sampleRate: 48000,
          numChannels: 1,
        ),
        path: 'voice_message.webm',
      );

      if (mounted) setState(() => _recording = true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not start microphone: ' + error.toString())),
        );
      }
    }
  }

  void _showAttachments() {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
            _AttachmentButton(icon: Icons.photo, label: 'Photo', onTap: () { _sendPhoto(); Navigator.pop(context); }),
            _AttachmentButton(icon: Icons.videocam, label: 'Video', onTap: () { _sendVideo(); Navigator.pop(context); }),
          ]),
        ),
      ),
    );
  }

  Future<void> _markMessagesRead(List<QueryDocumentSnapshot<Map<String, dynamic>>> messages) async {
    for (final doc in messages) {
      final data = doc.data();
      if (data['senderId'] == widget.user.uid) continue;
      final readBy = List<String>.from(data['readBy'] ?? const <String>[]);
      if (readBy.contains(widget.user.uid) || _readReceiptUpdates.contains(doc.id)) continue;
      _readReceiptUpdates.add(doc.id);
      try {
        await doc.reference.update({
          'readBy': FieldValue.arrayUnion([widget.user.uid]),
        });
      } on FirebaseException {
        // Keep the chat usable even if an older Firestore rule has not yet
        // been updated to allow read-receipt writes.
      } finally {
        _readReceiptUpdates.remove(doc.id);
      }
    }
  }

  Future<void> _send() async {
    final text = _composer.text.trim();
    if (text.isEmpty) return;
    _composer.clear();
    try {
      await widget.conversation.reference.collection('messages').add({
        'senderId': widget.user.uid,
        'text': text,
        'type': 'text',
        'readBy': [widget.user.uid],
        'createdAt': FieldValue.serverTimestamp(),
      });
      await widget.conversation.reference.update({'lastMessage': text, 'updatedAt': FieldValue.serverTimestamp()});
    } on FirebaseException catch (error) {
      _composer.text = text;
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message ?? 'Message could not be sent.')));
    }
  }

  Future<void> _showMessageActions(QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final message = doc.data();
    final isText = (message['type'] as String? ?? 'text') == 'text';
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(children: [
          if (isText)
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit message'),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
          ListTile(
            leading: const Icon(Icons.delete_outline, color: Colors.red),
            title: const Text('Delete message', style: TextStyle(color: Colors.red)),
            onTap: () => Navigator.pop(context, 'delete'),
          ),
        ]),
      ),
    );
    if (action == 'edit') await _editMessage(doc);
    if (action == 'delete') await _deleteMessage(doc);
  }

  Future<void> _editMessage(QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final current = doc.data()['text'] as String? ?? '';
    final controller = TextEditingController(text: current);
    final updated = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit message'),
        content: TextField(controller: controller, autofocus: true, maxLines: null),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    controller.dispose();
    if (updated == null || updated.isEmpty || updated == current) return;
    try {
      await doc.reference.update({
        'text': updated,
        'editedAt': FieldValue.serverTimestamp(),
      });
      final latest = await widget.conversation.reference
          .collection('messages')
          .orderBy('createdAt', descending: true)
          .limit(1)
          .get();
      if (latest.docs.isNotEmpty && latest.docs.first.id == doc.id) {
        await widget.conversation.reference.update({
          'lastMessage': updated,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    } on FirebaseException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message ?? 'Message could not be edited.')));
    }
  }

  Future<void> _deleteMessage(QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete message?'),
        content: const Text('This message will be removed from the conversation for everyone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await doc.reference.delete();
      final latest = await widget.conversation.reference
          .collection('messages')
          .orderBy('createdAt', descending: true)
          .limit(1)
          .get();
      final preview = latest.docs.isEmpty
          ? 'Start the conversation'
          : _messagePreview(latest.docs.first.data());
      await widget.conversation.reference.update({
        'lastMessage': preview,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.message ?? 'Message could not be deleted.')));
    }
  }

  String _messagePreview(Map<String, dynamic> message) {
    final type = message['type'] as String? ?? 'text';
    if (type == 'image') return '📷 Photo';
    if (type == 'video') return '🎥 Video';
    if (type == 'audio') return '🎤 Voice message';
    return message['text'] as String? ?? 'Message';
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.conversation.data() ?? const <String, dynamic>{}; final group = data['type'] == 'group';
    return Scaffold(
      appBar: AppBar(title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(data['title'] as String? ?? 'Chat'), Text(group ? 'Private group' : 'Private chat', style: const TextStyle(fontSize: 12))])),
      body: Column(children: [
        Expanded(child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: widget.conversation.reference.collection('messages').snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) return _ErrorScreen(message: snapshot.error.toString());
            final messages = snapshot.data?.docs ?? []; messages.sort((a, b) => _time(a.data()['createdAt']).compareTo(_time(b.data()['createdAt'])));
            if (messages.isEmpty) return const Center(child: Text('Start your private conversation.'));
            return ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: messages.length,
              itemBuilder: (context, index) {
                final doc = messages[index];
                final message = doc.data();
                final mine = message['senderId'] == widget.user.uid;
                return Align(
                  alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                  child: GestureDetector(
                    onLongPress: mine ? () => _showMessageActions(doc) : null,
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(12),
                      constraints: const BoxConstraints(maxWidth: 340),
                      decoration: BoxDecoration(
                        color: mine ? const Color(0xFFDDF1FF) : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Align(alignment: Alignment.centerLeft, child: _MessageBody(message: message)),
                          const SizedBox(height: 5),
                          _MessageMeta(message: message, mine: mine, currentUserId: widget.user.uid),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        )),
        SafeArea(top: false, child: Padding(padding: const EdgeInsets.all(12), child: Row(children: [
          IconButton(onPressed: _showAttachments, icon: const Icon(Icons.attach_file, color: Color(0xFF1F6AA5))),
          Expanded(child: TextField(controller: _composer, onSubmitted: (_) => _send(), decoration: const InputDecoration(hintText: 'Message', filled: true))),
          IconButton(onPressed: _sending ? null : _toggleRecording, icon: Icon(_recording ? Icons.stop_circle : Icons.mic, color: _recording ? Colors.red : const Color(0xFF1F6AA5))),
          IconButton(onPressed: _send, icon: const Icon(Icons.send, color: Color(0xFF1F6AA5))),
        ]))),
      ]),
    );
  }
}

class _AttachmentButton extends StatelessWidget {
  const _AttachmentButton({required this.icon, required this.label, required this.onTap});
  final IconData icon; final String label; final VoidCallback onTap;
  @override Widget build(BuildContext context) => InkWell(onTap: onTap, child: Padding(padding: const EdgeInsets.all(14), child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 38, color: const Color(0xFF1F6AA5)), const SizedBox(height: 8), Text(label)])));
}

class _MessageBody extends StatelessWidget {
  const _MessageBody({required this.message});
  final Map<String, dynamic> message;
  @override Widget build(BuildContext context) {
    final type = message['type'] as String? ?? 'text'; final url = message['mediaUrl'] as String?;
    if (type == 'image' && url != null) return ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.network(url, width: 240, fit: BoxFit.cover));
    if (type == 'video' && url != null) return Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.video_file, size: 58, color: Color(0xFF1F6AA5)), Text(message['fileName'] as String? ?? 'Video'), const Text('Video uploaded', style: TextStyle(fontSize: 12))]);
    if (type == 'audio' && url != null) return _VoiceMessage(url: url);
    return Text(message['text'] as String? ?? '');
  }
}

class _MessageMeta extends StatelessWidget {
  const _MessageMeta({required this.message, required this.mine, required this.currentUserId});
  final Map<String, dynamic> message;
  final bool mine;
  final String currentUserId;

  @override
  Widget build(BuildContext context) {
    final created = _time(message['createdAt']);
    final edited = message['editedAt'] != null;
    if (created.millisecondsSinceEpoch == 0) {
      return const Text('Sending…', style: TextStyle(fontSize: 10, color: Colors.black54));
    }
    final now = DateTime.now();
    final sameDay = created.year == now.year && created.month == now.month && created.day == now.day;
    final yesterday = DateTime(now.year, now.month, now.day).difference(DateTime(created.year, created.month, created.day)).inDays == 1;
    final hour = created.hour % 12 == 0 ? 12 : created.hour % 12;
    final minute = created.minute.toString().padLeft(2, '0');
    final amPm = created.hour >= 12 ? 'PM' : 'AM';
    final date = sameDay
        ? ''
        : yesterday
            ? 'Yesterday · '
            : '${created.day.toString().padLeft(2, '0')}/${created.month.toString().padLeft(2, '0')}/${created.year} · ';
    final readBy = List<String>.from(message['readBy'] ?? const <String>[]);
    final receipt = mine ? (readBy.any((id) => id != currentUserId) ? '  ✓✓' : '  ✓') : '';
    return Text(
      '${edited ? 'edited · ' : ''}$date$hour:$minute $amPm$receipt',
      style: const TextStyle(fontSize: 10, color: Colors.black54),
    );
  }
}

class _VoiceMessage extends StatefulWidget {
  const _VoiceMessage({required this.url}); final String url;
  @override State<_VoiceMessage> createState() => _VoiceMessageState();
}
class _VoiceMessageState extends State<_VoiceMessage> {
  final AudioPlayer _player = AudioPlayer(); bool _playing = false;
  @override void initState() { super.initState(); _player.onPlayerComplete.listen((_) { if (mounted) setState(() => _playing = false); }); }
  @override void dispose() { _player.dispose(); super.dispose(); }
  Future<void> _toggle() async { if (_playing) { await _player.pause(); if (mounted) setState(() => _playing = false); } else { await _player.play(UrlSource(widget.url)); if (mounted) setState(() => _playing = true); } }
  @override Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [IconButton(onPressed: _toggle, icon: Icon(_playing ? Icons.pause_circle : Icons.play_circle, size: 36)), const Text('Voice message')]);
}

class _ErrorScreen extends StatelessWidget {
  const _ErrorScreen({required this.message}); final String message;
  @override Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Text('Secure connection needs setup:\n$message', textAlign: TextAlign.center)));
}

DateTime _time(dynamic value) => value is Timestamp ? value.toDate() : DateTime.fromMillisecondsSinceEpoch(0);
