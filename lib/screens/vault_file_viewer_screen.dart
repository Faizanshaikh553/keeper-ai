import 'dart:io';

import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import '../models/vault_document_model.dart';
import '../services/vault_storage_service.dart';
import '../services/vault_file_action_service.dart';

class VaultFileViewerScreen extends StatefulWidget {
  final VaultDocumentModel document;

  const VaultFileViewerScreen({super.key, required this.document});

  @override
  State<VaultFileViewerScreen> createState() => _VaultFileViewerScreenState();
}

class _VaultFileViewerScreenState extends State<VaultFileViewerScreen> {
  File? _temporaryFile;
  bool _isLoading = true;
  String? _error;
  bool _isActionRunning = false;

  @override
  void initState() {
    super.initState();
    _prepareFile();
  }

  @override
  void dispose() {
    final File? file = _temporaryFile;
    if (file != null && file.existsSync()) {
      try {
        file.deleteSync();
      } catch (_) {}
    }
    super.dispose();
  }

  Future<void> _prepareFile() async {
    try {
      final File file = await VaultStorageService.instance
          .decryptToTemporaryFile(widget.document);

      if (!mounted) return;

      setState(() {
        _temporaryFile = file;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _error = 'Unable to open this secure file.';
        _isLoading = false;
      });
    }
  }

  Future<void> _shareFile() async {
    if (_isActionRunning) return;

    setState(() {
      _isActionRunning = true;
    });

    try {
      await VaultFileActionService.instance.share(widget.document);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(content: Text('Unable to share this secure file.')),
          );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isActionRunning = false;
        });
      }
    }
  }

  Future<void> _printFile() async {
    if (_isActionRunning) return;

    setState(() {
      _isActionRunning = true;
    });

    try {
      final bool started =
          await VaultFileActionService.instance.print(widget.document);

      if (!started && mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text(
                'Printing is not available for this file type on this device.',
              ),
            ),
          );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(content: Text('Unable to print this secure file.')),
          );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isActionRunning = false;
        });
      }
    }
  }

  bool get _isImage {
    final String type = widget.document.fileType.toLowerCase();
    return ['jpg', 'jpeg', 'png', 'webp', 'heic'].contains(type);
  }

  bool get _isPdf => widget.document.fileType.toLowerCase() == 'pdf';

  bool get _isText {
    final String type = widget.document.fileType.toLowerCase();
    return ['txt', 'md', 'csv', 'json'].contains(type);
  }

  Future<String> _readText() async {
    final File? file = _temporaryFile;
    if (file == null) return '';

    try {
      return await file.readAsString();
    } catch (_) {
      return '';
    }
  }

  Widget _buildViewer() {
    final File? file = _temporaryFile;

    if (file == null) {
      return const Center(
        child: Text(
          'File is unavailable.',
          style: TextStyle(color: Color(0xFF9CA3AF)),
        ),
      );
    }

    if (_isImage) {
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: InteractiveViewer(
          minScale: 0.8,
          maxScale: 5,
          child: Image.file(file, fit: BoxFit.contain),
        ),
      );
    }

    if (_isPdf) {
      return SfPdfViewer.file(
        file,
        enableDoubleTapZooming: true,
        enableTextSelection: true,
      );
    }

    if (_isText) {
      return FutureBuilder<String>(
        future: _readText(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFF766DFF)),
            );
          }

          final String text = snapshot.data ?? '';

          if (text.isEmpty) {
            return const Center(
              child: Text(
                'Text preview is unavailable.',
                style: TextStyle(color: Color(0xFF9CA3AF)),
              ),
            );
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(18),
            child: SelectableText(
              text,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                height: 1.55,
              ),
            ),
          );
        },
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.insert_drive_file_rounded,
              color: Color(0xFFAAA4FF),
              size: 58,
            ),
            const SizedBox(height: 14),
            Text(
              widget.document.fileName,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'This file is securely stored. In-app preview is currently available for images, PDFs and text files.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFF9CA3AF), height: 1.45),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF090D18),
      appBar: AppBar(
        backgroundColor: const Color(0xFF090D18),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          widget.document.fileName,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: 'Share',
            onPressed: _isActionRunning ? null : _shareFile,
            icon: const Icon(Icons.share_outlined),
          ),
          IconButton(
            tooltip: 'Print',
            onPressed: _isActionRunning ? null : _printFile,
            icon: const Icon(Icons.print_outlined),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFF766DFF)),
            )
          : _error != null
          ? Center(
              child: Text(
                _error!,
                style: const TextStyle(color: Color(0xFFFF7D92)),
              ),
            )
          : _buildViewer(),
    );
  }
}
