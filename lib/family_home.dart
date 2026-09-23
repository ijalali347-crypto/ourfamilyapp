import 'package:flutter/material.dart';

class FamilyHome extends StatefulWidget {
  const FamilyHome({super.key});

  @override
  State<FamilyHome> createState() => _FamilyHomeState();
}

class _FamilyHomeState extends State<FamilyHome> {
  final TextEditingController _messageController = TextEditingController();
  final List<String> _messages = [
    'Welcome to our private family space! ❤️',
    'Everything shared here stays with our family.',
  ];
  int _tab = 0;

  @override
  void dispose() {
    _messageController.dispose();
    super.dispose();
  }

  void _sendMessage() {
    final message = _messageController.text.trim();
    if (message.isEmpty) return;
    setState(() {
      _messages.add(message);
      _messageController.clear();
    });
  }

  void _showInvite() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Invite your family', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('Share this private invite code only with relatives you trust.'),
            const SizedBox(height: 20),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(color: const Color(0xFFEAF3FF), borderRadius: BorderRadius.circular(16)),
              child: const Text('FAMILY-2026', textAlign: TextAlign.center, style: TextStyle(letterSpacing: 2, fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF0F4C81))),
            ),
            const SizedBox(height: 16),
            const Text('This is a demo code. Real invite links will be connected securely when the backend is added.', style: TextStyle(color: Colors.black54)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const navy = Color(0xFF163B5C);
    return Scaffold(
      backgroundColor: const Color(0xFFF7FAFC),
      appBar: AppBar(
        backgroundColor: const Color(0xFFF7FAFC),
        foregroundColor: navy,
        elevation: 0,
        title: const Text('Our Family', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(onPressed: _showInvite, icon: const Icon(Icons.person_add_alt_1_outlined), tooltip: 'Invite family'),
        ],
      ),
      body: SafeArea(
        top: false,
        child: IndexedStack(
          index: _tab,
          children: [_chatTab(), _familyTab(), _momentsTab()],
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (value) => setState(() => _tab = value),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.chat_bubble_outline), selectedIcon: Icon(Icons.chat_bubble), label: 'Chat'),
          NavigationDestination(icon: Icon(Icons.group_outlined), selectedIcon: Icon(Icons.group), label: 'Family'),
          NavigationDestination(icon: Icon(Icons.photo_library_outlined), selectedIcon: Icon(Icons.photo_library), label: 'Moments'),
        ],
      ),
    );
  }

  Widget _chatTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [Color(0xFF1F6AA5), Color(0xFF6AB7E8)]),
              borderRadius: BorderRadius.circular(22),
            ),
            child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Good to see you!', style: TextStyle(color: Colors.white70, fontSize: 15)),
              SizedBox(height: 4),
              Text('Family Chat', style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.bold)),
              SizedBox(height: 6),
              Text('A private place for your favourite people.', style: TextStyle(color: Colors.white)),
            ]),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: _messages.length,
            itemBuilder: (context, index) {
              final mine = index == _messages.length - 1 && index > 1;
              return Align(
                alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: mine ? const Color(0xFF1F6AA5) : Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 8, offset: Offset(0, 3))],
                  ),
                  child: Text(_messages[index], style: TextStyle(color: mine ? Colors.white : const Color(0xFF263238))),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Row(children: [
            IconButton(onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Photos and voice notes are coming next.'))), icon: const Icon(Icons.add_circle_outline)),
            Expanded(
              child: TextField(
                controller: _messageController,
                onSubmitted: (_) => _sendMessage(),
                decoration: InputDecoration(hintText: 'Message your family...', filled: true, fillColor: Colors.white, border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none)),
              ),
            ),
            IconButton(onPressed: _sendMessage, icon: const Icon(Icons.send_rounded, color: Color(0xFF1F6AA5))),
          ]),
        ),
      ],
    );
  }

  Widget _familyTab() {
    const members = [
      ['You', 'Family admin', 'Y'],
      ['Mum', 'Online now', 'M'],
      ['Dad', 'Last seen recently', 'D'],
      ['Sister', 'Online now', 'S'],
    ];
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('Your family', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF163B5C))),
        const SizedBox(height: 8),
        const Text('Only invited people can see this space.'),
        const SizedBox(height: 20),
        ...members.map((member) => Card(
          elevation: 0,
          color: Colors.white,
          child: ListTile(
            leading: CircleAvatar(backgroundColor: const Color(0xFFE0F1FC), child: Text(member[2], style: const TextStyle(color: Color(0xFF1F6AA5), fontWeight: FontWeight.bold))),
            title: Text(member[0], style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(member[1]),
            trailing: member[1] == 'Online now' ? const Icon(Icons.circle, size: 12, color: Colors.green) : null,
          ),
        )),
        const SizedBox(height: 16),
        FilledButton.icon(onPressed: _showInvite, icon: const Icon(Icons.person_add_alt_1), label: const Text('Invite a family member')),
      ],
    );
  }

  Widget _momentsTab() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text('Family moments', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF163B5C))),
        const SizedBox(height: 8),
        const Text('Photos and videos shared with your family will appear here.'),
        const SizedBox(height: 32),
        Container(
          height: 220,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(24)),
          child: const Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.photo_camera_back_outlined, size: 54, color: Color(0xFF6AB7E8)),
            SizedBox(height: 12),
            Text('Your first family moment is waiting', style: TextStyle(fontWeight: FontWeight.bold)),
          ]),
        ),
      ],
    );
  }
}
