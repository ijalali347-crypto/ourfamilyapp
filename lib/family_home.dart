import 'package:flutter/material.dart';

class FamilyHome extends StatelessWidget {
  const FamilyHome({super.key});

  @override
  Widget build(BuildContext context) {
    return const _ChatListScreen();
  }
}

class _ChatListScreen extends StatelessWidget {
  const _ChatListScreen();

  static const chats = [
    _Chat('Family Group', 'Mum: Dinner at 7 tonight ❤️', '4', true, 'F'),
    _Chat('Mum', 'Can you call me when free?', '2', false, 'M'),
    _Chat('Dad', 'I shared a photo', '', false, 'D'),
    _Chat('Weekend Plans', 'Sister: I can bring dessert!', '1', true, 'W'),
    _Chat('Sister', 'See you soon!', '', false, 'S'),
  ];

  @override
  Widget build(BuildContext context) {
    const blue = Color(0xFF1F6AA5);
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF7FAFC),
        elevation: 0,
        title: const Text('Our Family', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF163B5C))),
        actions: [
          IconButton(onPressed: () {}, icon: const Icon(Icons.search, color: blue)),
          IconButton(onPressed: () {}, icon: const Icon(Icons.more_vert, color: blue)),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: blue,
        onPressed: () => _newChat(context),
        child: const Icon(Icons.chat, color: Colors.white),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: const Color(0xFFE5F3FD), borderRadius: BorderRadius.circular(18)),
            child: const Row(children: [
              Icon(Icons.lock_outline, color: blue),
              SizedBox(width: 12),
              Expanded(child: Text('Private family conversations. Only invited members can join.', style: TextStyle(color: Color(0xFF163B5C)))),
            ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(children: [
            const Text('Chats', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Color(0xFF163B5C))),
            const Spacer(),
            TextButton.icon(onPressed: () => _newGroup(context), icon: const Icon(Icons.group_add, size: 18), label: const Text('New group')),
          ]),
        ),
        const SizedBox(height: 6),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: chats.length,
            separatorBuilder: (_, __) => const Divider(indent: 76, height: 1),
            itemBuilder: (context, index) {
              final chat = chats[index];
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                leading: CircleAvatar(
                  radius: 26,
                  backgroundColor: chat.isGroup ? const Color(0xFF1F6AA5) : const Color(0xFFE0F1FC),
                  child: Icon(chat.isGroup ? Icons.groups_rounded : Icons.person, color: chat.isGroup ? Colors.white : blue),
                ),
                title: Text(chat.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(chat.preview, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Text('10:30', style: TextStyle(fontSize: 11, color: Colors.black54)),
                  if (chat.unread.isNotEmpty) const SizedBox(height: 4),
                  if (chat.unread.isNotEmpty) CircleAvatar(radius: 10, backgroundColor: blue, child: Text(chat.unread, style: const TextStyle(color: Colors.white, fontSize: 11))),
                ]),
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => _ConversationScreen(chat: chat))),
              );
            },
          ),
        ),
      ]),
    );
  }

  void _newChat(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Choose a family member to start a private chat.')));
  }

  void _newGroup(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Group creation will be connected to your secure family accounts.')));
  }
}

class _ConversationScreen extends StatefulWidget {
  const _ConversationScreen({required this.chat});
  final _Chat chat;

  @override
  State<_ConversationScreen> createState() => _ConversationScreenState();
}

class _ConversationScreenState extends State<_ConversationScreen> {
  final TextEditingController _controller = TextEditingController();
  late final List<_Message> _messages;

  @override
  void initState() {
    super.initState();
    _messages = [
      _Message(widget.chat.isGroup ? 'Mum' : widget.chat.name, 'Welcome to our private chat!'),
      const _Message('You', 'Hello! This is our family space.', mine: true),
    ];
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _messages.add(_Message('You', text, mine: true));
      _controller.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    const blue = Color(0xFF1F6AA5);
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF163B5C),
        titleSpacing: 0,
        title: Row(children: [
          CircleAvatar(backgroundColor: widget.chat.isGroup ? blue : const Color(0xFFE0F1FC), child: Icon(widget.chat.isGroup ? Icons.groups : Icons.person, color: widget.chat.isGroup ? Colors.white : blue)),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(widget.chat.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
            Text(widget.chat.isGroup ? '4 family members' : 'Private family chat', style: const TextStyle(fontSize: 12, color: Colors.black54)),
          ]),
        ]),
        actions: [IconButton(onPressed: () {}, icon: const Icon(Icons.videocam_outlined)), IconButton(onPressed: () {}, icon: const Icon(Icons.more_vert))],
      ),
      body: Column(children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _messages.length,
            itemBuilder: (context, index) {
              final message = _messages[index];
              return Align(
                alignment: message.mine ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(12),
                  constraints: const BoxConstraints(maxWidth: 290),
                  decoration: BoxDecoration(color: message.mine ? const Color(0xFFDFF1FF) : Colors.white, borderRadius: BorderRadius.circular(16)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (!message.mine && widget.chat.isGroup) Text(message.sender, style: const TextStyle(color: blue, fontWeight: FontWeight.bold, fontSize: 12)),
                    Text(message.text),
                    const SizedBox(height: 3),
                    const Align(alignment: Alignment.bottomRight, child: Text('10:30', style: TextStyle(fontSize: 10, color: Colors.black45))),
                  ]),
                ),
              );
            },
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(children: [
              IconButton(onPressed: () {}, icon: const Icon(Icons.add_circle_outline, color: blue)),
              Expanded(child: TextField(controller: _controller, onSubmitted: (_) => _send(), decoration: InputDecoration(hintText: 'Message', filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none)))),
              IconButton(onPressed: _send, icon: const Icon(Icons.send_rounded, color: blue)),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _Chat {
  const _Chat(this.name, this.preview, this.unread, this.isGroup, this.initial);
  final String name;
  final String preview;
  final String unread;
  final bool isGroup;
  final String initial;
}

class _Message {
  const _Message(this.sender, this.text, {this.mine = false});
  final String sender;
  final String text;
  final bool mine;
}
