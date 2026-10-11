part of 'family_home.dart';

class _PersonalHome extends StatefulWidget {
  const _PersonalHome({required this.user});
  final User user;
  @override
  State<_PersonalHome> createState() => _PersonalHomeState();
}

class _PersonalHomeState extends State<_PersonalHome> {
  final Map<String, StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>
      _callWatchers = {};
  final Set<String> _shownCalls = {};
  final Set<String> _blockedCallers = {};
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _blocksSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _chatsSubscription;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _chats = [];
  Object? _error;
  bool _loading = true;
  bool _finding = false;
  bool _openingCall = false;

  @override
  void initState() {
    super.initState();
    _blocksSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.user.uid)
        .collection('callBlocks')
        .snapshots()
        .listen((snapshot) {
      _blockedCallers
        ..clear()
        ..addAll(snapshot.docs.map((doc) => doc.id));
    });
    _chatsSubscription = FirebaseFirestore.instance
        .collection('conversations')
        .where('memberIds', arrayContains: widget.user.uid)
        .snapshots()
        .listen(
      (snapshot) {
        final paths = snapshot.docs.map((doc) => doc.reference.path).toSet();
        for (final path in _callWatchers.keys.toList()) {
          if (!paths.contains(path)) _callWatchers.remove(path)?.cancel();
        }
        for (final chat in snapshot.docs) {
          _callWatchers.putIfAbsent(
            chat.reference.path,
            () => chat.reference
                .collection('calls')
                .where('recipientId', isEqualTo: widget.user.uid)
                .snapshots()
                .listen(
              (calls) {
                for (final change in calls.docChanges) {
                  if (change.type == DocumentChangeType.removed) continue;
                  final call = change.doc;
                  final path = call.reference.path;
                  if (!mounted ||
                      call.data()?['status'] != 'ringing' ||
                      !ChatVoiceCall.isFresh(call.data()) ||
                      _blockedCallers.contains(call.data()?['callerId']) ||
                      _shownCalls.contains(path) ||
                      ChatVoiceCall.active ||
                      _openingCall) continue;
                  _shownCalls.add(path);
                  _openingCall = true;
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChatVoiceCall(
                        conversation: chat.reference,
                        user: widget.user,
                        call: call.reference,
                        incoming: true,
                      ),
                    ),
                  ).whenComplete(() {
                    _openingCall = false;
                  });
                }
              },
              onError: (Object error) {
                if (mounted)
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Incoming calls unavailable: $error',
                      ),
                    ),
                  );
              },
            ),
          );
        }
        if (mounted)
          setState(() {
            _chats = snapshot.docs;
            _error = null;
            _loading = false;
          });
      },
      onError: (Object error) {
        if (mounted)
          setState(() {
            _error = error;
            _loading = false;
          });
      },
    );
  }

  @override
  void dispose() {
    _blocksSubscription?.cancel();
    _chatsSubscription?.cancel();
    for (final watcher in _callWatchers.values) {
      watcher.cancel();
    }
    super.dispose();
  }

  Future<void> _findPerson() async {
    if (_finding) return;
    final input = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Start a chat'),
        content: TextField(
          controller: input,
          autofocus: true,
          autocorrect: false,
          textCapitalization: TextCapitalization.none,
          decoration: const InputDecoration(
            labelText: 'Their username',
            prefixText: '@',
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Enable call alerts',
            icon: const Icon(Icons.notifications_active),
            onPressed: () async {
              try {
                await CallRingtone.enable();
                await CallNotifications.enable(widget.user.uid);
                if (mounted)
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text(
                          'Call sound and background notifications enabled.')));
              } catch (error) {
                if (mounted)
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Call alert setup: $error')));
              }
            },
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, input.text.trim()),
            child: const Text('Find'),
          ),
        ],
      ),
    );
    input.dispose();
    if (name == null || name.isEmpty || !mounted) return;
    setState(() => _finding = true);
    try {
      final id = await UsernameDirectory.findUserId(name);
      if (id == null) throw StateError('No account was found for @$name.');
      if (id == widget.user.uid)
        throw StateError(
          'Choose another person. To sync your own chats, sign in with the same account on both devices.',
        );
      final chat = await ChatDirectory.openDirect(
        currentUserId: widget.user.uid,
        otherUserId: id,
      );
      if (mounted)
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                _ConversationScreen(conversation: chat, user: widget.user),
          ),
        );
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not start chat: $error'),
            duration: const Duration(seconds: 8),
          ),
        );
    } finally {
      if (mounted) setState(() => _finding = false);
    }
  }

  Future<void> _newGroup() async {
    final title = TextEditingController();
    final members = TextEditingController();
    final values = await showDialog<List<String>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('New group'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: title,
              decoration: const InputDecoration(labelText: 'Group name'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: members,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Member usernames',
                hintText: 'Separate usernames with commas',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, [title.text.trim(), members.text]),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    title.dispose();
    members.dispose();
    if (values == null || values.first.isEmpty) return;
    try {
      final ids = <String>{widget.user.uid};
      final names = values[1]
          .split(RegExp(r'[,\n]'))
          .map((name) => name.trim())
          .where((name) => name.isNotEmpty)
          .toSet();
      for (final name in names) {
        final id = await UsernameDirectory.findUserId(name);
        if (id == null) throw StateError('No account was found for @$name.');
        ids.add(id);
      }
      if (ids.length < 2 || ids.length > 50)
        throw StateError('Choose between 1 and 49 other people.');
      final ref =
          await FirebaseFirestore.instance.collection('conversations').add({
        'title': values.first,
        'type': 'group',
        'memberIds': ids.toList(),
        'adminIds': [widget.user.uid],
        'createdBy': widget.user.uid,
        'lastMessage': 'Group created',
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
      final chat = await ref.get();
      if (mounted)
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                _ConversationScreen(conversation: chat, user: widget.user),
          ),
        );
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not create group: $error')),
        );
    }
  }

  Future<void> _showAccount() async {
    final profile = await FirebaseFirestore.instance
        .collection('users')
        .doc(widget.user.uid)
        .get();
    if (!mounted) return;
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Your account'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SelectableText('@${profile.data()?['username'] ?? ''}'),
            SelectableText(widget.user.email ?? ''),
            const SizedBox(height: 12),
            const Text(
              'Share your username so anyone with a Chat Plus account can message you. Sign in with this same account to sync another phone.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _chatTile(QueryDocumentSnapshot<Map<String, dynamic>> chat) {
    final data = chat.data();
    final group = data['type'] == 'group';
    final members = List<String>.from(data['memberIds'] ?? const <String>[]);
    final others = members.where((id) => id != widget.user.uid);
    final otherId = others.isEmpty ? null : others.first;
    final title = group || otherId == null
        ? Text(data['title'] as String? ?? 'Group')
        : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('users')
                .doc(otherId)
                .snapshots(),
            builder: (context, snapshot) =>
                Text('@${snapshot.data?.data()?['username'] ?? 'User'}'),
          );
    return ListTile(
      leading: CircleAvatar(child: Icon(group ? Icons.groups : Icons.person)),
      title: title,
      subtitle: Text(
        data['lastMessage'] as String? ?? '',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              _ConversationScreen(conversation: chat, user: widget.user),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chats = [..._chats]..sort(
        (a, b) => _time(b.data()['updatedAt'])
            .compareTo(_time(a.data()['updatedAt'])),
      );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat Plus'),
        actions: [
          IconButton(
            tooltip: 'Your username',
            onPressed: _showAccount,
            icon: const Icon(Icons.alternate_email),
          ),
          IconButton(
            tooltip: 'New group',
            onPressed: _newGroup,
            icon: const Icon(Icons.group_add),
          ),
          IconButton(
            tooltip: 'Sign out',
            onPressed: () async {
              await CallNotifications.disable();
              await FirebaseAuth.instance.signOut();
              if (mounted)
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (_) => const FamilyHome()),
                  (_) => false,
                );
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _finding ? null : _findPerson,
        icon: const Icon(Icons.person_search),
        label: Text(_finding ? 'Finding…' : 'New chat'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 100),
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Message anyone by username. Only chat members can read the conversation.',
            ),
          ),
          if (_loading) const Center(child: CircularProgressIndicator()),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: SelectableText('Chats could not load: $_error'),
            ),
          if (!_loading && _error == null && chats.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('No chats yet. Tap New chat to find someone.'),
            ),
          ...chats.map(_chatTile),
          // Old family conversations remain accessible without moving or deleting them.
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('families')
                .where('memberIds', arrayContains: widget.user.uid)
                .snapshots(),
            builder: (context, snapshot) {
              if (snapshot.hasError)
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Previous chats could not load. Check your connection and try again.',
                  ),
                );
              final families = snapshot.data?.docs ?? [];
              if (families.isEmpty) return const SizedBox.shrink();
              return ExpansionTile(
                title: const Text('Previous family chats'),
                children: families
                    .map(
                      (family) => ListTile(
                        title: Text(
                          family.data()['name'] as String? ?? 'Previous chats',
                        ),
                        leading: const Icon(Icons.history),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => _ChatListScreen(
                              family: family,
                              user: widget.user,
                            ),
                          ),
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}
