import 'package:cloud_firestore/cloud_firestore.dart';

enum KeeperMemorySpace { personal, organization }

class KeeperMemory {
  final String id;
  final String userId;
  final String organizationId;
  final KeeperMemorySpace space;
  final String title;
  final String content;
  final List<String> keywords;
  final DateTime createdAt;
  final DateTime updatedAt;

  const KeeperMemory({
    required this.id,
    required this.userId,
    required this.organizationId,
    required this.space,
    required this.title,
    required this.content,
    required this.keywords,
    required this.createdAt,
    required this.updatedAt,
  });

  factory KeeperMemory.fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) {
    final Map<String, dynamic> data = snapshot.data() ?? const {};

    DateTime readDate(dynamic value) {
      if (value is Timestamp) return value.toDate();
      return DateTime.tryParse(value?.toString() ?? '') ?? DateTime.now();
    }

    final String rawSpace = data['space']?.toString() ?? 'personal';

    return KeeperMemory(
      id: snapshot.id,
      userId: data['userId']?.toString() ?? '',
      organizationId: data['organizationId']?.toString() ?? '',
      space: rawSpace == 'organization'
          ? KeeperMemorySpace.organization
          : KeeperMemorySpace.personal,
      title: data['title']?.toString() ?? 'Memory',
      content: data['content']?.toString() ?? '',
      keywords: (data['keywords'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .where((item) => item.trim().isNotEmpty)
          .toList(),
      createdAt: readDate(data['createdAt']),
      updatedAt: readDate(data['updatedAt']),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'userId': userId,
      'organizationId': organizationId,
      'space': space.name,
      'title': title,
      'content': content,
      'keywords': keywords,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  KeeperMemory copyWith({
    String? id,
    String? userId,
    String? organizationId,
    KeeperMemorySpace? space,
    String? title,
    String? content,
    List<String>? keywords,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return KeeperMemory(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      organizationId: organizationId ?? this.organizationId,
      space: space ?? this.space,
      title: title ?? this.title,
      content: content ?? this.content,
      keywords: keywords ?? this.keywords,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
