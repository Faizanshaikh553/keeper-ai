import 'dart:io';

import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../models/vault_document_model.dart';
import 'vault_storage_service.dart';

/// Actions for files stored inside Personal Vault.
///
/// Files are decrypted only into the app's temporary directory for the
/// duration of the requested action. The encrypted vault copy is never shared
/// directly.
class VaultFileActionService {
  VaultFileActionService._();

  static final VaultFileActionService instance = VaultFileActionService._();

  static const MethodChannel _platform = MethodChannel(
    'com.faizan.keeperai/keeper_live',
  );

  Future<void> share(VaultDocumentModel document) async {
    final File temporaryFile = await VaultStorageService.instance
        .decryptToTemporaryFile(document);

    try {
      await SharePlus.instance.share(
        ShareParams(
          text: 'Shared from Keeper Personal Vault',
          subject: document.fileName,
          files: [XFile(temporaryFile.path, mimeType: mimeTypeFor(document))],
        ),
      );
    } finally {
      await _deleteTemporaryFile(temporaryFile);
    }
  }

  Future<bool> print(VaultDocumentModel document) async {
    final File temporaryFile = await VaultStorageService.instance
        .decryptToTemporaryFile(document);

    try {
      final bool started =
          await _platform.invokeMethod<bool>('printVaultFile', <String, dynamic>{
            'path': temporaryFile.path,
            'fileName': document.fileName,
            'mimeType': mimeTypeFor(document),
          }) ??
          false;

      if (!started) {
        await _deleteTemporaryFile(temporaryFile);
      }

      // When printing starts, Android owns the temporary file until the
      // PrintDocumentAdapter finishes. It deletes the file in onFinish().
      return started;
    } catch (_) {
      await _deleteTemporaryFile(temporaryFile);
      rethrow;
    }
  }

  static String mimeTypeFor(VaultDocumentModel document) {
    final String type = document.fileType.toLowerCase();

    switch (type) {
      case 'pdf':
        return 'application/pdf';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'heic':
        return 'image/heic';
      case 'txt':
        return 'text/plain';
      case 'csv':
        return 'text/csv';
      case 'json':
        return 'application/json';
      case 'md':
        return 'text/markdown';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return
            'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'rtf':
        return 'application/rtf';
      case 'mp3':
        return 'audio/mpeg';
      case 'wav':
        return 'audio/wav';
      case 'm4a':
        return 'audio/mp4';
      default:
        return 'application/octet-stream';
    }
  }

  static Future<void> _deleteTemporaryFile(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }
}
