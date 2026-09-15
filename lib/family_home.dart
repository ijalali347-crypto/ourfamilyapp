import 'package:flutter/material.dart';

class FamilyHome extends StatelessWidget {
  const FamilyHome({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Our Family'),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.notifications_outlined),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'Family Chat',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 8),

          const Text(
            'Stay connected with your family',
            style: TextStyle(
              fontSize: 16,
            ),
          ),

          const SizedBox(height: 30),

          _FeatureCard(
            icon: Icons.chat_bubble_outline,
            title: 'Messages',
            subtitle: 'Send and receive text messages',
            onTap: () {},
          ),

          _FeatureCard(
            icon: Icons.mic_none,
            title: 'Voice Messages',
            subtitle: 'Send voice messages to your family',
            onTap: () {},
          ),

          _FeatureCard(
            icon: Icons.photo_library_outlined,
            title: 'Photos',
            subtitle: 'Share family photos',
            onTap: () {},
          ),

          _FeatureCard(
            icon: Icons.video_library_outlined,
            title: 'Videos',
            subtitle: 'Share family videos',
            onTap: () {},
          ),

          const SizedBox(height: 20),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  const Icon(
                    Icons.cloud_done_outlined,
                    size: 35,
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'Offline Sync',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 5),
                        Text(
                          'Messages will sync when you are back online.',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 15),
      child: ListTile(
        contentPadding: const EdgeInsets.all(15),
        leading: CircleAvatar(
          radius: 28,
          child: Icon(icon),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Text(subtitle),
        ),
        trailing: const Icon(Icons.arrow_forward_ios),
        onTap: onTap,
      ),
    );
  }
}
