import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/organization_chat_message_model.dart';
import '../services/organization_chat_service.dart';
import 'organization_members_screen.dart';

class OrganizationGroupChatScreen extends StatefulWidget {
  final String organizationId;
  final String organizationName;

  const OrganizationGroupChatScreen({
    super.key,
    required this.organizationId,
    required this.organizationName,
  });

  @override
  State<OrganizationGroupChatScreen> createState() =>
      _OrganizationGroupChatScreenState();
}

class _OrganizationGroupChatScreenState
    extends State<OrganizationGroupChatScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isSending = false;
  String _ownerId = '';

  @override
  void initState() {
    super.initState();
    _loadOwner();
  }

  Future<void> _loadOwner() async {
    try {
      final snapshot = await FirebaseFirestore.instance
          .collection('organizations')
          .doc(widget.organizationId)
          .get();
      if (!mounted) return;
      setState(() {
        _ownerId = snapshot.data()?['ownerId']?.toString() ?? '';
      });
    } catch (_) {
      // Messages still render using the role stored with new messages.
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final String text = _controller.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() => _isSending = true);
    try {
      await OrganizationChatService.sendMessage(
        organizationId: widget.organizationId,
        text: text,
      );
      _controller.clear();
    } catch (error) {
      _showMessage(
        error
            .toString()
            .replaceFirst('Bad state: ', '')
            .replaceFirst('Invalid argument(s): ', ''),
      );
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _delete(OrganizationChatMessage message) async {
    final bool confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            backgroundColor: const Color(0xFF141A29),
            title: const Text(
              'Delete message?',
              style: TextStyle(color: Colors.white),
            ),
            content: Text(
              message.text,
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFFB7BDCB)),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFE05E68),
                ),
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;

    try {
      await OrganizationChatService.deleteOwnMessage(message);
    } catch (error) {
      _showMessage(error.toString().replaceFirst('Bad state: ', ''));
    }
  }

  Future<void> _report(OrganizationChatMessage message) async {
    final String? reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        backgroundColor: const Color(0xFF141A29),
        title: const Text(
          'Report message',
          style: TextStyle(color: Colors.white),
        ),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, 'abuse_or_harassment'),
            child: const Text(
              'Abuse or harassment',
              style: TextStyle(color: Colors.white),
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, 'spam'),
            child: const Text('Spam', style: TextStyle(color: Colors.white)),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(dialogContext, 'other'),
            child: const Text('Other', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (reason == null) return;

    try {
      await OrganizationChatService.reportMessage(
        message: message,
        reason: reason,
      );
      _showMessage('Message reported. Thank you.');
    } catch (error) {
      _showMessage(error.toString().replaceFirst('Bad state: ', ''));
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _time(DateTime value) {
    final DateTime local = value.toLocal();
    final int hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final String minute = local.minute.toString().padLeft(2, '0');
    final String suffix = local.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $suffix';
  }

  Color _memberColor(String userId) {
    const List<Color> colors = [
      Color(0xFF3C4E8C),
      Color(0xFF216A67),
      Color(0xFF7A3E64),
      Color(0xFF315D86),
      Color(0xFF7A512B),
      Color(0xFF3F6B45),
      Color(0xFF654485),
    ];
    int hash = 0;
    for (final int unit in userId.codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    return colors[hash % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    final String currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: const Color(0xFF090D18),
      appBar: AppBar(
        backgroundColor: const Color(0xFF090D18),
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.organizationName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const Text(
              'Organization group chat',
              style: TextStyle(
                color: Color(0xFF8F96A8),
                fontSize: 11,
                fontWeight: FontWeight.w400,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'View members',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const OrganizationMembersScreen(),
                ),
              );
            },
            icon: const Icon(Icons.groups_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: StreamBuilder<List<OrganizationChatMessage>>(
                stream: OrganizationChatService.watchMessages(
                  widget.organizationId,
                ),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF766DFF),
                      ),
                    );
                  }

                  if (snapshot.hasError) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Unable to load group messages. Check Firestore rules.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Color(0xFFB0B6C5)),
                        ),
                      ),
                    );
                  }

                  final List<OrganizationChatMessage> messages =
                      snapshot.data ?? const <OrganizationChatMessage>[];
                  if (messages.isEmpty) {
                    return const Center(
                      child: Padding(
                        padding: EdgeInsets.all(28),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.forum_outlined,
                              size: 58,
                              color: Color(0xFF6E7390),
                            ),
                            SizedBox(height: 14),
                            Text(
                              'No messages yet',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            SizedBox(height: 7),
                            Text(
                              'Start a simple conversation with your organization members.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Color(0xFF8E95A8),
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }

                  return ListView.builder(
                    controller: _scrollController,
                    reverse: true,
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final OrganizationChatMessage message = messages[index];
                      final bool own = message.userId == currentUserId;
                      final bool owner =
                          message.isOwner ||
                          (_ownerId.isNotEmpty && message.userId == _ownerId);
                      final Color bubbleColor = owner
                          ? const Color(0xFF8A6818)
                          : own
                          ? const Color(0xFF6258E8)
                          : _memberColor(message.userId);
                      final String senderName = own
                          ? 'You'
                          : message.displayName.trim().isEmpty
                          ? 'Member'
                          : message.displayName.trim();

                      return Align(
                        alignment: own
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisAlignment: own
                                ? MainAxisAlignment.end
                                : MainAxisAlignment.start,
                            children: [
                              if (!own) ...[
                                Container(
                                  width: 34,
                                  height: 34,
                                  decoration: BoxDecoration(
                                    color: bubbleColor,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: owner
                                          ? const Color(0xFFFFD978)
                                          : bubbleColor.withValues(alpha: 0.9),
                                      width: owner ? 2 : 1,
                                    ),
                                  ),
                                  alignment: Alignment.center,
                                  child: Text(
                                    senderName[0].toUpperCase(),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                              ],
                              Flexible(
                                child: GestureDetector(
                                  onLongPress: own
                                      ? () => _delete(message)
                                      : null,
                                  child: Container(
                                    constraints: const BoxConstraints(
                                      maxWidth: 310,
                                    ),
                                    padding: const EdgeInsets.fromLTRB(
                                      14,
                                      10,
                                      14,
                                      9,
                                    ),
                                    decoration: BoxDecoration(
                                      color: bubbleColor,
                                      borderRadius: BorderRadius.circular(17),
                                      border: owner
                                          ? Border.all(
                                              color: const Color(0xFFFFD978),
                                            )
                                          : null,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Flexible(
                                              child: Text(
                                                senderName,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color: owner
                                                      ? const Color(0xFFFFF1C4)
                                                      : Colors.white,
                                                  fontSize: 11.5,
                                                  fontWeight: FontWeight.w900,
                                                ),
                                              ),
                                            ),
                                            if (owner) ...[
                                              const SizedBox(width: 7),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 7,
                                                      vertical: 2,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: const Color(
                                                    0xFFFFD978,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(20),
                                                ),
                                                child: const Text(
                                                  'OWNER',
                                                  style: TextStyle(
                                                    color: Color(0xFF352600),
                                                    fontSize: 8.5,
                                                    fontWeight: FontWeight.w900,
                                                  ),
                                                ),
                                              ),
                                            ],
                                            if (!own) ...[
                                              const SizedBox(width: 3),
                                              IconButton(
                                                tooltip: 'Report message',
                                                visualDensity:
                                                    VisualDensity.compact,
                                                constraints:
                                                    const BoxConstraints(
                                                      minWidth: 28,
                                                      minHeight: 28,
                                                    ),
                                                padding: EdgeInsets.zero,
                                                onPressed: () =>
                                                    _report(message),
                                                icon: const Icon(
                                                  Icons.flag_outlined,
                                                  color: Color(0xFFE4E6EE),
                                                  size: 15,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                        const SizedBox(height: 5),
                                        Text(
                                          message.text,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 14,
                                            height: 1.4,
                                          ),
                                        ),
                                        const SizedBox(height: 5),
                                        Align(
                                          alignment: Alignment.centerRight,
                                          child: Text(
                                            _time(message.createdAt),
                                            style: const TextStyle(
                                              color: Color(0xFFD9DCE6),
                                              fontSize: 10,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              decoration: const BoxDecoration(
                color: Color(0xFF0F1421),
                border: Border(top: BorderSide(color: Color(0xFF222A3A))),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      minLines: 1,
                      maxLines: 5,
                      textCapitalization: TextCapitalization.sentences,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Message your organization...',
                        hintStyle: const TextStyle(color: Color(0xFF737B8F)),
                        filled: true,
                        fillColor: const Color(0xFF171D2C),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(17),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 15,
                          vertical: 12,
                        ),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Container(
                    decoration: BoxDecoration(
                      color: _isSending
                          ? const Color(0xFF343A4B)
                          : const Color(0xFF766DFF),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: IconButton(
                      onPressed: _isSending ? null : _send,
                      icon: _isSending
                          ? const SizedBox(
                              width: 19,
                              height: 19,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.send_rounded, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
