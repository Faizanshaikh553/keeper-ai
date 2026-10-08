import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class ChatHistoryScreen extends StatefulWidget {
  const ChatHistoryScreen({super.key});

  @override
  State<ChatHistoryScreen> createState() => _ChatHistoryScreenState();
}

class _ChatHistoryScreenState extends State<ChatHistoryScreen> {
  String _formatDate(Timestamp? timestamp) {
    if (timestamp == null) return 'Unknown';

    final DateTime date = timestamp.toDate().toLocal();
    final DateTime now = DateTime.now();

    final bool sameDay =
        date.year == now.year && date.month == now.month && date.day == now.day;

    if (sameDay) {
      final int hour = date.hour == 0
          ? 12
          : date.hour > 12
          ? date.hour - 12
          : date.hour;
      final String minute = date.minute.toString().padLeft(2, '0');
      final String period = date.hour >= 12 ? 'PM' : 'AM';
      return '$hour:$minute $period';
    }

    return '${date.day}/${date.month}/${date.year}';
  }

  Future<void> _renameChat(
    BuildContext context,
    String chatId,
    String currentTitle,
  ) async {
    final TextEditingController controller = TextEditingController(
      text: currentTitle,
    );

    final String? newTitle = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF151B2A),
          title: const Text(
            'Rename chat',
            style: TextStyle(color: Colors.white),
          ),
          content: TextField(
            controller: controller,
            autofocus: true,
            maxLength: 60,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: 'Chat title',
              hintStyle: TextStyle(color: Color(0xFF7F8292)),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final String value = controller.text.trim();
                if (value.isNotEmpty) {
                  Navigator.pop(dialogContext, value);
                }
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    controller.dispose();

    if (newTitle == null || newTitle == currentTitle) return;

    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('keeper_chats')
        .doc(chatId)
        .update({'title': newTitle, 'updatedAt': FieldValue.serverTimestamp()});
  }

  Future<void> _deleteChat(
    BuildContext context,
    String chatId,
    String title,
  ) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF151B2A),
          title: const Text(
            'Delete chat?',
            style: TextStyle(color: Colors.white),
          ),
          content: Text(
            '"$title" will be removed permanently.',
            style: const TextStyle(color: Color(0xFFB8BBC7)),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text(
                'Delete',
                style: TextStyle(color: Color(0xFFFF7D92)),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('keeper_chats')
        .doc(chatId)
        .delete();
  }

  Future<void> _togglePin(String chatId, bool isPinned) async {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    await FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('keeper_chats')
        .doc(chatId)
        .update({
          'isPinned': !isPinned,
          'updatedAt': FieldValue.serverTimestamp(),
        });
  }

  @override
  Widget build(BuildContext context) {
    final User? user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: const Color(0xFF090D18),
      appBar: AppBar(
        backgroundColor: const Color(0xFF090D18),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Chat History',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: 'New chat',
            onPressed: () => Navigator.pop(context, '__new__'),
            icon: const Icon(Icons.add_comment_rounded),
          ),
        ],
      ),
      body: user == null
          ? const Center(
              child: Text(
                'Please sign in again.',
                style: TextStyle(color: Color(0xFF9CA3AF)),
              ),
            )
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('users')
                  .doc(user.uid)
                  .collection('keeper_chats')
                  .orderBy('updatedAt', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: Color(0xFF766DFF)),
                  );
                }

                if (snapshot.hasError) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Unable to load chat history.',
                        style: TextStyle(color: Color(0xFF9CA3AF)),
                      ),
                    ),
                  );
                }

                final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs =
                    snapshot.data?.docs ?? [];

                if (docs.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.forum_outlined,
                            color: Color(0xFF766DFF),
                            size: 58,
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'No saved chats yet.',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Your Keeper AI conversations will appear here.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Color(0xFF8E91A3),
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 18),
                          ElevatedButton.icon(
                            onPressed: () => Navigator.pop(context, '__new__'),
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('Start New Chat'),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final List<QueryDocumentSnapshot<Map<String, dynamic>>>
                sorted = [...docs]
                  ..sort((a, b) {
                    final bool aPinned = a.data()['isPinned'] as bool? ?? false;
                    final bool bPinned = b.data()['isPinned'] as bool? ?? false;

                    if (aPinned == bPinned) return 0;
                    return aPinned ? -1 : 1;
                  });

                return ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                  itemCount: sorted.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final document = sorted[index];
                    final data = document.data();

                    final String title =
                        data['title']?.toString() ?? 'New Chat';
                    final String preview =
                        data['lastMessage']?.toString() ?? '';
                    final bool isPinned = data['isPinned'] as bool? ?? false;
                    final int messageCount = data['messageCount'] as int? ?? 0;
                    final Timestamp? updatedAt =
                        data['updatedAt'] as Timestamp?;

                    return Material(
                      color: const Color(0xFF121725),
                      borderRadius: BorderRadius.circular(18),
                      child: InkWell(
                        onTap: () => Navigator.pop(context, document.id),
                        borderRadius: BorderRadius.circular(18),
                        child: Container(
                          padding: const EdgeInsets.all(15),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: isPinned
                                  ? const Color(0xFF5147E5)
                                  : const Color(0xFF292F42),
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 45,
                                height: 45,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF24205A),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Icon(
                                  isPinned
                                      ? Icons.push_pin_rounded
                                      : Icons.chat_bubble_outline_rounded,
                                  color: const Color(0xFFAAA4FF),
                                ),
                              ),
                              const SizedBox(width: 13),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    if (preview.isNotEmpty) ...[
                                      const SizedBox(height: 5),
                                      Text(
                                        preview,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Color(0xFF9CA3AF),
                                          fontSize: 11.5,
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 6),
                                    Text(
                                      '$messageCount messages • ${_formatDate(updatedAt)}',
                                      style: const TextStyle(
                                        color: Color(0xFF777D8E),
                                        fontSize: 10.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              PopupMenuButton<String>(
                                color: const Color(0xFF1A2030),
                                iconColor: const Color(0xFF9CA3AF),
                                onSelected: (value) {
                                  if (value == 'pin') {
                                    _togglePin(document.id, isPinned);
                                  } else if (value == 'rename') {
                                    _renameChat(context, document.id, title);
                                  } else if (value == 'delete') {
                                    _deleteChat(context, document.id, title);
                                  }
                                },
                                itemBuilder: (_) => [
                                  PopupMenuItem(
                                    value: 'pin',
                                    child: Text(
                                      isPinned ? 'Unpin' : 'Pin',
                                      style: const TextStyle(
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'rename',
                                    child: Text(
                                      'Rename',
                                      style: TextStyle(color: Colors.white),
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Text(
                                      'Delete',
                                      style: TextStyle(
                                        color: Color(0xFFFF7D92),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
