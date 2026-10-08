import 'dart:io';

import '../services/text_extractor_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import '../services/organization_subscription_service.dart';
import 'organization_subscription_screen.dart';

class UploadScreen extends StatefulWidget {
  const UploadScreen({super.key});

  @override
  State<UploadScreen> createState() => _UploadScreenState();
}

class _UploadScreenState extends State<UploadScreen> {
  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _loadOrganizations();
  }

  String _selectedSpace = 'personal';
  String? _selectedCategory;
  String _selectedVisibility = 'private';

  final List<PlatformFile> _selectedFiles = [];

  bool _isUploading = false;
  bool _isCheckingOrganizationPermission = false;
  bool _canUploadToOrganization = true;
  String _organizationUploadPermission = 'everyone';
  String? _linkedOrganizationId;
  String _linkedOrganizationName = '';
  bool _organizationSubscriptionExpired = false;
  bool _selectedOrganizationIsOwner = false;
  List<_OrganizationChoice> _organizations = const [];
  int _uploadedFiles = 0;
  int _totalFilesToUpload = 0;
  int _filesNeedingVisualRead = 0;
  String? _lastUploadError;

  final List<String> _personalCategories = [
    'Aadhaar',
    'PAN Card',
    'Certificate',
    'Resume',
    'Marksheet',
    'Personal Notes',
    'Bill',
    'Other',
  ];

  final List<String> _organizationCategories = [
    'Notice',
    'Exam Timetable',
    'Syllabus',
    'Previous Year Paper',
    'Assignment',
    'Lab Manual',
    'Internship',
    'Project',
    'Study Material',
    'Other',
  ];

  List<String> get _currentCategories {
    return _selectedSpace == 'personal'
        ? _personalCategories
        : _organizationCategories;
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _takePhoto() async {
    if (_isUploading) return;

    try {
      final XFile? photo = await _imagePicker.pickImage(
        source: ImageSource.camera,
        imageQuality: 92,
      );

      if (photo == null) {
        return;
      }

      final File file = File(photo.path);

      if (!await file.exists()) {
        _showMessage('Captured photo could not be accessed.');
        return;
      }

      final int fileSize = await file.length();
      const int maximumFileSize = 20 * 1024 * 1024;

      if (fileSize > maximumFileSize) {
        _showMessage('Photo is larger than the 20 MB limit.');
        return;
      }
      final PlatformFile platformFile = PlatformFile(
        name: photo.name,
        path: photo.path,
        size: fileSize,
      );

      final bool alreadySelected = _selectedFiles.any(
        (selectedFile) =>
            selectedFile.path == platformFile.path &&
            selectedFile.size == platformFile.size,
      );

      if (!alreadySelected && mounted) {
        setState(() {
          _selectedFiles.add(platformFile);
        });

        _showMessage('Photo captured and selected.');
      }
    } catch (_) {
      _showMessage('Unable to open the camera. Please try again.');
    }
  }

  Future<void> _pickFiles() async {
    if (_isUploading) return;

    try {
      final FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: [
          'pdf',
          'doc',
          'docx',
          'txt',
          'jpg',
          'jpeg',
          'png',
          'webp',
        ],
        allowMultiple: true,
        withData: false,
      );

      if (result == null || result.files.isEmpty) {
        return;
      }

      const int maximumFileSize = 20 * 1024 * 1024;

      final List<PlatformFile> validFiles = [];
      int oversizedFiles = 0;
      int inaccessibleFiles = 0;

      for (final PlatformFile file in result.files) {
        if (file.size > maximumFileSize) {
          oversizedFiles++;
          continue;
        }

        if (file.path == null || file.path!.isEmpty) {
          inaccessibleFiles++;
          continue;
        }

        final bool alreadySelected = _selectedFiles.any(
          (selectedFile) =>
              selectedFile.name == file.name &&
              selectedFile.size == file.size &&
              selectedFile.path == file.path,
        );

        if (!alreadySelected) {
          validFiles.add(file);
        }
      }

      if (!mounted) return;

      setState(() {
        _selectedFiles.addAll(validFiles);
      });

      if (validFiles.isNotEmpty) {
        _showMessage('${validFiles.length} file(s) selected.');
      }

      if (oversizedFiles > 0) {
        _showMessage(
          '$oversizedFiles file(s) skipped because maximum size is 20 MB.',
        );
      } else if (inaccessibleFiles > 0) {
        _showMessage('$inaccessibleFiles file(s) could not be accessed.');
      }
    } catch (error) {
      _showMessage('Unable to select files. Please try again.');
    }
  }

  void _removeSelectedFile(int index) {
    if (_isUploading) return;

    setState(() {
      _selectedFiles.removeAt(index);
    });
  }

  void _clearSelectedFiles() {
    if (_isUploading) return;

    setState(() {
      _selectedFiles.clear();
    });
  }

  Future<void> _checkOrganizationUploadPermission() async {
    final User? currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser == null) {
      if (!mounted) return;

      setState(() {
        _canUploadToOrganization = false;
        _linkedOrganizationId = null;
      });
      return;
    }

    if (mounted) {
      setState(() {
        _isCheckingOrganizationPermission = true;
      });
    }

    try {
      if (_organizations.isEmpty) {
        await _loadOrganizations();
      }

      final String? organizationId =
          _linkedOrganizationId ?? await _findOrganizationId(currentUser.uid);

      if (organizationId == null || organizationId.isEmpty) {
        if (!mounted) return;

        setState(() {
          _linkedOrganizationId = null;
          _organizationUploadPermission = 'everyone';
          _canUploadToOrganization = false;
          _organizationSubscriptionExpired = false;
        });
        return;
      }

      _OrganizationChoice? choice;
      for (final item in _organizations) {
        if (item.id == organizationId) {
          choice = item;
          break;
        }
      }
      if (choice == null) {
        await _loadOrganizations(force: true);
        for (final item in _organizations) {
          if (item.id == organizationId) {
            choice = item;
            break;
          }
        }
      }
      if (choice == null) throw StateError('Organization not found.');
      final _OrganizationChoice selectedChoice = choice;

      final OrganizationSubscriptionAccess subscription =
          await OrganizationSubscriptionService.load(organizationId);
      final bool allowedByRole =
          selectedChoice.uploadPermission != 'admin_only' ||
          selectedChoice.isAdmin;
      final bool subscriptionExpired = !subscription.canUseOrganizationUploads;

      if (!mounted) return;

      setState(() {
        _linkedOrganizationId = organizationId;
        _linkedOrganizationName = selectedChoice.name;
        _organizationUploadPermission = selectedChoice.uploadPermission;
        _selectedOrganizationIsOwner = selectedChoice.isOwner;
        _organizationSubscriptionExpired = subscriptionExpired;
        _canUploadToOrganization = allowedByRole && !subscriptionExpired;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _canUploadToOrganization = false;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isCheckingOrganizationPermission = false;
        });
      }
    }
  }

  Future<void> _loadOrganizations({bool force = false}) async {
    if (_isCheckingOrganizationPermission && !force) return;
    final User? user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (mounted) {
      setState(() => _isCheckingOrganizationPermission = true);
    }
    try {
      final FirebaseFirestore firestore = FirebaseFirestore.instance;
      final results = await Future.wait([
        firestore
            .collection('organizations')
            .where('memberIds', arrayContains: user.uid)
            .get(),
        firestore.collection('users').doc(user.uid).get(),
      ]);
      final QuerySnapshot<Map<String, dynamic>> organizations =
          results[0] as QuerySnapshot<Map<String, dynamic>>;
      final DocumentSnapshot<Map<String, dynamic>> userDocument =
          results[1] as DocumentSnapshot<Map<String, dynamic>>;

      final List<_OrganizationChoice> choices =
          organizations.docs
              .where((doc) => doc.data()['status']?.toString() != 'deleted')
              .map((doc) {
                final data = doc.data();
                final String ownerId = data['ownerId']?.toString() ?? '';
                final List<String> admins =
                    (data['adminIds'] as List<dynamic>? ?? const [])
                        .map((item) => item.toString())
                        .toList();
                return _OrganizationChoice(
                  id: doc.id,
                  name: data['name']?.toString() ?? 'Organization',
                  type: data['type']?.toString() ?? '',
                  uploadPermission:
                      data['uploadPermission']?.toString() ?? 'everyone',
                  isOwner: ownerId == user.uid,
                  isAdmin: ownerId == user.uid || admins.contains(user.uid),
                );
              })
              .toList()
            ..sort(
              (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
            );

      final String savedId =
          userDocument.data()?['organizationId']?.toString() ?? '';
      _OrganizationChoice? selected;
      for (final item in choices) {
        if (item.id == (_linkedOrganizationId ?? savedId)) {
          selected = item;
          break;
        }
      }
      selected ??= choices.isEmpty ? null : choices.first;

      if (!mounted) return;
      setState(() {
        _organizations = choices;
        _linkedOrganizationId = selected?.id;
        _linkedOrganizationName = selected?.name ?? '';
      });
      if (selected != null) {
        await _selectOrganization(selected, showExpiredMessage: false);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _organizations = const [];
        _canUploadToOrganization = false;
      });
    } finally {
      if (mounted) {
        setState(() => _isCheckingOrganizationPermission = false);
      }
    }
  }

  Future<void> _selectOrganization(
    _OrganizationChoice choice, {
    bool showExpiredMessage = true,
  }) async {
    if (_isUploading) return;
    setState(() {
      _linkedOrganizationId = choice.id;
      _linkedOrganizationName = choice.name;
      _organizationUploadPermission = choice.uploadPermission;
      _selectedOrganizationIsOwner = choice.isOwner;
    });

    try {
      final access = await OrganizationSubscriptionService.load(choice.id);
      if (!mounted) return;
      final bool expired = !access.canUseOrganizationUploads;
      setState(() {
        _organizationSubscriptionExpired = expired;
        _canUploadToOrganization =
            !expired &&
            (choice.uploadPermission != 'admin_only' || choice.isAdmin);
      });
      if (expired && showExpiredMessage) {
        await _showExpiredSubscriptionDialog();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _canUploadToOrganization = false);
    }
  }

  Future<void> _showExpiredSubscriptionDialog() async {
    if (!mounted) return;
    if (_selectedOrganizationIsOwner) {
      final bool subscribe =
          await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              backgroundColor: const Color(0xFF151B2A),
              title: const Text(
                'Free usage has ended',
                style: TextStyle(color: Colors.white),
              ),
              content: const Text(
                'Your 14-day organization trial is over. Subscribe for ₹499/month to upload files for this organization.',
                style: TextStyle(color: Color(0xFFB8BBC7), height: 1.4),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Not now'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Subscribe ₹499'),
                ),
              ],
            ),
          ) ??
          false;
      if (subscribe && mounted && _linkedOrganizationId != null) {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => OrganizationSubscriptionScreen(
              organizationId: _linkedOrganizationId!,
              organizationName: _linkedOrganizationName,
            ),
          ),
        );
        await _checkOrganizationUploadPermission();
      }
    } else {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: const Color(0xFF151B2A),
          title: const Text(
            'Organization plan expired',
            style: TextStyle(color: Colors.white),
          ),
          content: const Text(
            'New organization uploads are paused. Please contact the organization owner to renew the plan.',
            style: TextStyle(color: Color(0xFFB8BBC7), height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  Future<String?> _findOrganizationId(String userId) async {
    if (_linkedOrganizationId != null && _linkedOrganizationId!.isNotEmpty) {
      return _linkedOrganizationId;
    }
    final FirebaseFirestore firestore = FirebaseFirestore.instance;

    final DocumentSnapshot<Map<String, dynamic>> userSnapshot = await firestore
        .collection('users')
        .doc(userId)
        .get();

    final String? savedOrganizationId = userSnapshot
        .data()?['organizationId']
        ?.toString();

    if (savedOrganizationId != null && savedOrganizationId.trim().isNotEmpty) {
      return savedOrganizationId.trim();
    }

    final QuerySnapshot<Map<String, dynamic>> ownedOrganization =
        await firestore
            .collection('organizations')
            .where('ownerId', isEqualTo: userId)
            .limit(1)
            .get();

    if (ownedOrganization.docs.isNotEmpty) {
      return ownedOrganization.docs.first.id;
    }

    final QuerySnapshot<Map<String, dynamic>> joinedOrganization =
        await firestore
            .collection('organizations')
            .where('memberIds', arrayContains: userId)
            .limit(1)
            .get();

    if (joinedOrganization.docs.isNotEmpty) {
      return joinedOrganization.docs.first.id;
    }

    return null;
  }

  Future<void> _insertDocumentWithSchemaFallback(
    supabase.SupabaseClient client,
    Map<String, dynamic> payload,
  ) async {
    final Map<String, dynamic> currentPayload = Map<String, dynamic>.from(
      payload,
    );

    for (int attempt = 0; attempt < 12; attempt++) {
      try {
        await client.from('documents').insert(currentPayload);
        return;
      } catch (error) {
        final RegExpMatch? match = RegExp(
          r"Could not find the '([^']+)' column",
          caseSensitive: false,
        ).firstMatch(error.toString());

        final String? missingColumn = match?.group(1);

        if (missingColumn == null ||
            !currentPayload.containsKey(missingColumn)) {
          rethrow;
        }

        currentPayload.remove(missingColumn);
      }
    }

    throw StateError(
      'The documents table schema is incompatible with this upload.',
    );
  }

  Future<bool> _uploadSingleFile({
    required PlatformFile selectedFile,
    required User firebaseUser,
    required String category,
    required String? organizationId,
  }) async {
    final String? localPath = selectedFile.path;

    if (localPath == null || localPath.isEmpty) {
      return false;
    }

    final File localFile = File(localPath);

    if (!await localFile.exists()) {
      return false;
    }

    String? uploadedStoragePath;

    try {
      String extension = (selectedFile.extension ?? '').trim().toLowerCase();

      if (extension.isEmpty && selectedFile.name.contains('.')) {
        extension = selectedFile.name.split('.').last.trim().toLowerCase();
      }

      if (extension.isEmpty && localPath.contains('.')) {
        extension = localPath.split('.').last.trim().toLowerCase();
      }

      TextExtractionResult extractionResult;

      try {
        extractionResult = await TextExtractorService.extract(
          filePath: localPath,
          extension: extension,
        );
      } catch (_) {
        extractionResult = const TextExtractionResult(
          text: '',
          status: 'extraction_failed',
        );
      }

      final String effectiveCategory = _detectedCategory(
        selectedCategory: category,
        fileName: selectedFile.name,
        extractedText: extractionResult.text,
      );

      final String safeFileName = selectedFile.name.replaceAll(
        RegExp(r'[^a-zA-Z0-9._-]'),
        '_',
      );

      final String uniquePrefix =
          '${DateTime.now().microsecondsSinceEpoch}_${_uploadedFiles + 1}';

      final String storageFolder = _selectedSpace == 'personal'
          ? 'personal/${firebaseUser.uid}'
          : 'organizations/$organizationId';

      uploadedStoragePath = '$storageFolder/${uniquePrefix}_$safeFileName';

      final supabase.SupabaseClient client = supabase.Supabase.instance.client;

      await client.storage
          .from('Keeper-documents')
          .upload(
            uploadedStoragePath,
            localFile,
            fileOptions: const supabase.FileOptions(
              cacheControl: '3600',
              upsert: false,
            ),
          );

      final String publicUrl = client.storage
          .from('Keeper-documents')
          .getPublicUrl(uploadedStoragePath);

      await _insertDocumentWithSchemaFallback(client, {
        'user_id': firebaseUser.uid,
        'file_name': selectedFile.name,
        'category': effectiveCategory,
        'space': _selectedSpace,
        'visibility': _selectedVisibility,
        'file_url': publicUrl,
        'storage_path': uploadedStoragePath,
        'organization_id': organizationId,
        'extracted_text': extractionResult.text,
        'processing_status': extractionResult.status,
        'file_extension': extension,
        'mime_type': _mimeTypeForExtension(extension),
        'file_size': selectedFile.size,
      });

      if (extractionResult.text.trim().isEmpty) {
        _filesNeedingVisualRead++;
      }

      return true;
    } catch (error) {
      _lastUploadError = error.toString();

      if (uploadedStoragePath != null) {
        try {
          await supabase.Supabase.instance.client.storage
              .from('Keeper-documents')
              .remove([uploadedStoragePath]);
        } catch (_) {
          // Ignore cleanup error.
        }
      }

      return false;
    }
  }

  Future<void> _uploadFile() async {
    FocusScope.of(context).unfocus();

    if (_selectedCategory == null) {
      _showMessage('Please select a document category.');
      return;
    }

    if (_selectedFiles.isEmpty) {
      _showMessage('Please select at least one file.');
      return;
    }

    final User? firebaseUser = FirebaseAuth.instance.currentUser;

    if (firebaseUser == null) {
      _showMessage('Your login session expired. Please sign in again.');
      return;
    }

    setState(() {
      _isUploading = true;
      _uploadedFiles = 0;
      _totalFilesToUpload = _selectedFiles.length;
      _filesNeedingVisualRead = 0;
      _lastUploadError = null;
    });

    String? organizationId;

    try {
      if (_selectedSpace == 'organization') {
        await _checkOrganizationUploadPermission();

        if (!_canUploadToOrganization) {
          if (_organizationSubscriptionExpired) {
            throw Exception('organization-subscription-expired');
          }
          throw Exception('organization-upload-denied');
        }

        organizationId =
            _linkedOrganizationId ??
            await _findOrganizationId(firebaseUser.uid);

        if (organizationId == null || organizationId.isEmpty) {
          throw Exception('organization-not-found');
        }
      }

      int successCount = 0;
      int failedCount = 0;

      final List<PlatformFile> filesToUpload = List.from(_selectedFiles);

      for (final PlatformFile file in filesToUpload) {
        final bool success = await _uploadSingleFile(
          selectedFile: file,
          firebaseUser: firebaseUser,
          category: _selectedCategory!,
          organizationId: organizationId,
        );

        if (success) {
          successCount++;
        } else {
          failedCount++;
        }

        if (mounted) {
          setState(() {
            _uploadedFiles++;
          });
        }
      }

      if (!mounted) return;

      setState(() {
        _selectedFiles.clear();
        _selectedCategory = null;
      });

      if (failedCount == 0) {
        if (_filesNeedingVisualRead > 0) {
          _showMessage(
            '$successCount document(s) uploaded. Keeper AI will read '
            '$_filesNeedingVisualRead original image/PDF file(s) visually when asked.',
          );
        } else {
          _showMessage(
            '$successCount document(s) uploaded and indexed successfully.',
          );
        }
      } else {
        final String detail = _lastUploadError?.trim() ?? '';

        _showMessage(
          detail.isEmpty
              ? '$successCount uploaded, $failedCount failed.'
              : '$successCount uploaded, $failedCount failed: $detail',
        );
      }
    } catch (error) {
      final String errorText = error.toString().toLowerCase();

      if (errorText.contains('organization-subscription-expired')) {
        await _showExpiredSubscriptionDialog();
      } else if (errorText.contains('organization-upload-denied')) {
        _showMessage(
          'Only organization admins can upload documents in this workspace.',
        );
      } else if (errorText.contains('organization-not-found')) {
        _showMessage('No organization is linked with this account.');
      } else {
        _showMessage('Upload failed: $error');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _uploadedFiles = 0;
          _totalFilesToUpload = 0;
          _filesNeedingVisualRead = 0;
        });
      }
    }
  }

  String _mimeTypeForExtension(String extension) {
    switch (extension.toLowerCase()) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'pdf':
        return 'application/pdf';
      case 'txt':
      case 'text':
      case 'md':
      case 'csv':
      case 'log':
        return 'text/plain';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      default:
        return 'application/octet-stream';
    }
  }

  String _detectedCategory({
    required String selectedCategory,
    required String fileName,
    required String extractedText,
  }) {
    if (selectedCategory.trim().toLowerCase() != 'other') {
      return selectedCategory;
    }

    final String searchable = '$fileName\n$extractedText'.toLowerCase();
    final bool hasAadhaarNumber = RegExp(
      r'\b[0-9]{4}[\s-]*[0-9]{4}[\s-]*[0-9]{4}\b',
    ).hasMatch(searchable);

    if (searchable.contains('aadhaar') ||
        searchable.contains('aadhar') ||
        searchable.contains('uidai') ||
        searchable.contains('unique identification') ||
        (searchable.contains('government of india') && hasAadhaarNumber)) {
      return 'Aadhaar';
    }

    if (RegExp(r'\b[a-z]{5}[0-9]{4}[a-z]\b').hasMatch(searchable) ||
        searchable.contains('income tax department')) {
      return 'PAN Card';
    }

    if (searchable.contains('marksheet') ||
        searchable.contains('statement of marks') ||
        searchable.contains('grade card')) {
      return 'Marksheet';
    }

    if (searchable.contains('curriculum vitae') ||
        searchable.contains('resume')) {
      return 'Resume';
    }

    if (searchable.contains('certificate')) {
      return 'Certificate';
    }

    return selectedCategory;
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }

    final double kb = bytes / 1024;

    if (kb < 1024) {
      return '${kb.toStringAsFixed(1)} KB';
    }

    final double mb = kb / 1024;

    return '${mb.toStringAsFixed(1)} MB';
  }

  Widget _buildSelectedFilePreview(PlatformFile file) {
    final String extension = (file.extension ?? '').toLowerCase();
    final bool isImage =
        extension == 'jpg' ||
        extension == 'jpeg' ||
        extension == 'png' ||
        extension == 'webp';

    if (isImage && file.path != null && file.path!.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Image.file(
          File(file.path!),
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) {
            return _buildSelectedFileIcon(extension);
          },
        ),
      );
    }

    return _buildSelectedFileIcon(extension);
  }

  Widget _buildSelectedFileIcon(String extension) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: const Color(0xFF24205A),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(_fileIcon(extension), color: const Color(0xFFAAA4FF)),
    );
  }

  IconData _fileIcon(String extension) {
    switch (extension.toLowerCase()) {
      case 'pdf':
        return Icons.picture_as_pdf_rounded;

      case 'doc':
      case 'docx':
        return Icons.description_rounded;

      case 'txt':
        return Icons.notes_rounded;

      case 'jpg':
      case 'jpeg':
      case 'png':
        return Icons.image_rounded;

      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  Future<void> _changeSpace(String space) async {
    if (_isUploading) return;

    if (space == 'organization') {
      await _checkOrganizationUploadPermission();

      if (!mounted) return;

      if (_linkedOrganizationId == null) {
        _showMessage('No organization is linked with this account.');
        return;
      }

      if (_organizationSubscriptionExpired) {
        setState(() {
          _selectedSpace = 'organization';
          _selectedCategory = null;
          _selectedVisibility = 'organization';
        });
        await _showExpiredSubscriptionDialog();
        return;
      }

      if (!_canUploadToOrganization) {
        _showMessage(
          'Only organization admins can upload documents in this workspace.',
        );
        return;
      }
    }

    setState(() {
      _selectedSpace = space;
      _selectedCategory = null;

      if (space == 'personal') {
        _selectedVisibility = 'private';
      } else {
        _selectedVisibility = 'organization';
      }
    });
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
          'Upload Files',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Add to Keeper',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 29,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Upload multiple documents to your private space or shared organization workspace.',
                style: TextStyle(
                  color: Color(0xFF9CA3AF),
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 28),

              const _SectionTitle(title: 'Choose space'),
              const SizedBox(height: 12),

              Row(
                children: [
                  Expanded(
                    child: _SpaceCard(
                      icon: Icons.person_outline_rounded,
                      title: 'Personal',
                      subtitle: 'Only you',
                      selected: _selectedSpace == 'personal',
                      onTap: () {
                        _changeSpace('personal');
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _SpaceCard(
                      icon: Icons.apartment_rounded,
                      title: 'Organization',
                      subtitle: _isCheckingOrganizationPermission
                          ? 'Checking access...'
                          : !_canUploadToOrganization &&
                                _organizationUploadPermission == 'admin_only'
                          ? 'Admin upload only'
                          : 'Shared workspace',
                      selected: _selectedSpace == 'organization',
                      onTap: () {
                        _changeSpace('organization');
                      },
                    ),
                  ),
                ],
              ),

              if (_selectedSpace == 'organization' &&
                  _organizations.isNotEmpty) ...[
                const SizedBox(height: 22),
                const _SectionTitle(title: 'Choose organization'),
                const SizedBox(height: 10),
                ..._organizations.map(
                  (organization) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _OrganizationPickerTile(
                      organization: organization,
                      selected: organization.id == _linkedOrganizationId,
                      enabled: !_isUploading,
                      onTap: () => _selectOrganization(organization),
                    ),
                  ),
                ),
              ],

              if (_selectedSpace == 'organization' &&
                  _organizationSubscriptionExpired) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF2A2111),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF8A6818)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.workspace_premium_rounded,
                        color: Color(0xFFFFC857),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Text(
                          _selectedOrganizationIsOwner
                              ? 'Your free usage has ended. Subscribe for ₹499/month to upload organization files.'
                              : 'This organization plan has expired. Please contact the owner to resume uploads.',
                          style: const TextStyle(
                            color: Color(0xFFFFE4A3),
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              if (_organizationUploadPermission == 'admin_only' &&
                  !_canUploadToOrganization) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF231C2B),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF5E3344)),
                  ),
                  child: const Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.lock_outline_rounded,
                        color: Color(0xFFFF8CA1),
                        size: 21,
                      ),
                      SizedBox(width: 11),
                      Expanded(
                        child: Text(
                          'This organization allows uploads from admins only. '
                          'You can still view, search and ask Keeper AI about shared documents.',
                          style: TextStyle(
                            color: Color(0xFFFFC2CD),
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 26),

              const _SectionTitle(title: 'Document category'),
              const SizedBox(height: 10),

              DropdownButtonFormField<String>(
                key: ValueKey<String>(
                  '${_selectedSpace}_${_selectedCategory ?? 'empty'}',
                ),
                initialValue: _selectedCategory,
                dropdownColor: const Color(0xFF121725),
                icon: const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: Color(0xFF8E91A3),
                ),
                style: const TextStyle(color: Colors.white, fontSize: 15),
                decoration: _inputDecoration(
                  hint: 'Select a category',
                  icon: Icons.category_outlined,
                ),
                items: _currentCategories.map((category) {
                  return DropdownMenuItem<String>(
                    value: category,
                    child: Text(category),
                  );
                }).toList(),
                onChanged: _isUploading
                    ? null
                    : (value) {
                        setState(() {
                          _selectedCategory = value;
                        });
                      },
              ),

              const SizedBox(height: 26),

              const _SectionTitle(title: 'Visibility'),
              const SizedBox(height: 10),

              if (_selectedSpace == 'personal')
                _VisibilityOption(
                  value: 'private',
                  groupValue: _selectedVisibility,
                  icon: Icons.lock_outline_rounded,
                  title: 'Private',
                  subtitle: 'Only you can access these documents',
                  enabled: !_isUploading,
                  onChanged: (value) {
                    setState(() {
                      _selectedVisibility = value;
                    });
                  },
                )
              else ...[
                _VisibilityOption(
                  value: 'organization',
                  groupValue: _selectedVisibility,
                  icon: Icons.groups_outlined,
                  title: 'Organization Members',
                  subtitle: 'All organization members can access them',
                  enabled: !_isUploading,
                  onChanged: (value) {
                    setState(() {
                      _selectedVisibility = value;
                    });
                  },
                ),
                const SizedBox(height: 10),
                _VisibilityOption(
                  value: 'admin',
                  groupValue: _selectedVisibility,
                  icon: Icons.admin_panel_settings_outlined,
                  title: 'Admin Only',
                  subtitle: 'Visible only to organization administrators',
                  enabled: !_isUploading,
                  onChanged: (value) {
                    setState(() {
                      _selectedVisibility = value;
                    });
                  },
                ),
              ],

              const SizedBox(height: 26),

              Row(
                children: [
                  const Expanded(child: _SectionTitle(title: 'Select files')),
                  if (_selectedFiles.isNotEmpty)
                    TextButton(
                      onPressed: _isUploading ? null : _clearSelectedFiles,
                      child: const Text('Clear all'),
                    ),
                ],
              ),
              const SizedBox(height: 10),

              Row(
                children: [
                  Expanded(
                    child: _UploadSourceCard(
                      icon: Icons.camera_alt_rounded,
                      title: 'Take Photo',
                      subtitle: 'Scan with camera',
                      enabled: !_isUploading,
                      onTap: _takePhoto,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _UploadSourceCard(
                      icon: Icons.folder_open_rounded,
                      title: _selectedFiles.isEmpty
                          ? 'Choose Files'
                          : 'Add More',
                      subtitle: 'PDF, DOCX, TXT and images',
                      enabled: !_isUploading,
                      onTap: _pickFiles,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              const Text(
                'Maximum file size: 20 MB each',
                style: TextStyle(color: Color(0xFF818596), fontSize: 12),
              ),

              if (_selectedFiles.isNotEmpty) ...[
                const SizedBox(height: 18),

                Text(
                  '${_selectedFiles.length} file(s) selected',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),

                const SizedBox(height: 12),

                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _selectedFiles.length,
                  separatorBuilder: (context, index) {
                    return const SizedBox(height: 10);
                  },
                  itemBuilder: (context, index) {
                    final PlatformFile file = _selectedFiles[index];

                    return Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(15),
                      decoration: BoxDecoration(
                        color: const Color(0xFF121725),
                        borderRadius: BorderRadius.circular(17),
                        border: Border.all(color: const Color(0xFF292F42)),
                      ),
                      child: Row(
                        children: [
                          _buildSelectedFilePreview(file),
                          const SizedBox(width: 13),
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
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  _formatFileSize(file.size),
                                  style: const TextStyle(
                                    color: Color(0xFF8E91A3),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            onPressed: _isUploading
                                ? null
                                : () {
                                    _removeSelectedFile(index);
                                  },
                            icon: const Icon(
                              Icons.close_rounded,
                              color: Color(0xFF9CA3AF),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ],

              if (_isUploading && _totalFilesToUpload > 0) ...[
                const SizedBox(height: 24),

                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF121725),
                    borderRadius: BorderRadius.circular(17),
                    border: Border.all(color: const Color(0xFF292F42)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Uploading documents...',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Text(
                            '$_uploadedFiles/$_totalFilesToUpload',
                            style: const TextStyle(
                              color: Color(0xFFAAA4FF),
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      LinearProgressIndicator(
                        value: _totalFilesToUpload == 0
                            ? 0
                            : _uploadedFiles / _totalFilesToUpload,
                        minHeight: 7,
                        borderRadius: BorderRadius.circular(20),
                        backgroundColor: const Color(0xFF262B3A),
                        color: const Color(0xFF766DFF),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 30),

              SizedBox(
                width: double.infinity,
                height: 58,
                child: ElevatedButton(
                  onPressed: _isUploading ? null : _uploadFile,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF766DFF),
                    disabledBackgroundColor: const Color(0xFF514B8A),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: _isUploading
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Uploading $_uploadedFiles/$_totalFilesToUpload',
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.upload_file_rounded),
                            const SizedBox(width: 9),
                            Text(
                              _selectedFiles.length <= 1
                                  ? 'Upload Document'
                                  : 'Upload ${_selectedFiles.length} Documents',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration({
    required String hint,
    required IconData icon,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFF666A78)),
      prefixIcon: Icon(icon, color: const Color(0xFF8E8C9C)),
      filled: true,
      fillColor: const Color(0xFF121725),
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Color(0xFF242938)),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Color(0xFF242938)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Color(0xFF766DFF), width: 1.4),
      ),
    );
  }
}

class _OrganizationChoice {
  final String id;
  final String name;
  final String type;
  final String uploadPermission;
  final bool isOwner;
  final bool isAdmin;

  const _OrganizationChoice({
    required this.id,
    required this.name,
    required this.type,
    required this.uploadPermission,
    required this.isOwner,
    required this.isAdmin,
  });
}

class _OrganizationPickerTile extends StatelessWidget {
  final _OrganizationChoice organization;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  const _OrganizationPickerTile({
    required this.organization,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? const Color(0xFF24205A) : const Color(0xFF121725),
      borderRadius: BorderRadius.circular(17),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(17),
        child: Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(17),
            border: Border.all(
              color: selected
                  ? const Color(0xFF766DFF)
                  : const Color(0xFF292F42),
            ),
          ),
          child: Row(
            children: [
              const Icon(Icons.apartment_rounded, color: Color(0xFFAAA4FF)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      organization.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      organization.type.isEmpty
                          ? (organization.isOwner ? 'Owner' : 'Member')
                          : '${organization.type} · ${organization.isOwner ? 'Owner' : 'Member'}',
                      style: const TextStyle(
                        color: Color(0xFF8E91A3),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                color: selected
                    ? const Color(0xFFAAA4FF)
                    : const Color(0xFF737B8F),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UploadSourceCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback onTap;

  const _UploadSourceCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.6,
      child: Material(
        color: const Color(0xFF121725),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFF343A4D)),
            ),
            child: Column(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: const Color(0xFF24205A),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: const Color(0xFFAAA4FF), size: 23),
                ),
                const SizedBox(height: 11),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF818596),
                    fontSize: 10.5,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;

  const _SectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
    );
  }
}

class _SpaceCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _SpaceCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF24205A) : const Color(0xFF121725),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? const Color(0xFF766DFF) : const Color(0xFF292F42),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              color: selected
                  ? const Color(0xFFB9B4FF)
                  : const Color(0xFF8E91A3),
              size: 27,
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: const TextStyle(color: Color(0xFF8E91A3), fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _VisibilityOption extends StatelessWidget {
  final String value;
  final String groupValue;
  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final ValueChanged<String> onChanged;

  const _VisibilityOption({
    required this.value,
    required this.groupValue,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final bool selected = value == groupValue;

    return GestureDetector(
      onTap: enabled
          ? () {
              onChanged(value);
            }
          : null,
      child: Opacity(
        opacity: enabled ? 1 : 0.6,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF1B1B3E) : const Color(0xFF121725),
            borderRadius: BorderRadius.circular(17),
            border: Border.all(
              color: selected
                  ? const Color(0xFF766DFF)
                  : const Color(0xFF292F42),
            ),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                color: selected
                    ? const Color(0xFFAAA4FF)
                    : const Color(0xFF7F8292),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Color(0xFF8E91A3),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                selected
                    ? Icons.radio_button_checked_rounded
                    : Icons.radio_button_off_rounded,
                color: selected
                    ? const Color(0xFF938CFF)
                    : const Color(0xFF656879),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
