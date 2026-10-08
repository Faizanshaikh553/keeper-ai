import 'package:cloud_firestore/cloud_firestore.dart';

class OrganizationChatMessage {
  final String id;
  final String organizationId;
  final String userId;
  final String displayName;
  final String role;
  final bool isOwner;
  final String text;
  final DateTime createdAt;

  const OrganizationChatMessage({
    required this.id,
    required this.organizationId,
    required this.userId,
    required this.displayName,
    required this.role,
    required this.isOwner,
    required this.text,
    required this.createdAt,
  });

  factory OrganizationChatMessage.fromFirestore(
    String organizationId,
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final Map<String, dynamic> data = snapshot.data() ?? const {};
    final dynamic createdAtValue = data['createdAt'];
    final DateTime createdAt = createdAtValue is Timestamp
        ? createdAtValue.toDate()
        : DateTime.tryParse(createdAtValue?.toString() ?? '') ?? DateTime.now();

    return OrganizationChatMessage(
      id: snapshot.id,
      organizationId: organizationId,
      userId: data['userId']?.toString() ?? '',
      displayName: data['displayName']?.toString() ?? 'Member',
      role: data['role']?.toString().toLowerCase() ?? 'member',
      isOwner: data['isOwner'] as bool? ?? false,
      text: data['text']?.toString() ?? '',
      createdAt: createdAt,
    );
  }
}
