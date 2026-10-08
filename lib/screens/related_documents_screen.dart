import 'package:flutter/material.dart';

import '../services/related_document_service.dart';
import 'document_viewer_screen.dart';

class RelatedDocumentsScreen extends StatefulWidget {
  final Map<String, dynamic> document;

  const RelatedDocumentsScreen({super.key, required this.document});

  @override
  State<RelatedDocumentsScreen> createState() => _RelatedDocumentsScreenState();
}

class _RelatedDocumentsScreenState extends State<RelatedDocumentsScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  List<Map<String, dynamic>> _documents = [];

  @override
  void initState() {
    super.initState();
    _loadRelated();
  }

  Future<void> _loadRelated() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final List<Map<String, dynamic>> documents =
          await RelatedDocumentService.findRelated(document: widget.document);

      if (!mounted) return;

      setState(() {
        _documents = documents;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _errorMessage = 'Unable to load related documents.';
      });
    }
  }

  void _openDocument(Map<String, dynamic> document) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DocumentViewerScreen(
          fileName: document['file_name']?.toString() ?? 'Document',
          fileUrl: document['file_url']?.toString() ?? '',
          extractedText: document['extracted_text']?.toString() ?? '',
        ),
      ),
    );
  }

  IconData _iconFor(String fileName) {
    final String value = fileName.toLowerCase();

    if (value.endsWith('.pdf')) {
      return Icons.picture_as_pdf_rounded;
    }

    if (value.endsWith('.jpg') ||
        value.endsWith('.jpeg') ||
        value.endsWith('.png') ||
        value.endsWith('.webp')) {
      return Icons.image_rounded;
    }

    if (value.endsWith('.doc') || value.endsWith('.docx')) {
      return Icons.description_rounded;
    }

    return Icons.insert_drive_file_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final String currentName =
        widget.document['file_name']?.toString() ?? 'Document';

    return Scaffold(
      backgroundColor: const Color(0xFF090D18),
      appBar: AppBar(
        backgroundColor: const Color(0xFF090D18),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Related Documents',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _loadRelated,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF766DFF)),
            )
          : _errorMessage != null
          ? Center(
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: Color(0xFF9CA3AF)),
              ),
            )
          : SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(
                        color: const Color(0xFF151B2A),
                        borderRadius: BorderRadius.circular(17),
                        border: Border.all(color: const Color(0xFF2B3142)),
                      ),
                      child: Text(
                        'Related to: $currentName',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: _documents.isEmpty
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(28),
                              child: Text(
                                'No related documents found yet.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Color(0xFF9CA3AF)),
                              ),
                            ),
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
                            itemCount: _documents.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final document = _documents[index];
                              final String name =
                                  document['file_name']?.toString() ??
                                  'Unnamed document';
                              final String category =
                                  document['category']?.toString() ?? 'Other';
                              final String subject =
                                  document['detected_subject']?.toString() ??
                                  '';

                              return Material(
                                color: const Color(0xFF121725),
                                borderRadius: BorderRadius.circular(18),
                                child: InkWell(
                                  onTap: () => _openDocument(document),
                                  borderRadius: BorderRadius.circular(18),
                                  child: Container(
                                    padding: const EdgeInsets.all(15),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(18),
                                      border: Border.all(
                                        color: const Color(0xFF292F42),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 48,
                                          height: 48,
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF24205A),
                                            borderRadius: BorderRadius.circular(
                                              14,
                                            ),
                                          ),
                                          child: Icon(
                                            _iconFor(name),
                                            color: const Color(0xFFAAA4FF),
                                          ),
                                        ),
                                        const SizedBox(width: 13),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                name,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                              const SizedBox(height: 5),
                                              Text(
                                                subject.isEmpty
                                                    ? category
                                                    : '$subject • $category',
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  color: Color(0xFF9CA3AF),
                                                  fontSize: 11.5,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const Icon(
                                          Icons.chevron_right_rounded,
                                          color: Color(0xFF777D8E),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
    );
  }
}
