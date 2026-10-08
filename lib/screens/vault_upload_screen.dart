import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/vault_storage_service.dart';

class VaultUploadScreen extends StatefulWidget {
  const VaultUploadScreen({super.key});

  @override
  State<VaultUploadScreen> createState() => _VaultUploadScreenState();
}

class _VaultUploadScreenState extends State<VaultUploadScreen> {
  final List<PlatformFile> _selectedFiles = [];

  bool _isSaving = false;
  int _completed = 0;

  String _autoCategory(PlatformFile file) {
    final String name = file.name.toLowerCase();
    final String extension = (file.extension ?? name.split('.').last)
        .toLowerCase();

    if (name.contains('aadhaar') || name.contains('aadhar')) {
      return 'Aadhaar';
    }
    if (name.contains('pan')) return 'PAN Card';
    if (name.contains('passport')) return 'Passport';
    if (name.contains('license') || name.contains('licence')) {
      return 'Driving License';
    }
    if (name.contains('marksheet') || name.contains('result')) {
      return 'Marksheets';
    }
    if (name.contains('certificate')) return 'Certificates';
    if (name.contains('resume') || name.contains('cv')) {
      return 'Resume';
    }
    if (name.contains('bank') || name.contains('statement')) {
      return 'Bank Documents';
    }
    if (name.contains('medical') || name.contains('report')) {
      return 'Medical Records';
    }

    if (['jpg', 'jpeg', 'png', 'webp', 'heic'].contains(extension)) {
      return 'Images';
    }
    if (extension == 'pdf') return 'PDFs';
    if (['mp3', 'wav', 'm4a', 'aac', 'ogg'].contains(extension)) {
      return 'Audio Files';
    }

    return 'Personal Files';
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pickFiles() async {
    if (_isSaving) return;

    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.any,
        withData: false,
      );

      if (result == null) return;

      final List<PlatformFile> available = result.files
          .where(
            (file) =>
                file.path != null && file.path!.isNotEmpty && file.size > 0,
          )
          .toList();

      if (!mounted) return;

      setState(() {
        for (final PlatformFile file in available) {
          final bool exists = _selectedFiles.any(
            (selected) =>
                selected.path == file.path && selected.size == file.size,
          );

          if (!exists) {
            _selectedFiles.add(file);
          }
        }
      });
    } catch (_) {
      _showMessage('Unable to select files.');
    }
  }

  Future<void> _saveToVault() async {
    if (_selectedFiles.isEmpty || _isSaving) {
      _showMessage('Select at least one file.');
      return;
    }

    setState(() {
      _isSaving = true;
      _completed = 0;
    });

    int success = 0;

    for (final PlatformFile selectedFile in _selectedFiles) {
      try {
        final String? path = selectedFile.path;

        if (path == null || path.isEmpty) {
          continue;
        }

        await VaultStorageService.instance.importFile(
          sourceFile: File(path),
          originalFileName: selectedFile.name,
          category: _autoCategory(selectedFile),
        );

        success++;
      } catch (_) {}

      if (mounted) {
        setState(() {
          _completed++;
        });
      }
    }

    if (!mounted) return;

    setState(() {
      _isSaving = false;
    });

    if (success > 0) {
      Navigator.of(context).pop(true);
    } else {
      _showMessage('Unable to save selected files.');
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final double kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    return '${(kb / 1024).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF090D18),
      appBar: AppBar(
        backgroundColor: const Color(0xFF090D18),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Add Files to Vault',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 24),
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF151B2A),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: const Color(0xFF2B3142)),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.auto_awesome_rounded,
                          color: Color(0xFFAAA4FF),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Keeper automatically organizes files by name and file type. Files are encrypted locally.',
                            style: TextStyle(
                              color: Color(0xFFB6BAC7),
                              fontSize: 12,
                              height: 1.45,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  OutlinedButton.icon(
                    onPressed: _isSaving ? null : _pickFiles,
                    icon: const Icon(Icons.add_rounded),
                    label: const Text('Choose Files'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFAAA4FF),
                      minimumSize: const Size.fromHeight(52),
                      side: const BorderSide(color: Color(0xFF5147E5)),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_selectedFiles.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: Column(
                        children: [
                          Icon(
                            Icons.folder_open_rounded,
                            color: Color(0xFF555D71),
                            size: 52,
                          ),
                          SizedBox(height: 12),
                          Text(
                            'No files selected',
                            style: TextStyle(color: Color(0xFF8E91A3)),
                          ),
                        ],
                      ),
                    )
                  else
                    ...List.generate(_selectedFiles.length, (index) {
                      final PlatformFile file = _selectedFiles[index];

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Container(
                          padding: const EdgeInsets.all(13),
                          decoration: BoxDecoration(
                            color: const Color(0xFF121725),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFF292F42)),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.insert_drive_file_outlined,
                                color: Color(0xFFAAA4FF),
                              ),
                              const SizedBox(width: 11),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      file.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${_autoCategory(file)} • ${_formatSize(file.size)}',
                                      style: const TextStyle(
                                        color: Color(0xFF8E91A3),
                                        fontSize: 11,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              if (!_isSaving)
                                IconButton(
                                  onPressed: () {
                                    setState(() {
                                      _selectedFiles.removeAt(index);
                                    });
                                  },
                                  icon: const Icon(
                                    Icons.close_rounded,
                                    color: Color(0xFF8E91A3),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
              decoration: const BoxDecoration(
                color: Color(0xFF0D1220),
                border: Border(top: BorderSide(color: Color(0xFF252B3C))),
              ),
              child: SafeArea(
                top: false,
                child: SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton.icon(
                    onPressed: _isSaving ? null : _saveToVault,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 19,
                            height: 19,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.lock_rounded),
                    label: Text(
                      _isSaving
                          ? 'Encrypting $_completed/${_selectedFiles.length}'
                          : 'Encrypt & Save',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF766DFF),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
