import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

class RelatedDocumentService {
  RelatedDocumentService._();

  static Future<List<Map<String, dynamic>>> findRelated({
    required Map<String, dynamic> document,
    int limit = 12,
  }) async {
    final String documentId = document['id']?.toString() ?? '';
    final String category = document['category']?.toString().trim() ?? '';
    final String subject =
        document['detected_subject']?.toString().trim() ?? '';
    final String space = document['space']?.toString() ?? 'personal';
    final String userId = document['user_id']?.toString() ?? '';
    final String organizationId = document['organization_id']?.toString() ?? '';

    final supabase.SupabaseClient client = supabase.Supabase.instance.client;

    dynamic query = client.from('documents').select().eq('space', space);

    if (space == 'personal' && userId.isNotEmpty) {
      query = query.eq('user_id', userId);
    } else if (space == 'organization' && organizationId.isNotEmpty) {
      query = query.eq('organization_id', organizationId);
    }

    final List<dynamic> response = await query
        .order('created_at', ascending: false)
        .limit(100);

    final List<Map<String, dynamic>> candidates = response
        .map((item) => Map<String, dynamic>.from(item as Map))
        .where((item) => item['id']?.toString() != documentId)
        .toList();

    int score(Map<String, dynamic> item) {
      int value = 0;

      final String itemCategory = item['category']?.toString().trim() ?? '';
      final String itemSubject =
          item['detected_subject']?.toString().trim() ?? '';
      final String itemName = item['file_name']?.toString().toLowerCase() ?? '';
      final String currentName =
          document['file_name']?.toString().toLowerCase() ?? '';

      if (subject.isNotEmpty &&
          itemSubject.isNotEmpty &&
          subject.toLowerCase() == itemSubject.toLowerCase()) {
        value += 10;
      }

      if (category.isNotEmpty &&
          itemCategory.isNotEmpty &&
          category.toLowerCase() == itemCategory.toLowerCase()) {
        value += 5;
      }

      final Set<String> currentWords = _importantWords(currentName);
      final Set<String> itemWords = _importantWords(itemName);

      value += currentWords.intersection(itemWords).length * 2;

      return value;
    }

    candidates.sort((a, b) => score(b).compareTo(score(a)));

    return candidates.where((item) => score(item) > 0).take(limit).toList();
  }

  static Set<String> _importantWords(String value) {
    const Set<String> ignored = {
      'pdf',
      'doc',
      'docx',
      'txt',
      'jpg',
      'jpeg',
      'png',
      'file',
      'document',
      'notes',
      'final',
      'new',
      'copy',
    };

    return value
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((word) => word.length >= 3 && !ignored.contains(word))
        .toSet();
  }
}
