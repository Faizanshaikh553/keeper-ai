import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/memory_model.dart';

enum KeeperMemoryCommandType { none, save, list, forget, forgetAll }

class KeeperMemoryCommand {
  final KeeperMemoryCommandType type;
  final String content;
  final KeeperMemorySpace? requestedSpace;

  const KeeperMemoryCommand({
    required this.type,
    this.content = '',
    this.requestedSpace,
  });
}

class KeeperMemoryService {
  KeeperMemoryService._();

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  static User _requireUser() {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw StateError('Please sign in again.');
    }
    return user;
  }

  static Future<String?> currentOrganizationId() async {
    final User user = _requireUser();
    final DocumentSnapshot<Map<String, dynamic>> snapshot = await _firestore
        .collection('users')
        .doc(user.uid)
        .get();
    final Map<String, dynamic> data = snapshot.data() ?? const {};

    final dynamic value =
        data['organizationId'] ??
        data['organization_id'] ??
        data['currentOrganizationId'] ??
        data['current_organization_id'];

    final String organizationId = value?.toString().trim() ?? '';
    if (organizationId.isNotEmpty) return organizationId;

    final QuerySnapshot<Map<String, dynamic>> membership = await _firestore
        .collection('organizations')
        .where('memberIds', arrayContains: user.uid)
        .limit(1)
        .get();

    return membership.docs.isEmpty ? null : membership.docs.first.id;
  }

  static CollectionReference<Map<String, dynamic>> _personalCollection(
    String userId,
  ) {
    return _firestore
        .collection('users')
        .doc(userId)
        .collection('keeper_memories');
  }

  static CollectionReference<Map<String, dynamic>> _organizationCollection(
    String organizationId,
  ) {
    return _firestore
        .collection('organizations')
        .doc(organizationId)
        .collection('keeper_memories');
  }

  static Future<KeeperMemory> saveMemory({
    required String content,
    required KeeperMemorySpace space,
    String? customTitle,
  }) async {
    final User user = _requireUser();
    final String cleaned = _cleanContent(content);

    if (cleaned.length < 2) {
      throw ArgumentError('Memory content is empty.');
    }

    String organizationId = '';
    CollectionReference<Map<String, dynamic>> collection;

    if (space == KeeperMemorySpace.organization) {
      organizationId = await currentOrganizationId() ?? '';
      if (organizationId.isEmpty) {
        throw StateError('No organization is linked with this account.');
      }
      collection = _organizationCollection(organizationId);
    } else {
      collection = _personalCollection(user.uid);
    }

    final DocumentReference<Map<String, dynamic>> reference = collection.doc();
    final DateTime now = DateTime.now();
    final KeeperMemory memory = KeeperMemory(
      id: reference.id,
      userId: user.uid,
      organizationId: organizationId,
      space: space,
      title: _buildTitle(
        customTitle?.trim().isNotEmpty == true ? customTitle!.trim() : cleaned,
      ),
      content: cleaned,
      keywords: _keywords(cleaned).take(30).toList(),
      createdAt: now,
      updatedAt: now,
    );

    await reference.set({
      ...memory.toFirestore(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    return memory;
  }

  static Future<List<KeeperMemory>> loadMemories({
    required KeeperMemorySpace space,
    int limit = 200,
  }) async {
    final User user = _requireUser();
    Query<Map<String, dynamic>> query;

    if (space == KeeperMemorySpace.organization) {
      final String organizationId = await currentOrganizationId() ?? '';
      if (organizationId.isEmpty) return const <KeeperMemory>[];
      query = _organizationCollection(organizationId);
    } else {
      query = _personalCollection(user.uid);
    }

    final QuerySnapshot<Map<String, dynamic>> snapshot = await query
        .orderBy('updatedAt', descending: true)
        .limit(limit)
        .get();

    return snapshot.docs
        .map(KeeperMemory.fromFirestore)
        .where((memory) => memory.content.trim().isNotEmpty)
        .toList();
  }

  static Future<List<KeeperMemory>> findRelevantMemories({
    required String question,
    required String scope,
    int limit = 6,
  }) async {
    final List<KeeperMemory> memories = <KeeperMemory>[];

    if (scope == 'personal' || scope == 'all') {
      memories.addAll(
        await loadMemories(space: KeeperMemorySpace.personal, limit: 120),
      );
    }

    if (scope == 'organization' || scope == 'all') {
      memories.addAll(
        await loadMemories(space: KeeperMemorySpace.organization, limit: 120),
      );
    }

    if (memories.isEmpty) return const <KeeperMemory>[];

    final Set<String> questionTerms = _keywords(question).toSet();
    final String normalizedQuestion = _normalize(question);

    final List<({KeeperMemory memory, double score})> ranked = memories
        .map((m) {
          final Set<String> memoryTerms = <String>{
            ...m.keywords,
            ..._keywords('${m.title} ${m.content}'),
          };
          final int overlap = questionTerms.intersection(memoryTerms).length;
          double score = overlap * 12.0;

          final String normalizedMemory = _normalize('${m.title} ${m.content}');
          if (normalizedQuestion.isNotEmpty &&
              normalizedMemory.contains(normalizedQuestion)) {
            score += 30;
          }

          if (overlap == 0 &&
              _isBroadMemoryRecallQuestion(normalizedQuestion)) {
            score += 5;
          }

          final int ageDays = DateTime.now().difference(m.updatedAt).inDays;
          score += max(0.0, 4.0 - (ageDays / 90)).toDouble();
          return (memory: m, score: score);
        })
        .where((item) => item.score > 0)
        .toList();

    ranked.sort((a, b) => b.score.compareTo(a.score));
    return ranked.take(limit).map((item) => item.memory).toList();
  }

  static Future<void> deleteMemory(KeeperMemory memory) async {
    final User user = _requireUser();
    if (memory.space == KeeperMemorySpace.organization) {
      if (memory.organizationId.isEmpty) return;
      await _organizationCollection(
        memory.organizationId,
      ).doc(memory.id).delete();
      return;
    }

    await _personalCollection(user.uid).doc(memory.id).delete();
  }

  static Future<int> deleteAll({required KeeperMemorySpace space}) async {
    final List<KeeperMemory> memories = await loadMemories(space: space);
    if (memories.isEmpty) return 0;

    for (int start = 0; start < memories.length; start += 400) {
      final WriteBatch batch = _firestore.batch();
      final int end = min(start + 400, memories.length);

      for (final KeeperMemory memory in memories.sublist(start, end)) {
        final DocumentReference<Map<String, dynamic>> reference =
            memory.space == KeeperMemorySpace.organization
            ? _organizationCollection(memory.organizationId).doc(memory.id)
            : _personalCollection(memory.userId).doc(memory.id);
        batch.delete(reference);
      }
      await batch.commit();
    }

    return memories.length;
  }

  static Future<KeeperMemory?> forgetBestMatch({
    required String description,
    required KeeperMemorySpace space,
  }) async {
    final List<KeeperMemory> memories = await loadMemories(space: space);
    if (memories.isEmpty) return null;

    final Set<String> queryTerms = _keywords(description).toSet();
    KeeperMemory? best;
    double bestScore = 0;

    for (final KeeperMemory memory in memories) {
      final Set<String> memoryTerms = _keywords(
        '${memory.title} ${memory.content}',
      ).toSet();
      final double score =
          queryTerms.intersection(memoryTerms).length * 10.0 +
          (_normalize(memory.content).contains(_normalize(description))
              ? 25
              : 0);

      if (score > bestScore) {
        bestScore = score;
        best = memory;
      }
    }

    if (best == null || bestScore <= 0) return null;
    await deleteMemory(best);
    return best;
  }

  static KeeperMemoryCommand parseCommand(String question) {
    final String normalized = _normalize(question);
    final KeeperMemorySpace? requestedSpace = _detectRequestedSpace(normalized);

    if (_containsAny(normalized, const [
      'forget all memories',
      'delete all memories',
      'clear all memories',
      'sab memories delete',
      'sari memories delete',
      'saari memories delete',
      'sab yaad bhul jao',
    ])) {
      return KeeperMemoryCommand(
        type: KeeperMemoryCommandType.forgetAll,
        requestedSpace: requestedSpace,
      );
    }

    if (_containsAny(normalized, const [
      'show my memories',
      'show memories',
      'what do you remember',
      'what have you remembered',
      'remembered things',
      'meri memories',
      'memory dikhao',
      'kya yaad hai',
      'tumhe kya yaad hai',
      'saved memories',
    ])) {
      return KeeperMemoryCommand(
        type: KeeperMemoryCommandType.list,
        requestedSpace: requestedSpace,
      );
    }

    if (_containsAny(normalized, const [
      'forget this',
      'forget that',
      'delete this memory',
      'remove this memory',
      'isko bhul jao',
      'ye bhul jao',
      'memory delete karo',
    ])) {
      return KeeperMemoryCommand(
        type: KeeperMemoryCommandType.forget,
        content: _stripCommandPrefix(question, const [
          'forget this',
          'forget that',
          'delete this memory',
          'remove this memory',
          'isko bhul jao',
          'ye bhul jao',
          'memory delete karo',
        ]),
        requestedSpace: requestedSpace,
      );
    }

    if (_containsAny(normalized, const [
      'remember this',
      'remember that',
      'save this',
      'save that',
      'store this',
      'note this',
      'yaad rakho',
      'yaad rakhna',
      'isko yaad rakho',
      'ye yaad rakho',
      'memory me save',
      'memory mein save',
    ])) {
      return KeeperMemoryCommand(
        type: KeeperMemoryCommandType.save,
        content: _stripCommandPrefix(question, const [
          'remember this',
          'remember that',
          'save this',
          'save that',
          'store this',
          'note this',
          'yaad rakho',
          'yaad rakhna',
          'isko yaad rakho',
          'ye yaad rakho',
          'memory me save',
          'memory mein save',
        ]),
        requestedSpace: requestedSpace,
      );
    }

    return const KeeperMemoryCommand(type: KeeperMemoryCommandType.none);
  }

  static KeeperMemorySpace defaultSpaceForScope(String scope) {
    return scope == 'organization'
        ? KeeperMemorySpace.organization
        : KeeperMemorySpace.personal;
  }

  static String _stripCommandPrefix(String original, List<String> phrases) {
    String value = original.trim();
    final String lower = value.toLowerCase();

    int bestIndex = -1;
    int bestLength = 0;
    for (final String phrase in phrases) {
      final int index = lower.indexOf(phrase);
      if (index >= 0 && (bestIndex < 0 || index < bestIndex)) {
        bestIndex = index;
        bestLength = phrase.length;
      }
    }

    if (bestIndex >= 0) {
      value = value.substring(bestIndex + bestLength).trim();
    }

    return value
        .replaceFirst(RegExp(r'^[:;,\-–—]+\s*'), '')
        .replaceAll(
          RegExp(
            r'\b(personal|organization|organisation|org)\s+memory\b',
            caseSensitive: false,
          ),
          '',
        )
        .trim();
  }

  static KeeperMemorySpace? _detectRequestedSpace(String value) {
    if (_containsAny(value, const [
      'organization memory',
      'organisation memory',
      'org memory',
      'organization me',
      'organisation me',
    ])) {
      return KeeperMemorySpace.organization;
    }
    if (_containsAny(value, const [
      'personal memory',
      'personal me',
      'meri personal',
    ])) {
      return KeeperMemorySpace.personal;
    }
    return null;
  }

  static bool _isBroadMemoryRecallQuestion(String value) {
    return _containsAny(value, const [
      'what do you know about me',
      'what do you remember',
      'mere bare me',
      'mere baare me',
      'pending work',
      'pending task',
      'meri preference',
    ]);
  }

  static bool _containsAny(String value, List<String> phrases) {
    return phrases.any(value.contains);
  }

  static String _cleanContent(String value) {
    return value
        .replaceAll('\u0000', '')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  static String _buildTitle(String content) {
    final String singleLine = content.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (singleLine.length <= 56) return singleLine;
    return '${singleLine.substring(0, 56).trim()}...';
  }

  static Iterable<String> _keywords(String value) {
    const Set<String> ignored = {
      'about',
      'after',
      'again',
      'also',
      'and',
      'are',
      'because',
      'before',
      'from',
      'have',
      'into',
      'more',
      'that',
      'the',
      'their',
      'there',
      'these',
      'they',
      'this',
      'those',
      'what',
      'when',
      'where',
      'which',
      'with',
      'your',
      'hai',
      'hain',
      'ka',
      'ki',
      'ke',
      'ko',
      'kya',
      'mein',
      'me',
      'mera',
      'mere',
      'meri',
      'mujhe',
      'nahi',
      'rakho',
      'rakhna',
      'yaad',
      'isko',
    };

    return _normalize(value)
        .split(' ')
        .where((word) => word.length >= 3 && !ignored.contains(word))
        .toSet();
  }

  static String _normalize(String value) {
    return value
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\u0900-\u097f\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
