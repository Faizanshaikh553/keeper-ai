import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'document_viewer_screen.dart';
import '../services/keeper_knowledge_engine.dart';

enum UniversalSearchFilter {
  all,
  personal,
  organization,
  pdf,
  images,
  notes,
  certificates,
  questionPapers,
  assignments,
}

class UniversalSearchScreen extends StatefulWidget {
  const UniversalSearchScreen({super.key});

  @override
  State<UniversalSearchScreen> createState() => _UniversalSearchScreenState();
}

class _UniversalSearchScreenState extends State<UniversalSearchScreen> {
  static final Map<String, List<Map<String, dynamic>>> _personalCache = {};
  static final Map<String, List<Map<String, dynamic>>> _organizationCache = {};
  static final Map<String, String> _organizationIdCache = {};

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  List<Map<String, dynamic>> _personalDocuments = [];
  List<Map<String, dynamic>> _organizationDocuments = [];

  UniversalSearchFilter _selectedFilter = UniversalSearchFilter.all;
  String _selectedSubject = 'All Subjects';
  String _selectedSort = 'Relevance';

  bool _isLoading = true;
  bool _isRefreshing = false;
  String _query = '';
  String? _errorMessage;

  @override
  void initState() {
    super.initState();

    _searchController.addListener(() {
      final String value = _searchController.text.trim().toLowerCase();

      if (value == _query) {
        return;
      }

      setState(() {
        _query = value;
      });
    });

    _restoreCacheAndRefresh();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _restoreCacheAndRefresh() {
    final User? user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      _loadDocuments();
      return;
    }

    final List<Map<String, dynamic>> cachedPersonal =
        _personalCache[user.uid] ?? const [];

    final String? organizationId = _organizationIdCache[user.uid];

    final List<Map<String, dynamic>> cachedOrganization = organizationId == null
        ? const []
        : (_organizationCache[organizationId] ?? const []);

    final bool hasCache =
        cachedPersonal.isNotEmpty || cachedOrganization.isNotEmpty;

    if (hasCache) {
      _personalDocuments = List<Map<String, dynamic>>.from(cachedPersonal);
      _organizationDocuments = List<Map<String, dynamic>>.from(
        cachedOrganization,
      );
      _isLoading = false;
    }

    _loadDocuments(showLoading: !hasCache);
  }

  Future<String?> _loadOrganizationId(String userId) async {
    try {
      final DocumentSnapshot<Map<String, dynamic>> userDocument =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(userId)
              .get();

      final Map<String, dynamic>? data = userDocument.data();

      if (data == null) {
        return null;
      }

      final dynamic rawOrganizationId =
          data['organizationId'] ??
          data['organization_id'] ??
          data['currentOrganizationId'] ??
          data['current_organization_id'];

      final String organizationId = rawOrganizationId?.toString().trim() ?? '';

      return organizationId.isEmpty ? null : organizationId;
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadDocuments({bool showLoading = true}) async {
    final User? user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _isRefreshing = false;
        _errorMessage = 'Please sign in again.';
      });
      return;
    }

    if (showLoading && mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    } else if (mounted) {
      setState(() {
        _isRefreshing = true;
        _errorMessage = null;
      });
    }

    try {
      final supabase.SupabaseClient client = supabase.Supabase.instance.client;

      String? organizationId = _organizationIdCache[user.uid];
      organizationId ??= await _loadOrganizationId(user.uid);

      if (organizationId != null && organizationId.isNotEmpty) {
        _organizationIdCache[user.uid] = organizationId;
      }

      final Future<List<dynamic>> personalFuture = client
          .from('documents')
          .select()
          .eq('user_id', user.uid)
          .eq('space', 'personal')
          .order('created_at', ascending: false);

      final Future<List<dynamic>> organizationFuture =
          organizationId == null || organizationId.isEmpty
          ? Future<List<dynamic>>.value(<dynamic>[])
          : client
                .from('documents')
                .select()
                .eq('space', 'organization')
                .eq('organization_id', organizationId)
                .order('created_at', ascending: false);

      final List<List<dynamic>> responses = await Future.wait([
        personalFuture,
        organizationFuture,
      ]);

      final List<Map<String, dynamic>> personalDocuments = responses[0]
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();

      final List<Map<String, dynamic>> organizationDocuments = responses[1]
          .map((item) => Map<String, dynamic>.from(item as Map))
          .toList();

      _personalCache[user.uid] = personalDocuments;

      if (organizationId != null && organizationId.isNotEmpty) {
        _organizationCache[organizationId] = organizationDocuments;
      }

      if (!mounted) return;

      KeeperKnowledgeEngine.clearCache();

      setState(() {
        _personalDocuments = personalDocuments;
        _organizationDocuments = organizationDocuments;
        _isLoading = false;
        _isRefreshing = false;
        _errorMessage = null;
      });
    } catch (error) {
      if (!mounted) return;

      final bool hasExistingData =
          _personalDocuments.isNotEmpty || _organizationDocuments.isNotEmpty;

      setState(() {
        _isLoading = false;
        _isRefreshing = false;

        if (!hasExistingData) {
          _errorMessage = 'Unable to load Keeper search: $error';
        }
      });

      if (hasExistingData) {
        _showMessage('Could not refresh. Showing cached results.');
      }
    }
  }

  List<Map<String, dynamic>> get _allDocuments => [
    ..._personalDocuments,
    ..._organizationDocuments,
  ];

  List<String> get _availableSubjects {
    final Set<String> subjects = {'All Subjects'};

    for (final Map<String, dynamic> document in _allDocuments) {
      final String subject =
          document['detected_subject']?.toString().trim() ?? '';

      if (subject.isNotEmpty) {
        subjects.add(subject);
      }
    }

    final List<String> values = subjects.toList()
      ..sort((a, b) {
        if (a == 'All Subjects') return -1;
        if (b == 'All Subjects') return 1;
        return a.compareTo(b);
      });

    return values;
  }

  List<Map<String, dynamic>> _applySmartFilters(
    List<Map<String, dynamic>> documents,
  ) {
    final List<Map<String, dynamic>> result = documents.where((document) {
      if (_selectedSubject == 'All Subjects') return true;

      final String subject =
          document['detected_subject']?.toString().trim() ?? '';

      return subject.toLowerCase() == _selectedSubject.toLowerCase();
    }).toList();

    if (_selectedSort == 'Newest') {
      result.sort((a, b) {
        final DateTime? aDate = DateTime.tryParse(
          a['created_at']?.toString() ?? '',
        );
        final DateTime? bDate = DateTime.tryParse(
          b['created_at']?.toString() ?? '',
        );

        return (bDate ?? DateTime(1970)).compareTo(aDate ?? DateTime(1970));
      });
    } else if (_selectedSort == 'Oldest') {
      result.sort((a, b) {
        final DateTime? aDate = DateTime.tryParse(
          a['created_at']?.toString() ?? '',
        );
        final DateTime? bDate = DateTime.tryParse(
          b['created_at']?.toString() ?? '',
        );

        return (aDate ?? DateTime(1970)).compareTo(bDate ?? DateTime(1970));
      });
    } else if (_selectedSort == 'Name') {
      result.sort((a, b) {
        final String aName = a['file_name']?.toString().toLowerCase() ?? '';
        final String bName = b['file_name']?.toString().toLowerCase() ?? '';

        return aName.compareTo(bName);
      });
    }

    return result;
  }

  List<Map<String, dynamic>> get _filteredDocuments {
    final List<Map<String, dynamic>> sourceDocuments =
        switch (_selectedFilter) {
          UniversalSearchFilter.personal => _personalDocuments,
          UniversalSearchFilter.organization => _organizationDocuments,
          _ => _allDocuments,
        };

    final List<Map<String, dynamic>> typeFiltered = sourceDocuments
        .where(_matchesTypeFilter)
        .toList();

    if (_query.isEmpty) {
      typeFiltered.sort((a, b) {
        final DateTime? aDate = DateTime.tryParse(
          a['created_at']?.toString() ?? '',
        );
        final DateTime? bDate = DateTime.tryParse(
          b['created_at']?.toString() ?? '',
        );

        return (bDate ?? DateTime(1970)).compareTo(aDate ?? DateTime(1970));
      });

      return _applySmartFilters(typeFiltered);
    }

    final List<KeeperRankedDocument> ranked = KeeperKnowledgeEngine.search(
      question: _query,
      documents: typeFiltered,
      limit: typeFiltered.length,
    );

    final List<Map<String, dynamic>> rankedDocuments = ranked.map((result) {
      final Map<String, dynamic> document = Map<String, dynamic>.from(
        result.document.raw,
      );

      document['_keeper_score'] = result.score;
      document['_keeper_snippet'] = result.snippet;
      document['_keeper_matched_terms'] = result.matchedTerms;

      return document;
    }).toList();

    return _applySmartFilters(rankedDocuments);
  }

  bool _matchesTypeFilter(Map<String, dynamic> document) {
    final String fileName =
        document['file_name']?.toString().toLowerCase() ?? '';

    final String category =
        document['category']?.toString().toLowerCase() ?? '';

    switch (_selectedFilter) {
      case UniversalSearchFilter.pdf:
        return fileName.endsWith('.pdf');

      case UniversalSearchFilter.images:
        return _isImage(fileName);

      case UniversalSearchFilter.notes:
        return category.contains('note') ||
            fileName.contains('note') ||
            fileName.endsWith('.txt');

      case UniversalSearchFilter.certificates:
        return category.contains('certificate') ||
            fileName.contains('certificate');

      case UniversalSearchFilter.questionPapers:
        return category.contains('previous year paper') ||
            category.contains('question paper') ||
            fileName.contains('question paper') ||
            fileName.contains('pyq');

      case UniversalSearchFilter.assignments:
        return category.contains('assignment') ||
            fileName.contains('assignment');

      case UniversalSearchFilter.all:
      case UniversalSearchFilter.personal:
      case UniversalSearchFilter.organization:
        return true;
    }
  }

  Future<void> _openDocument(Map<String, dynamic> document) async {
    final String fileName =
        document['file_name']?.toString() ?? 'Unnamed document';

    final String fileUrl = document['file_url']?.toString() ?? '';

    final String extractedText =
        document['_keeper_snippet']?.toString() ??
        document['extracted_text']?.toString() ??
        '';

    if (fileUrl.trim().isEmpty && extractedText.trim().isEmpty) {
      _showMessage('This document does not have a readable preview yet.');
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

  bool _isImage(String fileName) {
    return fileName.endsWith('.jpg') ||
        fileName.endsWith('.jpeg') ||
        fileName.endsWith('.png') ||
        fileName.endsWith('.webp');
  }

  bool _isPdf(String fileName) {
    return fileName.endsWith('.pdf');
  }

  String _formatDate(dynamic value) {
    final DateTime? date = DateTime.tryParse(
      value?.toString() ?? '',
    )?.toLocal();

    if (date == null) {
      return 'Unknown date';
    }

    const List<String> months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];

    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  String _shortSnippet(Map<String, dynamic> document) {
    final String text =
        document['extracted_text']
            ?.toString()
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim() ??
        '';

    if (text.isEmpty) {
      return 'No extracted text available.';
    }

    if (_query.isNotEmpty) {
      final int index = text.toLowerCase().indexOf(_query);

      if (index >= 0) {
        final int start = index > 55 ? index - 55 : 0;
        final int end = index + _query.length + 90 < text.length
            ? index + _query.length + 90
            : text.length;

        return '${start > 0 ? '...' : ''}'
            '${text.substring(start, end)}'
            '${end < text.length ? '...' : ''}';
      }
    }

    return text.length <= 150 ? text : '${text.substring(0, 150)}...';
  }

  Widget _buildFilterChip(UniversalSearchFilter filter) {
    final bool selected = _selectedFilter == filter;

    return Padding(
      padding: const EdgeInsets.only(right: 9),
      child: ChoiceChip(
        selected: selected,
        label: Text(_filterLabel(filter)),
        onSelected: (_) {
          setState(() {
            _selectedFilter = filter;
          });
        },
        selectedColor: const Color(0xFF766DFF),
        backgroundColor: const Color(0xFF121725),
        side: BorderSide(
          color: selected ? const Color(0xFF766DFF) : const Color(0xFF2B3142),
        ),
        labelStyle: TextStyle(
          color: selected ? Colors.white : const Color(0xFFB4B8C5),
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }

  String _filterLabel(UniversalSearchFilter filter) {
    switch (filter) {
      case UniversalSearchFilter.all:
        return 'All';
      case UniversalSearchFilter.personal:
        return 'Personal';
      case UniversalSearchFilter.organization:
        return 'Organization';
      case UniversalSearchFilter.pdf:
        return 'PDF';
      case UniversalSearchFilter.images:
        return 'Images';
      case UniversalSearchFilter.notes:
        return 'Notes';
      case UniversalSearchFilter.certificates:
        return 'Certificates';
      case UniversalSearchFilter.questionPapers:
        return 'Question Papers';
      case UniversalSearchFilter.assignments:
        return 'Assignments';
    }
  }

  Widget _buildPreview(Map<String, dynamic> document) {
    final String fileName =
        document['file_name']?.toString().toLowerCase() ?? '';

    final String fileUrl = document['file_url']?.toString() ?? '';

    if (_isImage(fileName) && fileUrl.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.network(
          fileUrl,
          width: 68,
          height: 76,
          fit: BoxFit.cover,
          cacheWidth: 240,
          errorBuilder: (_, _, _) {
            return _buildPreviewPlaceholder(fileName);
          },
        ),
      );
    }

    return _buildPreviewPlaceholder(fileName);
  }

  Widget _buildPreviewPlaceholder(String fileName) {
    final IconData icon = _isPdf(fileName)
        ? Icons.picture_as_pdf_rounded
        : _isImage(fileName)
        ? Icons.image_rounded
        : fileName.endsWith('.txt')
        ? Icons.notes_rounded
        : Icons.description_rounded;

    return Container(
      width: 68,
      height: 76,
      decoration: BoxDecoration(
        color: const Color(0xFF24205A),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon, color: const Color(0xFFAAA4FF), size: 30),
    );
  }

  Widget _buildResultCard(Map<String, dynamic> document) {
    final String fileName =
        document['file_name']?.toString() ?? 'Unnamed document';

    final String category = document['category']?.toString() ?? 'Other';

    final String space =
        document['space']?.toString().toLowerCase() ?? 'personal';

    final String date = _formatDate(document['created_at']);

    return InkWell(
      onTap: () => _openDocument(document),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: const Color(0xFF121725),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0xFF292F42)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildPreview(document),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fileName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      height: 1.25,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 7),
                  Wrap(
                    spacing: 7,
                    runSpacing: 6,
                    children: [
                      _buildSmallBadge(category),
                      _buildSmallBadge(
                        space == 'organization' ? 'Organization' : 'Personal',
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _shortSnippet(document),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFADB2BF),
                      fontSize: 11.5,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(
                        Icons.schedule_rounded,
                        color: Color(0xFF777D8E),
                        size: 13,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        date,
                        style: const TextStyle(
                          color: Color(0xFF777D8E),
                          fontSize: 10.5,
                        ),
                      ),
                      const Spacer(),
                      const Text(
                        'Open',
                        style: TextStyle(
                          color: Color(0xFFAAA4FF),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.arrow_forward_ios_rounded,
                        color: Color(0xFFAAA4FF),
                        size: 11,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSmallBadge(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF242A3D),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFFAAA4FF),
          fontSize: 10,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _query.isEmpty
                  ? Icons.manage_search_rounded
                  : Icons.search_off_rounded,
              color: const Color(0xFF766DFF),
              size: 58,
            ),
            const SizedBox(height: 16),
            Text(
              _query.isEmpty
                  ? 'Search your entire Keeper workspace.'
                  : 'No matching knowledge found.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _query.isEmpty
                  ? 'Search by file name, category, subject, document text or identifier.'
                  : 'Try another keyword or change the selected filter.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF8E91A3),
                fontSize: 13,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<Map<String, dynamic>> results = _filteredDocuments;

    return Scaffold(
      backgroundColor: const Color(0xFF090D18),
      appBar: AppBar(
        backgroundColor: const Color(0xFF090D18),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Search Keeper',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          if (_isRefreshing)
            const Padding(
              padding: EdgeInsets.only(right: 18),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Color(0xFFAAA4FF),
                  ),
                ),
              ),
            )
          else
            IconButton(
              tooltip: 'Refresh',
              onPressed: () => _loadDocuments(showLoading: false),
              icon: const Icon(Icons.refresh_rounded),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                autofocus: true,
                style: const TextStyle(color: Colors.white, fontSize: 15),
                decoration: InputDecoration(
                  hintText: 'Search anything in Keeper...',
                  hintStyle: const TextStyle(color: Color(0xFF73798A)),
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    color: Color(0xFFAAA4FF),
                  ),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          onPressed: _searchController.clear,
                          icon: const Icon(
                            Icons.close_rounded,
                            color: Color(0xFF8E91A3),
                          ),
                        ),
                  filled: true,
                  fillColor: const Color(0xFF151B2A),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: const BorderSide(color: Color(0xFF2B3142)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(18),
                    borderSide: const BorderSide(
                      color: Color(0xFF766DFF),
                      width: 1.4,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 13),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue:
                          _availableSubjects.contains(_selectedSubject)
                          ? _selectedSubject
                          : 'All Subjects',
                      isExpanded: true,
                      dropdownColor: const Color(0xFF181D2B),
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      decoration: InputDecoration(
                        labelText: 'Subject',
                        labelStyle: const TextStyle(
                          color: Color(0xFF8E91A3),
                          fontSize: 11,
                        ),
                        filled: true,
                        fillColor: const Color(0xFF121725),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      items: _availableSubjects
                          .map(
                            (subject) => DropdownMenuItem<String>(
                              value: subject,
                              child: Text(
                                subject,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;

                        setState(() {
                          _selectedSubject = value;
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue:
                          const [
                            'Relevance',
                            'Newest',
                            'Oldest',
                            'Name',
                          ].contains(_selectedSort)
                          ? _selectedSort
                          : 'Relevance',
                      isExpanded: true,
                      dropdownColor: const Color(0xFF181D2B),
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      decoration: InputDecoration(
                        labelText: 'Sort',
                        labelStyle: const TextStyle(
                          color: Color(0xFF8E91A3),
                          fontSize: 11,
                        ),
                        filled: true,
                        fillColor: const Color(0xFF121725),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      items: const [
                        DropdownMenuItem<String>(
                          value: 'Relevance',
                          child: Text('Relevance'),
                        ),
                        DropdownMenuItem<String>(
                          value: 'Newest',
                          child: Text('Newest'),
                        ),
                        DropdownMenuItem<String>(
                          value: 'Oldest',
                          child: Text('Oldest'),
                        ),
                        DropdownMenuItem<String>(
                          value: 'Name',
                          child: Text('Name'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;

                        setState(() {
                          _selectedSort = value;
                        });
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 42,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: UniversalSearchFilter.values
                    .map(_buildFilterChip)
                    .toList(),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
              child: Row(
                children: [
                  Text(
                    _query.isEmpty
                        ? '${results.length} documents available'
                        : '${results.length} result${results.length == 1 ? '' : 's'} found',
                    style: const TextStyle(
                      color: Color(0xFF9CA3AF),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Spacer(),
                  if (_query.isNotEmpty)
                    Text(
                      'Sorted by relevance',
                      style: const TextStyle(
                        color: Color(0xFF777D8E),
                        fontSize: 11,
                      ),
                    ),
                ],
              ),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF766DFF),
                      ),
                    )
                  : _errorMessage != null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.error_outline_rounded,
                              color: Color(0xFFEF4444),
                              size: 50,
                            ),
                            const SizedBox(height: 15),
                            Text(
                              _errorMessage!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Color(0xFFB4B8C5),
                                height: 1.45,
                              ),
                            ),
                            const SizedBox(height: 18),
                            ElevatedButton(
                              onPressed: _loadDocuments,
                              child: const Text('Try Again'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : results.isEmpty
                  ? _buildEmptyState()
                  : RefreshIndicator(
                      color: const Color(0xFF766DFF),
                      backgroundColor: const Color(0xFF121725),
                      onRefresh: () => _loadDocuments(showLoading: false),
                      child: ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 6, 16, 28),
                        itemCount: results.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 11),
                        itemBuilder: (context, index) {
                          return _buildResultCard(results[index]);
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
