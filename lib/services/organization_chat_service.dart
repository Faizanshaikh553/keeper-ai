import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/organization_chat_message_model.dart';

class OrganizationChatService {
  OrganizationChatService._();

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static User _requireUser() {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Please sign in again.');
    return user;
  }

  static CollectionReference<Map<String, dynamic>> _messages(
    String organizationId,
  ) {
    return _firestore
        .collection('organizations')
        .doc(organizationId)
        .collection('group_messages');
  }

  static Stream<List<OrganizationChatMessage>> watchMessages(
    String organizationId,
  ) {
    return _messages(organizationId)
        .orderBy('createdAt', descending: true)
        .limit(150)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(
                (document) => OrganizationChatMessage.fromFirestore(
                  organizationId,
                  document,
                ),
              )
              .where((message) => message.text.trim().isNotEmpty)
              .toList(),
        );
  }

  static Future<bool> isMember(String organizationId) async {
    final User user = _requireUser();
    final DocumentSnapshot<Map<String, dynamic>> organization = await _firestore
        .collection('organizations')
        .doc(organizationId)
        .get();
    final Map<String, dynamic> data = organization.data() ?? const {};

    final String ownerId = data['ownerId']?.toString() ?? '';
    final List<String> memberIds =
        (data['memberIds'] as List<dynamic>? ?? const [])
            .map((item) => item.toString())
            .toList();
    final List<String> adminIds =
        (data['adminIds'] as List<dynamic>? ?? const [])
            .map((item) => item.toString())
            .toList();

    if (ownerId == user.uid ||
        memberIds.contains(user.uid) ||
        adminIds.contains(user.uid)) {
      return true;
    }

    final DocumentSnapshot<Map<String, dynamic>> memberDocument =
        await _firestore
            .collection('organizations')
            .doc(organizationId)
            .collection('members')
            .doc(user.uid)
            .get();
    return memberDocument.exists;
  }

  static Future<void> sendMessage({
    required String organizationId,
    required String text,
  }) async {
    final User user = _requireUser();
    final String cleaned = text
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();

    if (cleaned.isEmpty) return;
    if (cleaned.length > 2000) {
      throw ArgumentError('Message is too long. Maximum 2000 characters.');
    }
    if (!await isMember(organizationId)) {
      throw StateError('You are not a member of this organization.');
    }

    final DocumentSnapshot<Map<String, dynamic>> organization = await _firestore
        .collection('organizations')
        .doc(organizationId)
        .get();
    final Map<String, dynamic> organizationData =
        organization.data() ?? const {};
    final String ownerId = organizationData['ownerId']?.toString() ?? '';
    final List<String> adminIds =
        (organizationData['adminIds'] as List<dynamic>? ?? const [])
            .map((item) => item.toString())
            .toList();

    String role = 'member';
    if (ownerId == user.uid) {
      role = 'owner';
    } else if (adminIds.contains(user.uid)) {
      role = 'admin';
    } else {
      final DocumentSnapshot<Map<String, dynamic>> membership = await _firestore
          .collection('organizations')
          .doc(organizationId)
          .collection('members')
          .doc(user.uid)
          .get();
      role = membership.data()?['role']?.toString().toLowerCase() ?? 'member';
    }

    String displayName = user.displayName?.trim() ?? '';
    if (displayName.isEmpty) {
      final DocumentSnapshot<Map<String, dynamic>> profile = await _firestore
          .collection('users')
          .doc(user.uid)
          .get();
      displayName = profile.data()?['name']?.toString().trim() ?? '';
    }
    if (displayName.isEmpty) {
      displayName = user.email?.split('@').first ?? 'Member';
    }

    await _messages(organizationId).add({
      'organizationId': organizationId,
      'userId': user.uid,
      'displayName': displayName,
      'role': role,
      'isOwner': role == 'owner',
      'text': cleaned,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  static Future<void> deleteOwnMessage(OrganizationChatMessage message) async {
    final User user = _requireUser();
    if (message.userId != user.uid) {
      throw StateError('You can delete only your own message.');
    }

    await _messages(message.organizationId).doc(message.id).delete();
  }

  static Future<void> reportMessage({
    required OrganizationChatMessage message,
    required String reason,
  }) async {
    final User user = _requireUser();
    if (message.userId == user.uid) {
      throw StateError('You cannot report your own message.');
    }
    if (!await isMember(message.organizationId)) {
      throw StateError('You are not a member of this organization.');
    }

    await _firestore.collection('group_message_reports').add({
      'organizationId': message.organizationId,
      'messageId': message.id,
      'reportedUserId': message.userId,
      'reporterUserId': user.uid,
      'reason': reason,
      'messagePreview': message.text.length > 1000
          ? message.text.substring(0, 1000)
          : message.text,
      'status': 'open',
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}
