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
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _chatsSubscription;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _chats = [];
  Object? _error;
  bool _loading = true;
  bool _finding = false;
  bool _openingCall = false;
  bool _pushBusy = false;
  String? _pushStatus;
  StreamSubscription<String>? _pushTokenUpdates;

  @override
  void initState() {
    super.initState();
    // Browser notification permission needs a user gesture on many devices.
    // Do not request permission automatically when the page loads.
    if (html.Notification.permission == 'granted') {
      _enablePushNotifications();
    }
    _updateLastSeen();
    html.document.addEventListener('visibilitychange', _handleVisibilityChange);
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

  Future<void> _updateLastSeen() async {
    try {
      await FirebaseFirestore.instance.collection('users').doc(widget.user.uid).update({
        'lastSeen': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Presence should never block chats if the network is temporarily unavailable.
    }
  }

  void _handleVisibilityChange(html.Event _) {
    if (html.document.visibilityState == 'visible') {
      _updateLastSeen();
    }
  }

  Future<void> _enablePushNotifications() async {
    if (_pushBusy) return;
    setState(() {
      _pushBusy = true;
      _pushStatus = null;
    });
    const vapidKey = String.fromEnvironment('FCM_VAPID_KEY');
    if (vapidKey.isEmpty) {
      if (mounted) setState(() {
        _pushBusy = false;
        _pushStatus = 'Push notifications are not configured in this build.';
      });
      return;
    }
    try {
      final messaging = FirebaseMessaging.instance;
      final permission = await messaging.requestPermission(
        alert: true, badge: true, sound: true,
      );
      if (permission.authorizationStatus != AuthorizationStatus.authorized &&
          permission.authorizationStatus != AuthorizationStatus.provisional) {
        throw StateError('Notifications are blocked. Allow Chat Plus notifications in Chrome.');
      }
      // Firebase Messaging looks for this worker at the site root on web.
      // The deploy workflow publishes a root-compatible copy for GitHub Pages.
      final token = await messaging.getToken(vapidKey: vapidKey);
      if (token == null || token.isEmpty) {
        throw StateError('This browser did not provide a push token.');
      }
      await _savePushToken(token);
      await _pushTokenUpdates?.cancel();
      _pushTokenUpdates = messaging.onTokenRefresh.listen((next) {
        _savePushToken(next).catchError((Object error) {
          if (mounted) setState(() => _pushStatus = 'Push token update failed: $error');
        });
      });
      if (mounted) setState(() => _pushStatus = 'Call notifications enabled on this phone.');
    } catch (error) {
      if (mounted) setState(() => _pushStatus = 'Call notifications failed: $error');
    } finally {
      if (mounted) setState(() => _pushBusy = false);
    }
  }

  Future<void> _savePushToken(String token) async {
    await FirebaseFirestore.instance
        .collection('pushTokens')
        .doc(widget.user.uid)
        .collection('devices')
        .doc('web')
        .set({
      'registration': token,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  void dispose() {
    _updateLastSeen();
    html.document.removeEventListener('visibilitychange', _handleVisibilityChange);
    _pushTokenUpdates?.cancel();
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
            tooltip: 'Enable call notifications',
            onPressed: _pushBusy ? null : _enablePushNotifications,
            icon: const Icon(Icons.notifications_active_outlined),
          ),
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
          if (_pushStatus != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: SelectableText(_pushStatus!),
            ),
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
