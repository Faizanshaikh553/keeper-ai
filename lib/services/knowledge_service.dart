import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'keeper_knowledge_engine.dart';

class KeeperKnowledgeBundle {
  final List<Map<String, dynamic>> personal;
  final List<Map<String, dynamic>> organization;
  final String organizationId;

  const KeeperKnowledgeBundle({
    required this.personal,
    required this.organization,
    required this.organizationId,
  });

  List<Map<String, dynamic>> forScope(String scope) {
    switch (scope) {
      case 'organization':
        return organization;
      case 'all':
        return <Map<String, dynamic>>[...personal, ...organization];
      case 'personal':
      default:
        return personal;
    }
  }
}

class KnowledgeService {
  KnowledgeService._();

  static Future<String?> loadOrganizationId(String userId) async {
    final DocumentSnapshot<Map<String, dynamic>> userDocument =
        await FirebaseFirestore.instance.collection('users').doc(userId).get();
    final Map<String, dynamic> data = userDocument.data() ?? const {};

    final dynamic value =
        data['organizationId'] ??
        data['organization_id'] ??
        data['currentOrganizationId'] ??
        data['current_organization_id'];
    final String direct = value?.toString().trim() ?? '';
    if (direct.isNotEmpty) return direct;

    final QuerySnapshot<Map<String, dynamic>> membership =
        await FirebaseFirestore.instance
            .collection('organizations')
            .where('memberIds', arrayContains: userId)
            .limit(1)
            .get();

    return membership.docs.isEmpty ? null : membership.docs.first.id;
  }

  static Future<KeeperKnowledgeBundle> loadKnowledge() async {
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const KeeperKnowledgeBundle(
        personal: <Map<String, dynamic>>[],
        organization: <Map<String, dynamic>>[],
        organizationId: '',
      );
    }

    final String organizationId = await loadOrganizationId(user.uid) ?? '';
    final supabase.SupabaseClient client = supabase.Supabase.instance.client;

    final Future<List<dynamic>> personalFuture = client
        .from('documents')
        .select()
        .eq('user_id', user.uid)
        .eq('space', 'personal')
        .order('created_at', ascending: false);

    final Future<List<dynamic>> organizationFuture = organizationId.isEmpty
        ? Future<List<dynamic>>.value(<dynamic>[])
        : client
              .from('documents')
              .select()
              .eq('space', 'organization')
              .eq('organization_id', organizationId)
              .order('created_at', ascending: false);

    final List<List<dynamic>> responses = await Future.wait(
      <Future<List<dynamic>>>[personalFuture, organizationFuture],
    );

    List<Map<String, dynamic>> convert(List<dynamic> rows) {
      return rows
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList();
    }

    return KeeperKnowledgeBundle(
      personal: convert(responses[0]),
      organization: convert(responses[1]),
      organizationId: organizationId,
    );
  }

  static List<KeeperRankedDocument> search({
    required String question,
    required KeeperKnowledgeBundle bundle,
    required String scope,
    int limit = 12,
  }) {
    return KeeperKnowledgeEngine.search(
      question: question,
      documents: bundle.forScope(scope),
      limit: limit,
    );
  }
}
