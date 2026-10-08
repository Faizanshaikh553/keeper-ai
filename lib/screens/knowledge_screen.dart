import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'document_viewer_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import '../services/keeper_knowledge_engine.dart';

class KnowledgeScreen extends StatefulWidget {
  const KnowledgeScreen({super.key});

  @override
  State<KnowledgeScreen> createState() => _KnowledgeScreenState();
}

class _KnowledgeScreenState extends State<KnowledgeScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  String? _errorMessage;
  String _searchQuery = '';

  List<Map<String, dynamic>> _personalDocuments = [];
  List<Map<String, dynamic>> _organizationDocuments = [];

  @override
  void initState() {
    super.initState();

    _tabController = TabController(length: 2, vsync: this);

    _searchController.addListener(() {
      if (!mounted) return;

      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });

    _loadKnowledge();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _loadKnowledge() async {
    final User? user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _errorMessage = 'Please sign in again.';
      });

      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final supabase.SupabaseClient client = supabase.Supabase.instance.client;

      final List<dynamic> personalResponse = await client
          .from('documents')
          .select()
          .eq('user_id', user.uid)
          .eq('space', 'personal')
          .order('created_at', ascending: false);

      final List<dynamic> organizationResponse = await client
          .from('documents')
          .select()
          .eq('space', 'organization')
          .order('created_at', ascending: false);

      if (!mounted) return;

      KeeperKnowledgeEngine.clearCache();

      setState(() {
        _personalDocuments = personalResponse
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();

        _organizationDocuments = organizationResponse
            .map((item) => Map<String, dynamic>.from(item as Map))
            .toList();

        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _errorMessage = 'Unable to load knowledge: $error';
      });
    }
  }

  List<Map<String, dynamic>> _filterDocuments(
    List<Map<String, dynamic>> documents,
  ) {
    if (_searchQuery.isEmpty) {
      return documents;
    }

    final List<KeeperRankedDocument> ranked = KeeperKnowledgeEngine.search(
      question: _searchQuery,
      documents: documents,
      limit: documents.length,
    );

    return ranked.map((result) {
      final Map<String, dynamic> document = Map<String, dynamic>.from(
        result.document.raw,
      );

      document['_keeper_score'] = result.score;
      document['_keeper_snippet'] = result.snippet;
      document['_keeper_matched_terms'] = result.matchedTerms;

      return document;
    }).toList();
  }

  String _matchingSnippet(Map<String, dynamic> document) {
    final String engineSnippet =
        document['_keeper_snippet']?.toString().trim() ?? '';

    if (engineSnippet.isNotEmpty) {
      return engineSnippet;
    }

    final String extractedText =
        document['extracted_text']?.toString().trim() ?? '';

    if (extractedText.isEmpty) {
      return 'No extracted text available.';
    }

    if (extractedText.length <= 150) {
      return extractedText;
    }

    return '${extractedText.substring(0, 150)}...';
  }

  Map<String, int> _categoryCounts(List<Map<String, dynamic>> documents) {
    final Map<String, int> counts = {};

    for (final Map<String, dynamic> document in documents) {
      final String rawCategory = document['category']?.toString().trim() ?? '';

      final String category = rawCategory.isEmpty ? 'Other' : rawCategory;

      counts[category] = (counts[category] ?? 0) + 1;
    }

    return counts;
  }

  Future<void> _openDocument(Map<String, dynamic> document) async {
    final String fileUrl = document['file_url']?.toString() ?? '';
    final String fileName = document['file_name']?.toString() ?? 'Document';
    final String extractedText = document['extracted_text']?.toString() ?? '';

    if (fileUrl.isEmpty && extractedText.trim().isEmpty) {
      _showMessage('This document is not available.');
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DocumentViewerScreen(
          fileName: fileName,
          fileUrl: fileUrl,
          extractedText: extractedText,
        ),
      ),
    );
  }

  String _formatDate(dynamic value) {
    final DateTime? date = DateTime.tryParse(
      value?.toString() ?? '',
    )?.toLocal();

    if (date == null) {
      return 'Unknown date';
    }

    final String day = date.day.toString().padLeft(2, '0');

    final String month = date.month.toString().padLeft(2, '0');

    return '$day/$month/${date.year}';
  }

  IconData _categoryIcon(String category) {
    final String value = category.toLowerCase();

    if (value.contains('timetable')) {
      return Icons.calendar_month_rounded;
    }

    if (value.contains('syllabus')) {
      return Icons.menu_book_rounded;
    }

    if (value.contains('previous') || value.contains('paper')) {
      return Icons.quiz_outlined;
    }

    if (value.contains('notice')) {
      return Icons.campaign_outlined;
    }

    if (value.contains('assignment')) {
      return Icons.assignment_outlined;
    }

    if (value.contains('certificate')) {
      return Icons.workspace_premium_outlined;
    }

    if (value.contains('aadhaar') || value.contains('pan')) {
      return Icons.badge_outlined;
    }

    return Icons.folder_copy_outlined;
  }

  IconData _fileIcon(String fileName) {
    final String lowerName = fileName.toLowerCase();

    if (lowerName.endsWith('.pdf')) {
      return Icons.picture_as_pdf_rounded;
    }

    if (lowerName.endsWith('.doc') || lowerName.endsWith('.docx')) {
      return Icons.description_rounded;
    }

    if (lowerName.endsWith('.jpg') ||
        lowerName.endsWith('.jpeg') ||
        lowerName.endsWith('.png')) {
      return Icons.image_rounded;
    }

    if (lowerName.endsWith('.txt')) {
      return Icons.notes_rounded;
    }

    return Icons.insert_drive_file_rounded;
  }

  Widget _buildSummary(List<Map<String, dynamic>> documents, String spaceName) {
    final Map<String, int> categories = _categoryCounts(documents);

    return Container(
      margin: const EdgeInsets.fromLTRB(18, 18, 18, 0),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF25205C), Color(0xFF151933)],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFF393274)),
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: const Color(0xFF312B70),
              borderRadius: BorderRadius.circular(17),
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              color: Color(0xFFB9B4FF),
              size: 29,
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$spaceName Knowledge',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '${documents.length} documents • ${categories.length} categories',
                  style: const TextStyle(
                    color: Color(0xFFB5B2C8),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
      child: TextField(
        controller: _searchController,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: 'Search file name, category or text...',
          hintStyle: const TextStyle(color: Color(0xFF6F7282)),
          prefixIcon: const Icon(
            Icons.search_rounded,
            color: Color(0xFF8E91A3),
          ),
          suffixIcon: _searchQuery.isEmpty
              ? null
              : IconButton(
                  onPressed: () {
                    _searchController.clear();
                  },
                  icon: const Icon(
                    Icons.close_rounded,
                    color: Color(0xFF8E91A3),
                  ),
                ),
          filled: true,
          fillColor: const Color(0xFF121725),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(17),
            borderSide: const BorderSide(color: Color(0xFF292F42)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(17),
            borderSide: const BorderSide(color: Color(0xFF766DFF), width: 1.4),
          ),
        ),
      ),
    );
  }

  Widget _buildDocumentThumbnail(
    Map<String, dynamic> document, {
    double size = 48,
  }) {
    final String fileName =
        document['file_name']?.toString().toLowerCase() ?? '';
    final String fileUrl = document['file_url']?.toString() ?? '';

    final bool isImage =
        fileName.endsWith('.jpg') ||
        fileName.endsWith('.jpeg') ||
        fileName.endsWith('.png') ||
        fileName.endsWith('.webp');

    if (isImage && fileUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.network(
          fileUrl,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) {
            return Container(
              width: size,
              height: size,
              color: const Color(0xFF24205A),
              child: const Icon(Icons.image_rounded, color: Color(0xFFAAA4FF)),
            );
          },
        ),
      );
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFF24205A),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(_fileIcon(fileName), color: const Color(0xFFAAA4FF)),
    );
  }

  Widget _buildSearchResultCard(Map<String, dynamic> document) {
    final String fileName =
        document['file_name']?.toString() ?? 'Unnamed document';

    final String category = document['category']?.toString() ?? 'Other';

    final String date = _formatDate(document['created_at']);

    final String snippet = _matchingSnippet(document);

    return GestureDetector(
      onTap: () {
        _openDocument(document);
      },
      child: Container(
        margin: const EdgeInsets.fromLTRB(18, 0, 18, 12),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: const Color(0xFF121725),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFF292F42)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDocumentThumbnail(document),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fileName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '$category • $date',
                    style: const TextStyle(
                      color: Color(0xFF8E91A3),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 9),
                  Text(
                    snippet,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFB6B8C5),
                      fontSize: 12,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFF777A8A)),
          ],
        ),
      ),
    );
  }

  Widget _buildKnowledgeTab(
    List<Map<String, dynamic>> originalDocuments,
    String spaceName,
  ) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF766DFF)),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                color: Color(0xFFEF4444),
                size: 48,
              ),
              const SizedBox(height: 14),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF9CA3AF)),
              ),
              const SizedBox(height: 18),
              ElevatedButton(
                onPressed: _loadKnowledge,
                child: const Text('Try Again'),
              ),
            ],
          ),
        ),
      );
    }

    final List<Map<String, dynamic>> documents = _filterDocuments(
      originalDocuments,
    );

    final Map<String, int> categoryCounts = _categoryCounts(documents);

    final List<MapEntry<String, int>> categories =
        categoryCounts.entries.toList()
          ..sort((first, second) => second.value.compareTo(first.value));

    if (_searchQuery.isNotEmpty) {
      return RefreshIndicator(
        color: const Color(0xFF766DFF),
        backgroundColor: const Color(0xFF121725),
        onRefresh: _loadKnowledge,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 30),
          children: [
            _buildSummary(originalDocuments, spaceName),
            _buildSearchBar(),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 24, 18, 14),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Search results',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    '${documents.length} found',
                    style: const TextStyle(
                      color: Color(0xFF938CFF),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            if (documents.isEmpty)
              const Padding(
                padding: EdgeInsets.all(35),
                child: Center(
                  child: Column(
                    children: [
                      Icon(
                        Icons.search_off_rounded,
                        color: Color(0xFF766DFF),
                        size: 54,
                      ),
                      SizedBox(height: 14),
                      Text(
                        'No matching knowledge found.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Color(0xFF9CA3AF),
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              ...documents.map(_buildSearchResultCard),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: const Color(0xFF766DFF),
      backgroundColor: const Color(0xFF121725),
      onRefresh: _loadKnowledge,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 30),
        children: [
          _buildSummary(originalDocuments, spaceName),
          _buildSearchBar(),
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 25, 18, 12),
            child: Text(
              'Knowledge categories',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (categories.isEmpty)
            const Padding(
              padding: EdgeInsets.all(30),
              child: Center(
                child: Text(
                  'No knowledge found.',
                  style: TextStyle(color: Color(0xFF9CA3AF)),
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: categories.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.35,
                ),
                itemBuilder: (context, index) {
                  final MapEntry<String, int> item = categories[index];

                  return GestureDetector(
                    onTap: () {
                      final String selectedCategory = item.key;

                      final List<Map<String, dynamic>> categoryDocuments =
                          documents.where((document) {
                            final String documentCategory =
                                document['category']?.toString() ?? 'Other';

                            return documentCategory == selectedCategory;
                          }).toList();

                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => CategoryDocumentsScreen(
                            categoryName: selectedCategory,
                            documents: categoryDocuments,
                          ),
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(
                        color: const Color(0xFF121725),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0xFF292F42)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Icon(
                            _categoryIcon(item.key),
                            color: const Color(0xFF938CFF),
                            size: 28,
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.key,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${item.value} documents',
                                style: const TextStyle(
                                  color: Color(0xFF8E91A3),
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          const Padding(
            padding: EdgeInsets.fromLTRB(18, 28, 18, 12),
            child: Text(
              'Recent documents',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),

          if (documents.isEmpty)
            const Padding(
              padding: EdgeInsets.all(30),
              child: Center(
                child: Text(
                  'No documents available.',
                  style: TextStyle(color: Color(0xFF9CA3AF)),
                ),
              ),
            )
          else
            ...documents.take(5).map((document) {
              final String fileName =
                  document['file_name']?.toString() ?? 'Unnamed document';

              final String category =
                  document['category']?.toString() ?? 'Other';

              final String date = _formatDate(document['created_at']);

              return GestureDetector(
                onTap: () {
                  _openDocument(document);
                },
                child: Container(
                  margin: const EdgeInsets.fromLTRB(18, 0, 18, 11),
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: const Color(0xFF121725),
                    borderRadius: BorderRadius.circular(17),
                    border: Border.all(color: const Color(0xFF292F42)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 45,
                        height: 45,
                        decoration: BoxDecoration(
                          color: const Color(0xFF24205A),
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: Icon(
                          _fileIcon(fileName),
                          color: const Color(0xFFAAA4FF),
                        ),
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              fileName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 5),
                            Text(
                              '$category • $date',
                              style: const TextStyle(
                                color: Color(0xFF8E91A3),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: Color(0xFF777A8A),
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF090D18),
      appBar: AppBar(
        backgroundColor: const Color(0xFF090D18),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Knowledge',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _loadKnowledge,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF766DFF),
          labelColor: Colors.white,
          unselectedLabelColor: const Color(0xFF7F8292),
          tabs: const [
            Tab(icon: Icon(Icons.person_outline_rounded), text: 'Personal'),
            Tab(icon: Icon(Icons.apartment_rounded), text: 'Organization'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildKnowledgeTab(_personalDocuments, 'Personal'),
          _buildKnowledgeTab(_organizationDocuments, 'Organization'),
        ],
      ),
    );
  }
}

class CategoryDocumentsScreen extends StatelessWidget {
  final String categoryName;
  final List<Map<String, dynamic>> documents;

  const CategoryDocumentsScreen({
    super.key,
    required this.categoryName,
    required this.documents,
  });

  void _showMessage(BuildContext context, String message) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openDocument(
    BuildContext context,
    Map<String, dynamic> document,
  ) async {
    final String fileUrl = document['file_url']?.toString() ?? '';
    final String fileName = document['file_name']?.toString() ?? 'Document';
    final String extractedText = document['extracted_text']?.toString() ?? '';

    if (fileUrl.isEmpty && extractedText.trim().isEmpty) {
      _showMessage(context, 'This document is not available.');
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DocumentViewerScreen(
          fileName: fileName,
          fileUrl: fileUrl,
          extractedText: extractedText,
        ),
      ),
    );
  }

  String _formatDate(dynamic value) {
    final DateTime? date = DateTime.tryParse(
      value?.toString() ?? '',
    )?.toLocal();

    if (date == null) {
      return 'Unknown date';
    }

    final String day = date.day.toString().padLeft(2, '0');

    final String month = date.month.toString().padLeft(2, '0');

    return '$day/$month/${date.year}';
  }

  IconData _fileIcon(String fileName) {
    final String lowerName = fileName.toLowerCase();

    if (lowerName.endsWith('.pdf')) {
      return Icons.picture_as_pdf_rounded;
    }

    if (lowerName.endsWith('.doc') || lowerName.endsWith('.docx')) {
      return Icons.description_rounded;
    }

    if (lowerName.endsWith('.jpg') ||
        lowerName.endsWith('.jpeg') ||
        lowerName.endsWith('.png')) {
      return Icons.image_rounded;
    }

    if (lowerName.endsWith('.txt')) {
      return Icons.notes_rounded;
    }

    return Icons.insert_drive_file_rounded;
  }

  String _documentSnippet(Map<String, dynamic> document) {
    final String extractedText = document['extracted_text']?.toString() ?? '';

    final String cleanedText = extractedText
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (cleanedText.isEmpty) {
      return 'No extracted text available.';
    }

    if (cleanedText.length <= 130) {
      return cleanedText;
    }

    return '${cleanedText.substring(0, 130)}...';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF090D18),
      appBar: AppBar(
        backgroundColor: const Color(0xFF090D18),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          categoryName,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: documents.isEmpty
          ? const Center(
              child: Text(
                'No documents found.',
                style: TextStyle(color: Color(0xFF9CA3AF)),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(18),
              itemCount: documents.length,
              separatorBuilder: (context, index) {
                return const SizedBox(height: 12);
              },
              itemBuilder: (context, index) {
                final Map<String, dynamic> document = documents[index];

                final String fileName =
                    document['file_name']?.toString() ?? 'Unnamed document';

                final String date = _formatDate(document['created_at']);

                final String snippet = _documentSnippet(document);

                return GestureDetector(
                  onTap: () {
                    _openDocument(context, document);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(15),
                    decoration: BoxDecoration(
                      color: const Color(0xFF121725),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFF292F42)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: const Color(0xFF24205A),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            _fileIcon(fileName),
                            color: const Color(0xFFAAA4FF),
                          ),
                        ),
                        const SizedBox(width: 13),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                fileName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 5),
                              Text(
                                date,
                                style: const TextStyle(
                                  color: Color(0xFF8E91A3),
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                snippet,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xFFB6B8C5),
                                  fontSize: 12,
                                  height: 1.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.chevron_right_rounded,
                          color: Color(0xFF777A8A),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
