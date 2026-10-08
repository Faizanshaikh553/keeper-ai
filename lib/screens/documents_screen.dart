import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import 'package:url_launcher/url_launcher.dart';

import '../services/organization_permission_service.dart';
import 'document_viewer_screen.dart';
import 'related_documents_screen.dart';

class DocumentsScreen extends StatefulWidget {
  final int initialTabIndex;

  const DocumentsScreen({super.key, this.initialTabIndex = 0});

  @override
  State<DocumentsScreen> createState() => _DocumentsScreenState();
}

class _DocumentsScreenState extends State<DocumentsScreen>
    with SingleTickerProviderStateMixin {
  static List<Map<String, dynamic>> _cachedPersonalDocuments = [];
  static List<Map<String, dynamic>> _cachedOrganizationDocuments = [];
  late final TabController _tabController;

  final TextEditingController _searchController = TextEditingController();

  bool _isLoading =
      _cachedPersonalDocuments.isEmpty && _cachedOrganizationDocuments.isEmpty;
  bool _isDeleting = false;
  bool _isPreparingFile = false;
  OrganizationAccess? _organizationAccess;
  String? _errorMessage;
  String _searchQuery = '';

  List<Map<String, dynamic>> _personalDocuments =
      List<Map<String, dynamic>>.from(_cachedPersonalDocuments);
  List<Map<String, dynamic>> _organizationDocuments =
      List<Map<String, dynamic>>.from(_cachedOrganizationDocuments);

  @override
  void initState() {
    super.initState();

    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTabIndex < 0
          ? 0
          : widget.initialTabIndex > 1
          ? 1
          : widget.initialTabIndex,
    );

    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });

    _loadDocuments();
    _loadOrganizationAccess();
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

  Future<String?> _loadUserOrganizationId(String userId) async {
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

      final dynamic organizationValue =
          data['organization_id'] ??
          data['organizationId'] ??
          data['current_organization_id'] ??
          data['currentOrganizationId'];

      final String organizationId = organizationValue?.toString().trim() ?? '';

      return organizationId.isEmpty ? null : organizationId;
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadOrganizationAccess() async {
    try {
      final OrganizationAccess access =
          await OrganizationPermissionService.loadCurrentUserAccess();

      if (!mounted) return;

      setState(() {
        _organizationAccess = access;
      });
    } catch (_) {
      // Personal document actions still work even if organization access fails.
    }
  }

  bool _canDeleteDocument(Map<String, dynamic> document) {
    final String currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';

    final String uploaderId = document['user_id']?.toString() ?? '';

    final String space = document['space']?.toString() ?? 'personal';

    if (space != 'organization') {
      return uploaderId.isNotEmpty && uploaderId == currentUserId;
    }

    final OrganizationAccess? access = _organizationAccess;

    if (access == null) {
      return uploaderId.isNotEmpty && uploaderId == currentUserId;
    }

    return access.canDeleteDocument(uploaderId, currentUserId);
  }

  bool _canEditDocument(Map<String, dynamic> document) {
    final String currentUserId = FirebaseAuth.instance.currentUser?.uid ?? '';

    final String uploaderId = document['user_id']?.toString() ?? '';

    final String space = document['space']?.toString() ?? 'personal';

    if (space != 'organization') {
      return uploaderId.isNotEmpty && uploaderId == currentUserId;
    }

    final OrganizationAccess? access = _organizationAccess;

    if (access == null) {
      return uploaderId.isNotEmpty && uploaderId == currentUserId;
    }

    return access.canEditDocument(uploaderId, currentUserId);
  }

  Future<void> _loadDocuments() async {
    final User? user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _errorMessage = 'Please sign in again.';
      });
      return;
    }

    final bool hasCachedDocuments =
        _personalDocuments.isNotEmpty || _organizationDocuments.isNotEmpty;

    if (!hasCachedDocuments && mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    } else if (mounted) {
      setState(() {
        _errorMessage = null;
      });
    }

    try {
      final supabase.SupabaseClient client = supabase.Supabase.instance.client;
      final String? organizationId = await _loadUserOrganizationId(user.uid);

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

      _cachedPersonalDocuments = personalDocuments;
      _cachedOrganizationDocuments = organizationDocuments;

      if (!mounted) return;

      setState(() {
        _personalDocuments = personalDocuments;
        _organizationDocuments = organizationDocuments;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;

        if (_personalDocuments.isEmpty && _organizationDocuments.isEmpty) {
          _errorMessage = 'Unable to load documents: $error';
        }
      });

      if (_personalDocuments.isNotEmpty || _organizationDocuments.isNotEmpty) {
        _showMessage('Could not refresh documents. Showing saved results.');
      }
    }
  }

  List<Map<String, dynamic>> _filterDocuments(
    List<Map<String, dynamic>> documents,
  ) {
    if (_searchQuery.isEmpty) {
      return documents;
    }

    return documents.where((document) {
      final String fileName =
          document['file_name']?.toString().toLowerCase() ?? '';

      final String category =
          document['category']?.toString().toLowerCase() ?? '';

      final String visibility =
          document['visibility']?.toString().toLowerCase() ?? '';

      return fileName.contains(_searchQuery) ||
          category.contains(_searchQuery) ||
          visibility.contains(_searchQuery);
    }).toList();
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

  String? _extractStoragePath(String publicUrl) {
    const String marker = '/storage/v1/object/public/Keeper-documents/';

    final int markerIndex = publicUrl.indexOf(marker);

    if (markerIndex == -1) {
      return null;
    }

    final String encodedPath = publicUrl.substring(markerIndex + marker.length);

    return Uri.decodeFull(encodedPath);
  }

  Future<void> _editDocumentDetails(Map<String, dynamic> document) async {
    if (!_canEditDocument(document)) {
      _showMessage('You do not have permission to edit this document.');
      return;
    }

    final String documentId = document['id']?.toString() ?? '';

    if (documentId.isEmpty) {
      _showMessage('Document ID is missing.');
      return;
    }

    final TextEditingController nameController = TextEditingController(
      text: document['file_name']?.toString() ?? '',
    );

    final List<String> categories = [
      'Certificate',
      'Resume',
      'Marksheet',
      'Personal Notes',
      'Bill',
      'Notice',
      'Exam Timetable',
      'Syllabus',
      'Previous Year Paper',
      'Assignment',
      'Lab Manual',
      'Internship',
      'Project',
      'Study Material',
      'WhatsApp Chat',
      'Voice Notes',
      'Other',
    ];

    String selectedCategory = document['category']?.toString() ?? 'Other';

    if (!categories.contains(selectedCategory)) {
      categories.insert(0, selectedCategory);
    }

    final Map<String, String>?
    result = await showModalBottomSheet<Map<String, String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF121725),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return SafeArea(
              top: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  18,
                  12,
                  18,
                  22 + MediaQuery.viewInsetsOf(context).bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 42,
                        height: 4,
                        decoration: BoxDecoration(
                          color: const Color(0xFF3A4052),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Edit Document',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: nameController,
                      autofocus: true,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Document name',
                        labelStyle: const TextStyle(color: Color(0xFF9CA3AF)),
                        filled: true,
                        fillColor: const Color(0xFF1A2030),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      initialValue: selectedCategory,
                      dropdownColor: const Color(0xFF1A2030),
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        labelText: 'Category',
                        labelStyle: const TextStyle(color: Color(0xFF9CA3AF)),
                        filled: true,
                        fillColor: const Color(0xFF1A2030),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      items: categories
                          .map(
                            (category) => DropdownMenuItem<String>(
                              value: category,
                              child: Text(category),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;

                        setSheetState(() {
                          selectedCategory = value;
                        });
                      },
                    ),
                    const SizedBox(height: 18),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: () {
                          final String newName = nameController.text.trim();

                          if (newName.isEmpty) return;

                          Navigator.pop(sheetContext, {
                            'file_name': newName,
                            'category': selectedCategory,
                          });
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF766DFF),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text(
                          'Save Changes',
                          style: TextStyle(fontWeight: FontWeight.w800),
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
    );

    nameController.dispose();

    if (result == null) return;

    try {
      await supabase.Supabase.instance.client
          .from('documents')
          .update({
            'file_name': result['file_name'],
            'category': result['category'],
          })
          .eq('id', documentId);

      document['file_name'] = result['file_name'];
      document['category'] = result['category'];

      _cachedPersonalDocuments = _personalDocuments;
      _cachedOrganizationDocuments = _organizationDocuments;

      if (mounted) {
        setState(() {});
      }

      _showMessage('Document updated successfully.');
    } catch (error) {
      final String message = error.toString().toLowerCase();

      if (message.contains('permission') ||
          message.contains('row-level security') ||
          message.contains('unauthorized')) {
        _showMessage('Edit permission denied. Check Supabase policies.');
      } else {
        _showMessage('Unable to update document.');
      }
    }
  }

  String _safeFileName(String fileName) {
    return fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_').trim();
  }

  Future<File> _downloadToTemporaryFile(Map<String, dynamic> document) async {
    final String fileUrl = document['file_url']?.toString() ?? '';
    final String fileName =
        document['file_name']?.toString() ?? 'keeper_document';

    if (fileUrl.isEmpty) {
      throw Exception('missing-file-url');
    }

    final Uri? uri = Uri.tryParse(fileUrl);

    if (uri == null) {
      throw Exception('invalid-file-url');
    }

    final Directory temporaryDirectory = await getTemporaryDirectory();

    final File outputFile = File(
      '${temporaryDirectory.path}/${_safeFileName(fileName)}',
    );

    final HttpClient client = HttpClient();

    try {
      final HttpClientRequest request = await client.getUrl(uri);
      final HttpClientResponse response = await request.close();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('download-failed-${response.statusCode}');
      }

      final IOSink sink = outputFile.openWrite();
      await response.pipe(sink);

      return outputFile;
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _shareDocument(Map<String, dynamic> document) async {
    if (_isPreparingFile) return;

    setState(() {
      _isPreparingFile = true;
    });

    try {
      final File file = await _downloadToTemporaryFile(document);

      final String fileName =
          document['file_name']?.toString() ?? 'Keeper document';

      await SharePlus.instance.share(
        ShareParams(
          text: 'Shared from Keeper',
          files: [XFile(file.path)],
          subject: fileName,
        ),
      );
    } catch (_) {
      _showMessage('Unable to share this document.');
    } finally {
      if (mounted) {
        setState(() {
          _isPreparingFile = false;
        });
      }
    }
  }

  Future<void> _downloadDocument(Map<String, dynamic> document) async {
    final String fileUrl = document['file_url']?.toString() ?? '';

    if (fileUrl.isEmpty) {
      _showMessage('Document URL is missing.');
      return;
    }

    final Uri? uri = Uri.tryParse(fileUrl);

    if (uri == null) {
      _showMessage('Document link is invalid.');
      return;
    }

    final bool opened = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );

    if (!opened) {
      _showMessage('Unable to open download link.');
    }
  }

  Future<void> _confirmDelete(Map<String, dynamic> document) async {
    final User? currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      _showMessage('Please sign in again.');
      return;
    }

    if (!_canDeleteDocument(document)) {
      _showMessage('You do not have permission to delete this document.');
      return;
    }

    final String fileName =
        document['file_name']?.toString() ?? 'this document';

    final bool? shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF121725),
          title: const Text(
            'Delete Document?',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
          ),
          content: Text(
            'Are you sure you want to permanently delete "$fileName"?',
            style: const TextStyle(color: Color(0xFFB0B3C0), height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext, false);
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext, true);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
                foregroundColor: Colors.white,
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (shouldDelete == true) {
      await _deleteDocument(document);
    }
  }

  Future<void> _deleteDocument(Map<String, dynamic> document) async {
    if (_isDeleting) return;

    final String documentId = document['id']?.toString() ?? '';

    final String fileUrl = document['file_url']?.toString() ?? '';

    if (documentId.isEmpty) {
      _showMessage('Document ID is missing.');
      return;
    }

    setState(() {
      _isDeleting = true;
    });

    try {
      final supabase.SupabaseClient client = supabase.Supabase.instance.client;

      final String? storagePath = _extractStoragePath(fileUrl);

      if (storagePath != null && storagePath.isNotEmpty) {
        await client.storage.from('Keeper-documents').remove([storagePath]);
      }

      await client.from('documents').delete().eq('id', documentId);

      if (!mounted) return;

      _showMessage('Document deleted successfully.');

      await _loadDocuments();
    } catch (error) {
      if (!mounted) return;

      final String errorText = error.toString().toLowerCase();

      if (errorText.contains('permission') ||
          errorText.contains('row-level security') ||
          errorText.contains('unauthorized')) {
        _showMessage('Delete permission denied. Check Supabase policies.');
      } else {
        _showMessage('Unable to delete document: $error');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDeleting = false;
        });
      }
    }
  }

  String _formatDate(dynamic value) {
    if (value == null) {
      return 'Unknown date';
    }

    final DateTime? date = DateTime.tryParse(value.toString())?.toLocal();

    if (date == null) {
      return 'Unknown date';
    }

    final String day = date.day.toString().padLeft(2, '0');

    final String month = date.month.toString().padLeft(2, '0');

    return '$day/$month/${date.year}';
  }

  bool _isImageDocument(String fileName) {
    final String lowerName = fileName.toLowerCase();

    return lowerName.endsWith('.jpg') ||
        lowerName.endsWith('.jpeg') ||
        lowerName.endsWith('.png') ||
        lowerName.endsWith('.webp');
  }

  Widget _buildDocumentPreview({
    required String fileName,
    required String fileUrl,
  }) {
    if (_isImageDocument(fileName) && fileUrl.trim().isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.network(
          fileUrl,
          width: 58,
          height: 58,
          fit: BoxFit.cover,
          cacheWidth: 220,
          errorBuilder: (_, _, _) {
            return _buildDocumentIconPreview(fileName);
          },
        ),
      );
    }

    return _buildDocumentIconPreview(fileName);
  }

  Widget _buildDocumentIconPreview(String fileName) {
    return Container(
      width: 58,
      height: 58,
      decoration: BoxDecoration(
        color: const Color(0xFF24205A),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(_documentIcon(fileName), color: const Color(0xFFAAA4FF)),
    );
  }

  IconData _documentIcon(String fileName) {
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

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 0),
      child: TextField(
        controller: _searchController,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: 'Search documents or category...',
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

  Widget _buildDocumentList(
    List<Map<String, dynamic>> originalDocuments,
    String emptyMessage,
  ) {
    if (_isLoading && originalDocuments.isEmpty) {
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
                size: 46,
              ),
              const SizedBox(height: 14),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
              ),
              const SizedBox(height: 18),
              ElevatedButton(
                onPressed: _loadDocuments,
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

    return Column(
      children: [
        _buildSearchBar(),
        Expanded(
          child: documents.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _searchQuery.isEmpty
                              ? Icons.folder_open_rounded
                              : Icons.search_off_rounded,
                          color: const Color(0xFF766DFF),
                          size: 54,
                        ),
                        const SizedBox(height: 15),
                        Text(
                          _searchQuery.isEmpty
                              ? emptyMessage
                              : 'No matching document found.',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFF9CA3AF),
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  color: const Color(0xFF766DFF),
                  backgroundColor: const Color(0xFF121725),
                  onRefresh: _loadDocuments,
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(18, 18, 18, 30),
                    itemCount: documents.length,
                    separatorBuilder: (context, index) {
                      return const SizedBox(height: 12);
                    },
                    itemBuilder: (context, index) {
                      final Map<String, dynamic> document = documents[index];

                      final String fileName =
                          document['file_name']?.toString() ??
                          'Unnamed document';

                      final String fileUrl =
                          document['file_url']?.toString() ?? '';

                      final String category =
                          document['category']?.toString() ?? 'Other';

                      final String visibility =
                          document['visibility']?.toString() ?? '';

                      final String date = _formatDate(document['created_at']);

                      final bool canEdit = _canEditDocument(document);

                      final bool canDelete = _canDeleteDocument(document);

                      return Container(
                        padding: const EdgeInsets.all(15),
                        decoration: BoxDecoration(
                          color: const Color(0xFF121725),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: const Color(0xFF292F42)),
                        ),
                        child: Row(
                          children: [
                            GestureDetector(
                              onTap: () {
                                _openDocument(document);
                              },
                              child: _buildDocumentPreview(
                                fileName: fileName,
                                fileUrl: fileUrl,
                              ),
                            ),
                            const SizedBox(width: 13),
                            Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  _openDocument(document);
                                },
                                behavior: HitTestBehavior.opaque,
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
                                    const SizedBox(height: 6),
                                    Text(
                                      '$category • $date',
                                      style: const TextStyle(
                                        color: Color(0xFF8E91A3),
                                        fontSize: 12,
                                      ),
                                    ),
                                    if (visibility.isNotEmpty) ...[
                                      const SizedBox(height: 5),
                                      Text(
                                        visibility == 'private'
                                            ? 'Private'
                                            : visibility == 'admin'
                                            ? 'Admin only'
                                            : 'Organization members',
                                        style: const TextStyle(
                                          color: Color(0xFF938CFF),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                            PopupMenuButton<String>(
                              color: const Color(0xFF181D2B),
                              icon: const Icon(
                                Icons.more_vert_rounded,
                                color: Color(0xFF8E91A3),
                              ),
                              onSelected: (value) {
                                if (value == 'open') {
                                  _openDocument(document);
                                } else if (value == 'related') {
                                  Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => RelatedDocumentsScreen(
                                        document: document,
                                      ),
                                    ),
                                  );
                                } else if (value == 'download') {
                                  _downloadDocument(document);
                                } else if (value == 'share') {
                                  _shareDocument(document);
                                } else if (value == 'edit') {
                                  _editDocumentDetails(document);
                                } else if (value == 'delete') {
                                  _confirmDelete(document);
                                }
                              },
                              itemBuilder: (context) {
                                return [
                                  const PopupMenuItem<String>(
                                    value: 'open',
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.visibility_outlined,
                                          color: Color(0xFFAAA4FF),
                                        ),
                                        SizedBox(width: 11),
                                        Text(
                                          'View',
                                          style: TextStyle(color: Colors.white),
                                        ),
                                      ],
                                    ),
                                  ),

                                  const PopupMenuItem<String>(
                                    value: 'related',
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.auto_awesome_motion_rounded,
                                          color: Color(0xFFAAA4FF),
                                        ),
                                        SizedBox(width: 11),
                                        Text(
                                          'Related Documents',
                                          style: TextStyle(color: Colors.white),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem<String>(
                                    value: 'download',
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.download_rounded,
                                          color: Color(0xFFAAA4FF),
                                        ),
                                        SizedBox(width: 11),
                                        Text(
                                          'Download',
                                          style: TextStyle(color: Colors.white),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem<String>(
                                    value: 'share',
                                    child: Row(
                                      children: [
                                        Icon(
                                          Icons.share_outlined,
                                          color: Color(0xFFAAA4FF),
                                        ),
                                        SizedBox(width: 11),
                                        Text(
                                          'Share',
                                          style: TextStyle(color: Colors.white),
                                        ),
                                      ],
                                    ),
                                  ),

                                  if (canEdit)
                                    const PopupMenuItem<String>(
                                      value: 'edit',
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.edit_outlined,
                                            color: Color(0xFFAAA4FF),
                                          ),
                                          SizedBox(width: 11),
                                          Text(
                                            'Rename / Category',
                                            style: TextStyle(
                                              color: Colors.white,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),

                                  if (canDelete)
                                    const PopupMenuItem<String>(
                                      value: 'delete',
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.delete_outline_rounded,
                                            color: Color(0xFFEF4444),
                                          ),
                                          SizedBox(width: 11),
                                          Text(
                                            'Delete',
                                            style: TextStyle(
                                              color: Color(0xFFEF4444),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ];
                              },
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          backgroundColor: const Color(0xFF090D18),
          appBar: AppBar(
            backgroundColor: const Color(0xFF090D18),
            elevation: 0,
            iconTheme: const IconThemeData(color: Colors.white),
            title: const Text(
              'Documents',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
            actions: [
              IconButton(
                onPressed: _isLoading
                    ? null
                    : () async {
                        await Future.wait([
                          _loadDocuments(),
                          _loadOrganizationAccess(),
                        ]);
                      },
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
              _buildDocumentList(
                _personalDocuments,
                'Your personal documents will appear here.',
              ),
              _buildDocumentList(
                _organizationDocuments,
                'Organization documents will appear here.',
              ),
            ],
          ),
        ),
        if (_isPreparingFile)
          Container(
            color: Colors.black54,
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Color(0xFF766DFF)),
                  SizedBox(height: 14),
                  Text(
                    'Preparing document...',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        if (_isDeleting)
          Container(
            color: Colors.black38,
            child: const Center(
              child: SizedBox(
                width: 44,
                height: 44,
                child: CircularProgressIndicator(
                  strokeWidth: 3.2,
                  color: Color(0xFF766DFF),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
