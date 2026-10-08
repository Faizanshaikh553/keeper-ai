import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

class DuplicateCheckResult {
  final bool isDuplicate;
  final String? existingDocumentId;
  final String? existingFileName;

  const DuplicateCheckResult({
    required this.isDuplicate,
    required this.existingDocumentId,
    required this.existingFileName,
  });
}

class DuplicateDocumentService {
  DuplicateDocumentService._();

  static Future<DuplicateCheckResult> checkDuplicate({
    required String fileName,
    required int fileSize,
    required String userId,
    required String space,
    String? organizationId,
  }) async {
    final supabase.SupabaseClient client = supabase.Supabase.instance.client;

    dynamic query = client
        .from('documents')
        .select('id, file_name, file_size')
        .eq('file_name', fileName)
        .eq('file_size', fileSize)
        .eq('space', space);

    if (space == 'personal') {
      query = query.eq('user_id', userId);
    } else if (space == 'organization' &&
        organizationId != null &&
        organizationId.isNotEmpty) {
      query = query.eq('organization_id', organizationId);
    }

    final List<dynamic> response = await query.limit(1) as List<dynamic>;

    if (response.isEmpty) {
      return const DuplicateCheckResult(
        isDuplicate: false,
        existingDocumentId: null,
        existingFileName: null,
      );
    }

    final Map<String, dynamic> existing = Map<String, dynamic>.from(
      response.first as Map,
    );

    return DuplicateCheckResult(
      isDuplicate: true,
      existingDocumentId: existing['id']?.toString(),
      existingFileName:
          existing['file_name']?.toString() ?? 'Existing document',
    );
  }
}
