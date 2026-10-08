import 'dart:io';

import 'package:flutter/material.dart';

import '../models/vault_document_model.dart';
import '../services/vault_security_service.dart';
import '../services/vault_storage_service.dart';
import '../services/vault_file_action_service.dart';
import 'vault_file_viewer_screen.dart';
import 'vault_lock_screen.dart';
import 'vault_upload_screen.dart';

class PersonalVaultScreen extends StatefulWidget {
  const PersonalVaultScreen({super.key});

  @override
  State<PersonalVaultScreen> createState() => _PersonalVaultScreenState();
}

class _PersonalVaultScreenState extends State<PersonalVaultScreen>
    with WidgetsBindingObserver {
  static const List<String> _categories = [
    'All',
    'Aadhaar',
    'PAN Card',
    'Passport',
    'Driving License',
    'Marksheets',
    'Certificates',
    'Resume',
    'Bank Documents',
    'Medical Records',
    'Images',
    'PDFs',
    'Audio Files',
    'Personal Files',
  ];

  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = true;
  bool _isDeleting = false;
  bool _isPerformingFileAction = false;
  bool _authRouteOpen = false;
  String _selectedCategory = 'All';
  String _query = '';
  int _storageUsedBytes = 0;
  List<VaultDocumentModel> _documents = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _initializeVault();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      VaultSecurityService.instance.lockVault();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    VaultSecurityService.instance.lockVault();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initializeVault() async {
    final bool unlocked = await _ensureUnlocked();

    if (!unlocked) {
      if (!mounted) return;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      });
      return;
    }

    await _loadVault();
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _loadVault() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      final List<VaultDocumentModel> documents = await VaultStorageService
          .instance
          .getDocuments();

      final int usedBytes = await VaultStorageService.instance
          .getStorageUsedBytes();

      if (!mounted) return;

      setState(() {
        _documents = documents;
        _storageUsedBytes = usedBytes;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      _showMessage('Unable to load Personal Vault.');
    }
  }

  List<VaultDocumentModel> get _filteredDocuments {
    final String query = _query.trim().toLowerCase();

    return _documents.where((document) {
      final bool matchesCategory =
          _selectedCategory == 'All' || document.category == _selectedCategory;

      final bool matchesQuery =
          query.isEmpty ||
          document.fileName.toLowerCase().contains(query) ||
          document.category.toLowerCase().contains(query) ||
          document.fileType.toLowerCase().contains(query);

      return matchesCategory && matchesQuery;
    }).toList();
  }

  Future<bool> _ensureUnlocked() async {
    final VaultSecurityService security = VaultSecurityService.instance;

    if (security.isUnlocked) return true;
    if (_authRouteOpen || !mounted) return false;

    _authRouteOpen = true;

    try {
      final bool? unlocked = await Navigator.of(context).push<bool>(
        MaterialPageRoute<bool>(builder: (_) => const VaultLockScreen()),
      );

      return unlocked == true;
    } finally {
      _authRouteOpen = false;
    }
  }

  Future<void> _openUpload() async {
    if (!await _ensureUnlocked()) return;
    if (!mounted) return;

    final bool? changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(builder: (_) => const VaultUploadScreen()),
    );

    if (changed == true) {
      await _loadVault();
    }
  }

  Future<void> _openDocument(VaultDocumentModel document) async {
    if (!await _ensureUnlocked()) return;
    if (!mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => VaultFileViewerScreen(document: document),
      ),
    );
  }

  Future<void> _shareDocument(VaultDocumentModel document) async {
    if (_isPerformingFileAction) return;

    setState(() {
      _isPerformingFileAction = true;
    });

    try {
      await VaultFileActionService.instance.share(document);
    } catch (_) {
      _showMessage('Unable to share this secure file.');
    } finally {
      if (mounted) {
        setState(() {
          _isPerformingFileAction = false;
        });
      }
    }
  }

  Future<void> _printDocument(VaultDocumentModel document) async {
    if (_isPerformingFileAction) return;

    setState(() {
      _isPerformingFileAction = true;
    });

    try {
      final bool started =
          await VaultFileActionService.instance.print(document);

      if (!started) {
        _showMessage(
          'Printing is not available for this file type on this device.',
        );
      }
    } catch (_) {
      _showMessage('Unable to print this secure file.');
    } finally {
      if (mounted) {
        setState(() {
          _isPerformingFileAction = false;
        });
      }
    }
  }

  Future<void> _editDocument(VaultDocumentModel document) async {
    final TextEditingController nameController = TextEditingController(
      text: document.fileName,
    );
    String selectedCategory = document.category;

    final List<String> editableCategories = _categories
        .where((category) => category != 'All')
        .toList();

    if (!editableCategories.contains(selectedCategory)) {
      selectedCategory = 'Personal Files';
    }

    final bool? saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF151B2A),
              title: const Text(
                'Edit secure file',
                style: TextStyle(color: Colors.white),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'File name',
                      labelStyle: const TextStyle(color: Color(0xFF9CA3AF)),
                      filled: true,
                      fillColor: const Color(0xFF101624),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
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
                      fillColor: const Color(0xFF101624),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    items: editableCategories
                        .map(
                          (category) => DropdownMenuItem<String>(
                            value: category,
                            child: Text(category),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setDialogState(() {
                        selectedCategory = value;
                      });
                    },
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (saved != true) {
      nameController.dispose();
      return;
    }

    final String newName = nameController.text.trim();
    nameController.dispose();

    if (newName.isEmpty) {
      _showMessage('File name cannot be empty.');
      return;
    }

    try {
      await VaultStorageService.instance.updateDocument(
        document: document,
        fileName: newName,
        category: selectedCategory,
      );
      await _loadVault();
      _showMessage('Secure file updated.');
    } catch (_) {
      _showMessage('Unable to update this file.');
    }
  }

  Future<void> _deleteDocument(VaultDocumentModel document) async {
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF151B2A),
          title: const Text(
            'Delete secure file?',
            style: TextStyle(color: Colors.white),
          ),
          content: Text(
            '${document.fileName} will be permanently removed from this device.',
            style: const TextStyle(color: Color(0xFFB8BBC7), height: 1.45),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text(
                'Delete',
                style: TextStyle(color: Color(0xFFFF7D92)),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    setState(() {
      _isDeleting = true;
    });

    try {
      await VaultStorageService.instance.deleteDocument(document);

      await _loadVault();
      _showMessage('File deleted from Personal Vault.');
    } catch (_) {
      _showMessage('Unable to delete this file.');
    } finally {
      if (mounted) {
        setState(() {
          _isDeleting = false;
        });
      }
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';

    final double kb = bytes / 1024;

    if (kb < 1024) {
      return '${kb.toStringAsFixed(1)} KB';
    }

    final double mb = kb / 1024;

    if (mb < 1024) {
      return '${mb.toStringAsFixed(1)} MB';
    }

    return '${(mb / 1024).toStringAsFixed(2)} GB';
  }

  IconData _fileIcon(VaultDocumentModel document) {
    final String type = document.fileType.toLowerCase();

    if (['jpg', 'jpeg', 'png', 'webp', 'heic'].contains(type)) {
      return Icons.image_rounded;
    }

    if (type == 'pdf') {
      return Icons.picture_as_pdf_rounded;
    }

    if (['mp3', 'wav', 'm4a', 'aac', 'ogg'].contains(type)) {
      return Icons.audio_file_rounded;
    }

    if (['doc', 'docx', 'txt', 'rtf'].contains(type)) {
      return Icons.description_rounded;
    }

    return Icons.insert_drive_file_rounded;
  }

  Widget _buildThumbnail(VaultDocumentModel document) {
    final String type = document.fileType.toLowerCase();
    final bool isImage = ['jpg', 'jpeg', 'png', 'webp', 'heic'].contains(type);

    if (!isImage) {
      return Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: const Color(0xFF24205A),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(_fileIcon(document), color: const Color(0xFFAAA4FF)),
      );
    }

    return FutureBuilder<File>(
      future: VaultStorageService.instance.decryptToTemporaryFile(document),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: const Color(0xFF24205A),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.image_rounded, color: Color(0xFFAAA4FF)),
          );
        }

        return ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.file(
            snapshot.data!,
            width: 48,
            height: 48,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) {
              return Container(
                width: 48,
                height: 48,
                color: const Color(0xFF24205A),
                child: const Icon(
                  Icons.image_rounded,
                  color: Color(0xFFAAA4FF),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildCategoryChip(String category) {
    final bool selected = category == _selectedCategory;

    return ChoiceChip(
      selected: selected,
      label: Text(category),
      onSelected: (_) {
        setState(() {
          _selectedCategory = category;
        });
      },
      selectedColor: const Color(0xFF766DFF),
      backgroundColor: const Color(0xFF121725),
      side: BorderSide(
        color: selected ? const Color(0xFF766DFF) : const Color(0xFF292F42),
      ),
      labelStyle: TextStyle(
        color: selected ? Colors.white : const Color(0xFFB4B8C5),
        fontWeight: FontWeight.w700,
        fontSize: 11.5,
      ),
    );
  }

  Widget _buildDocumentCard(VaultDocumentModel document) {
    return Material(
      color: const Color(0xFF121725),
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: () => _openDocument(document),
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFF292F42)),
          ),
          child: Row(
            children: [
              _buildThumbnail(document),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      document.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${document.category} • ${_formatSize(document.fileSizeBytes)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF8E91A3),
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.lock_rounded,
                color: Color(0xFF6FCF97),
                size: 18,
              ),
              PopupMenuButton<String>(
                color: const Color(0xFF1A2030),
                iconColor: const Color(0xFF8E91A3),
                onSelected: (value) {
                  if (value == 'share') {
                    _shareDocument(document);
                  } else if (value == 'print') {
                    _printDocument(document);
                  } else if (value == 'edit') {
                    _editDocument(document);
                  } else if (value == 'delete') {
                    _deleteDocument(document);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem<String>(
                    value: 'share',
                    child: Row(
                      children: [
                        Icon(Icons.share_outlined, color: Color(0xFFAAA4FF)),
                        SizedBox(width: 10),
                        Text(
                          'Share',
                          style: TextStyle(color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'print',
                    child: Row(
                      children: [
                        Icon(Icons.print_outlined, color: Color(0xFFAAA4FF)),
                        SizedBox(width: 10),
                        Text(
                          'Print',
                          style: TextStyle(color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit_outlined, color: Color(0xFFAAA4FF)),
                        SizedBox(width: 10),
                        Text(
                          'Rename / Move',
                          style: TextStyle(color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                  PopupMenuItem<String>(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(
                          Icons.delete_outline_rounded,
                          color: Color(0xFFFF7D92),
                        ),
                        SizedBox(width: 10),
                        Text(
                          'Delete',
                          style: TextStyle(color: Color(0xFFFF7D92)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<VaultDocumentModel> documents = _filteredDocuments;

    return Scaffold(
      backgroundColor: const Color(0xFF090D18),
      appBar: AppBar(
        backgroundColor: const Color(0xFF090D18),
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Personal Vault',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _loadVault,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: (_isDeleting || _isPerformingFileAction) ? null : _openUpload,
        backgroundColor: const Color(0xFF766DFF),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: const Text(
          'Add Files',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF1A1748), Color(0xFF11182A)],
                      ),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: const Color(0xFF383174)),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.enhanced_encryption_rounded,
                          color: Color(0xFFAAA4FF),
                          size: 34,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Encrypted Local Storage',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 17,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${_documents.length} files • ${_formatSize(_storageUsedBytes)} used',
                                style: const TextStyle(
                                  color: Color(0xFFB0B4C2),
                                  fontSize: 12,
                                ),
                              ),
                              const SizedBox(height: 5),
                              const Text(
                                'No cloud sync • No AI access',
                                style: TextStyle(
                                  color: Color(0xFF6FCF97),
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) {
                      setState(() {
                        _query = value;
                      });
                    },
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Search secure files...',
                      hintStyle: const TextStyle(color: Color(0xFF777D8E)),
                      prefixIcon: const Icon(
                        Icons.search_rounded,
                        color: Color(0xFFAAA4FF),
                      ),
                      filled: true,
                      fillColor: const Color(0xFF121725),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(17),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 42,
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    scrollDirection: Axis.horizontal,
                    itemCount: _categories.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      return _buildCategoryChip(_categories[index]);
                    },
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: _isLoading
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: Color(0xFF766DFF),
                          ),
                        )
                      : documents.isEmpty
                      ? const Center(
                          child: Padding(
                            padding: EdgeInsets.all(28),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.lock_outline_rounded,
                                  color: Color(0xFF766DFF),
                                  size: 58,
                                ),
                                SizedBox(height: 15),
                                Text(
                                  'No secure files found',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                SizedBox(height: 7),
                                Text(
                                  'Add files to encrypt and store them privately on this device.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: Color(0xFF8E91A3),
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : RefreshIndicator(
                          onRefresh: _loadVault,
                          color: const Color(0xFF766DFF),
                          backgroundColor: const Color(0xFF151B2A),
                          child: ListView.separated(
                            padding: const EdgeInsets.fromLTRB(18, 5, 18, 100),
                            itemCount: documents.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              return _buildDocumentCard(documents[index]);
                            },
                          ),
                        ),
                ),
              ],
            ),
            if (_isDeleting || _isPerformingFileAction)
              Container(
                color: Colors.black54,
                child: const Center(
                  child: CircularProgressIndicator(color: Color(0xFF766DFF)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
