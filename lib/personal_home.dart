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
  int _navIndex = 1;

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
                        video: call.data()?['video'] == true,
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

  Future<void> _loadPushScript(String src) async {
    if (html.document.querySelector('script[data-chat-plus-src="$src"]') != null) return;
    final script = html.ScriptElement()
      ..src = src
      ..setAttribute('data-chat-plus-src', src);
    final loaded = Completer<void>();
    script.onLoad.first.then((_) => loaded.complete());
    script.onError.first.then((_) => loaded.completeError(StateError('Could not load notification service.')));
    html.document.head?.append(script);
    await loaded.future;
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
      await _loadPushScript('https://www.gstatic.com/firebasejs/10.13.2/firebase-app-compat.js');
      await _loadPushScript('https://www.gstatic.com/firebasejs/10.13.2/firebase-messaging-compat.js');
      await _loadPushScript('/ourfamilyapp/push-bridge.js');
      final promise = js_util.callMethod<Object>(
        html.window,
        'chatPlusGetPushToken',
        <Object>[vapidKey],
      );
      final token = await js_util.promiseToFuture<String>(promise);
      if (token.isEmpty) {
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
            Text(profile.data()?['name'] as String? ?? '', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
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
            builder: (context, snapshot) {
              final profile = snapshot.data?.data();
              final name = (profile?['name'] as String?)?.trim();
              return Text(name != null && name.isNotEmpty ? name : '@${profile?['username'] ?? 'User'}');
            },
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
      (a, b) => _time(b.data()['updatedAt']).compareTo(_time(a.data()['updatedAt'])),
    );
    const green = Color(0xFF079600);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: const Color(0xFFFDFDFD),
        appBar: AppBar(
          backgroundColor: green,
          foregroundColor: Colors.white,
          elevation: 0,
          toolbarHeight: 88,
          title: Text(_navIndex == 0 ? 'Calls' : _navIndex == 2 ? 'Profile' : 'Chat Plus', style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w500)),
          actions: [
            IconButton(
              tooltip: 'Enable call notifications',
              onPressed: _pushBusy ? null : _enablePushNotifications,
              icon: const Icon(Icons.notifications_active_outlined, size: 30),
            ),
            IconButton(
              tooltip: 'New group',
              onPressed: _newGroup,
              icon: const Icon(Icons.group_add_outlined, size: 30),
            ),
            PopupMenuButton<String>(
              onSelected: (value) async {
                if (value == 'account') {
                  await _showAccount();
                } else if (value == 'logout') {
                  await FirebaseAuth.instance.signOut();
                  if (mounted) {
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (_) => const FamilyHome()),
                      (_) => false,
                    );
                  }
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'account', child: Text('My profile')),
                PopupMenuItem(value: 'logout', child: Text('Sign out')),
              ],
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(112),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 4, 28, 16),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Search',
                      prefixIcon: const Icon(Icons.search, size: 30),
                      filled: true,
                      fillColor: Colors.white.withOpacity(.22),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(26),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                Container(
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(34),
                      topRight: Radius.circular(34),
                    ),
                  ),
                  child: const TabBar(
                    labelColor: Colors.black,
                    unselectedLabelColor: Colors.black54,
                    indicatorColor: green,
                    indicatorWeight: 4,
                    tabs: [
                      Tab(text: 'Chats'),
                      Tab(text: 'Groups'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        floatingActionButton: _navIndex == 1 ? FloatingActionButton(
          backgroundColor: green,
          foregroundColor: Colors.white,
          onPressed: _finding ? null : _findPerson,
          child: const Icon(Icons.person_add_alt_1, size: 30),
        ) : null,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _navIndex,
          onDestinationSelected: (index) => setState(() => _navIndex = index),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.call_outlined), selectedIcon: Icon(Icons.call), label: 'Calls'),
            NavigationDestination(icon: Icon(Icons.chat_bubble_outline), selectedIcon: Icon(Icons.chat_bubble), label: 'Chats'),
            NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profile'),
          ],
        ),
        body: _navIndex == 0
            ? _CallsLanding(onStartCall: _findPerson)
            : _navIndex == 2
                ? _ProfileLanding(user: widget.user, onProfile: _showAccount, onNotifications: _enablePushNotifications)
                : TabBarView(
          children: [
            ListView(
              padding: const EdgeInsets.only(bottom: 100),
              children: [
                if (_pushStatus != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
                    child: SelectableText(_pushStatus!),
                  ),
                if (_loading) const Padding(
                  padding: EdgeInsets.all(30),
                  child: Center(child: CircularProgressIndicator()),
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: SelectableText('Chats could not load: $_error'),
                  ),
                if (!_loading && _error == null && chats.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(child: Text('No chats yet. Tap + to find someone.')),
                  ),
                ...chats.map(_chatTile),
                StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('families')
                      .where('memberIds', arrayContains: widget.user.uid)
                      .snapshots(),
                  builder: (context, snapshot) {
                    final families = snapshot.data?.docs ?? [];
                    if (families.isEmpty) return const SizedBox.shrink();
                    return ExpansionTile(
                      title: const Text('Previous family chats'),
                      children: families.map((family) => ListTile(
                        title: Text(family.data()['name'] as String? ?? 'Previous chats'),
                        leading: const Icon(Icons.history),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => _ChatListScreen(family: family, user: widget.user),
                          ),
                        ),
                      )).toList(),
                    );
                  },
                ),
              ],
            ),
            ListView(
              padding: const EdgeInsets.all(24),
              children: const [
                SizedBox(height: 80),
                Icon(Icons.groups_2_outlined, size: 82, color: Colors.black26),
                SizedBox(height: 18),
                Center(child: Text('Your group chats will appear here.', style: TextStyle(fontSize: 18))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CallsLanding extends StatelessWidget {
  const _CallsLanding({required this.onStartCall});
  final VoidCallback onStartCall;
  @override
  Widget build(BuildContext context) => Column(children: [
    Container(color: const Color(0xFF079600), padding: const EdgeInsets.fromLTRB(28, 8, 28, 20),
      child: TextField(decoration: InputDecoration(hintText: 'Search', prefixIcon: const Icon(Icons.search),
        filled: true, fillColor: Colors.white.withOpacity(.22),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(26), borderSide: BorderSide.none)))),
    const Padding(padding: EdgeInsets.all(18), child: Row(children: [
      Expanded(child: Center(child: Text('All Calls', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)))),
      Expanded(child: Center(child: Text('Missed Calls', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)))),
    ])),
    const Spacer(),
    const Icon(Icons.video_call_outlined, size: 92, color: Colors.black12),
    const SizedBox(height: 18),
    const Text('No calls yet', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold)),
    const SizedBox(height: 10),
    const Padding(padding: EdgeInsets.symmetric(horizontal: 50), child: Text('Start a voice or video call from a one-to-one chat.', textAlign: TextAlign.center, style: TextStyle(fontSize: 17))),
    const SizedBox(height: 22),
    FilledButton.icon(onPressed: onStartCall, icon: const Icon(Icons.add_call), label: const Text('Start call')),
    const Spacer(flex: 2),
  ]);
}

class _ProfileLanding extends StatelessWidget {
  const _ProfileLanding({required this.user, required this.onProfile, required this.onNotifications});
  final User user;
  final VoidCallback onProfile;
  final VoidCallback onNotifications;
  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.all(28), children: [
    const SizedBox(height: 45),
    const CircleAvatar(radius: 48, child: Icon(Icons.person, size: 54)),
    const SizedBox(height: 18),
    Center(child: Text(user.email ?? 'Chat Plus account', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600))),
    const SizedBox(height: 30),
    ListTile(leading: const Icon(Icons.alternate_email), title: const Text('My profile'), onTap: onProfile),
    ListTile(leading: const Icon(Icons.notifications_active_outlined), title: const Text('Call notifications'), onTap: onNotifications),
  ]);
}
