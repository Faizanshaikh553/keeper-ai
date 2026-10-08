import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

class DocumentViewerScreen extends StatefulWidget {
  final String fileName;
  final String fileUrl;
  final String extractedText;

  const DocumentViewerScreen({
    super.key,
    required this.fileName,
    required this.fileUrl,
    this.extractedText = '',
  });

  @override
  State<DocumentViewerScreen> createState() => _DocumentViewerScreenState();
}

class _DocumentViewerScreenState extends State<DocumentViewerScreen> {
  final PdfViewerController _pdfController = PdfViewerController();
  final TextEditingController _textSearchController = TextEditingController();

  PdfTextSearchResult? _pdfSearchResult;
  bool _showPdfSearch = false;
  bool _showTextSearch = false;
  String _textQuery = '';

  String get _lowerFileName => widget.fileName.toLowerCase();

  bool get _isImage =>
      _lowerFileName.endsWith('.jpg') ||
      _lowerFileName.endsWith('.jpeg') ||
      _lowerFileName.endsWith('.png') ||
      _lowerFileName.endsWith('.webp');

  bool get _isPdf => _lowerFileName.endsWith('.pdf');

  bool get _isTextDocument =>
      _lowerFileName.endsWith('.txt') ||
      _lowerFileName.endsWith('.doc') ||
      _lowerFileName.endsWith('.docx');

  @override
  void dispose() {
    _pdfController.dispose();
    _textSearchController.dispose();
    _pdfSearchResult?.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _searchPdf(String query) async {
    final String cleanedQuery = query.trim();

    _pdfSearchResult?.dispose();
    _pdfSearchResult = null;

    if (cleanedQuery.isEmpty) {
      setState(() {});
      return;
    }

    final PdfTextSearchResult result = _pdfController.searchText(cleanedQuery);

    setState(() {
      _pdfSearchResult = result;
    });
  }

  Widget _buildImageViewer() {
    if (widget.fileUrl.trim().isEmpty) {
      return _buildMissingFileState('Image URL is missing.');
    }

    return Container(
      color: Colors.black,
      alignment: Alignment.center,
      child: InteractiveViewer(
        minScale: 0.7,
        maxScale: 5,
        boundaryMargin: const EdgeInsets.all(120),
        child: Image.network(
          widget.fileUrl,
          fit: BoxFit.contain,
          loadingBuilder: (context, child, progress) {
            if (progress == null) {
              return child;
            }

            return const Center(
              child: CircularProgressIndicator(color: Color(0xFF766DFF)),
            );
          },
          errorBuilder: (_, _, _) {
            return _buildMissingFileState(
              'Unable to load this image.',
              showExternalButton: false,
            );
          },
        ),
      ),
    );
  }

  Widget _buildPdfViewer() {
    if (widget.fileUrl.trim().isEmpty) {
      return _buildMissingFileState('PDF URL is missing.');
    }

    return Column(
      children: [
        if (_showPdfSearch)
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            color: const Color(0xFF111725),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _textSearchController,
                    autofocus: true,
                    style: const TextStyle(color: Colors.white),
                    textInputAction: TextInputAction.search,
                    onSubmitted: _searchPdf,
                    decoration: InputDecoration(
                      hintText: 'Search inside PDF',
                      hintStyle: const TextStyle(color: Color(0xFF777D8E)),
                      filled: true,
                      fillColor: const Color(0xFF1A2030),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: () => _searchPdf(_textSearchController.text),
                  icon: const Icon(
                    Icons.search_rounded,
                    color: Color(0xFFAAA4FF),
                  ),
                ),
                if (_pdfSearchResult != null &&
                    _pdfSearchResult!.totalInstanceCount > 0) ...[
                  IconButton(
                    onPressed: _pdfSearchResult!.previousInstance,
                    icon: const Icon(
                      Icons.keyboard_arrow_up_rounded,
                      color: Colors.white,
                    ),
                  ),
                  IconButton(
                    onPressed: _pdfSearchResult!.nextInstance,
                    icon: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: Colors.white,
                    ),
                  ),
                ],
              ],
            ),
          ),
        Expanded(
          child: SfPdfViewer.network(
            widget.fileUrl,
            controller: _pdfController,
            canShowScrollHead: true,
            canShowScrollStatus: true,
            enableDoubleTapZooming: true,
            enableTextSelection: true,
            onDocumentLoadFailed: (_) {
              _showMessage('Unable to load this PDF.');
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTextViewer() {
    final String text = widget.extractedText.trim();

    if (text.isEmpty) {
      return _buildMissingFileState(
        'Readable text is not available for this document yet.',
        showExternalButton: false,
      );
    }

    final List<TextSpan> spans = _highlightMatches(
      text: text,
      query: _textQuery,
    );

    return Column(
      children: [
        if (_showTextSearch)
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            color: const Color(0xFF111725),
            child: TextField(
              controller: _textSearchController,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              onChanged: (value) {
                setState(() {
                  _textQuery = value.trim();
                });
              },
              decoration: InputDecoration(
                hintText: 'Search inside document',
                hintStyle: const TextStyle(color: Color(0xFF777D8E)),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: Color(0xFFAAA4FF),
                ),
                filled: true,
                fillColor: const Color(0xFF1A2030),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 40),
            child: SelectableText.rich(
              TextSpan(children: spans),
              style: const TextStyle(
                color: Color(0xFFE5E7EB),
                fontSize: 15,
                height: 1.65,
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<TextSpan> _highlightMatches({
    required String text,
    required String query,
  }) {
    if (query.isEmpty) {
      return [TextSpan(text: text)];
    }

    final String lowerText = text.toLowerCase();
    final String lowerQuery = query.toLowerCase();
    final List<TextSpan> spans = [];

    int start = 0;

    while (true) {
      final int index = lowerText.indexOf(lowerQuery, start);

      if (index == -1) {
        spans.add(TextSpan(text: text.substring(start)));
        break;
      }

      if (index > start) {
        spans.add(TextSpan(text: text.substring(start, index)));
      }

      spans.add(
        TextSpan(
          text: text.substring(index, index + query.length),
          style: const TextStyle(
            backgroundColor: Color(0xFF5A4FCF),
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      );

      start = index + query.length;
    }

    return spans;
  }

  Widget _buildMissingFileState(
    String message, {
    bool showExternalButton = false,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.description_outlined,
              color: Color(0xFFAAA4FF),
              size: 52,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFFB7BBC7),
                fontSize: 14,
                height: 1.45,
              ),
            ),
            if (showExternalButton) ...[
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: null,
                icon: Icon(Icons.lock_outline_rounded),
                label: Text('Keeper preview only'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildUnsupportedViewer() {
    return _buildMissingFileState(
      'Preview is not available for this file type yet.',
      showExternalButton: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool canSearch = _isPdf || _isTextDocument;

    return Scaffold(
      backgroundColor: const Color(0xFF090D18),
      appBar: AppBar(
        backgroundColor: const Color(0xFF090D18),
        foregroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 0,
        title: Text(
          widget.fileName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
        actions: [
          if (canSearch)
            IconButton(
              tooltip: 'Search',
              onPressed: () {
                setState(() {
                  if (_isPdf) {
                    _showPdfSearch = !_showPdfSearch;
                  } else {
                    _showTextSearch = !_showTextSearch;
                  }
                });
              },
              icon: const Icon(Icons.search_rounded),
            ),
        ],
      ),
      body: _isImage
          ? _buildImageViewer()
          : _isPdf
          ? _buildPdfViewer()
          : _isTextDocument
          ? _buildTextViewer()
          : _buildUnsupportedViewer(),
    );
  }
}
