import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

import '../models/vault_document_model.dart';

class VaultStorageService {
  VaultStorageService._();
  static final VaultStorageService instance = VaultStorageService._();

  static const _folder = 'keeper_secure_vault';
  static const _index = 'vault_index.json';
  static const _keyName = 'keeper_vault_master_key_v1';

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final AesGcm _algorithm = AesGcm.with256bits();

  Future<Directory> _directory() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/$_folder');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  Future<File> _indexFile() async {
    final dir = await _directory();
    return File('${dir.path}/$_index');
  }

  Future<SecretKey> _masterKey() async {
    final saved = await _secureStorage.read(key: _keyName);
    if (saved != null && saved.isNotEmpty) {
      return SecretKey(base64Decode(saved));
    }

    final bytes = Uint8List.fromList(
      List<int>.generate(32, (_) => Random.secure().nextInt(256)),
    );

    await _secureStorage.write(key: _keyName, value: base64Encode(bytes));

    return SecretKey(bytes);
  }

  Future<List<VaultDocumentModel>> getDocuments() async {
    final file = await _indexFile();
    if (!await file.exists()) return [];

    try {
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return [];

      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map(
            (item) => VaultDocumentModel.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _saveIndex(List<VaultDocumentModel> documents) async {
    final file = await _indexFile();
    await file.writeAsString(
      jsonEncode(documents.map((e) => e.toJson()).toList()),
      flush: true,
    );
  }

  Future<VaultDocumentModel> importFile({
    required File sourceFile,
    required String originalFileName,
    required String category,
  }) async {
    if (!await sourceFile.exists()) {
      throw Exception('Selected file is unavailable.');
    }

    final clearBytes = await sourceFile.readAsBytes();
    final key = await _masterKey();
    final nonce = _algorithm.newNonce();

    final encrypted = await _algorithm.encrypt(
      clearBytes,
      secretKey: key,
      nonce: nonce,
    );

    final id =
        '${DateTime.now().microsecondsSinceEpoch}_${Random.secure().nextInt(999999)}';

    final dir = await _directory();
    final encryptedFile = File('${dir.path}/$id.kvr');

    await encryptedFile.writeAsString(
      jsonEncode({
        'nonce': base64Encode(encrypted.nonce),
        'cipherText': base64Encode(encrypted.cipherText),
        'mac': base64Encode(encrypted.mac.bytes),
      }),
      flush: true,
    );

    final extension = originalFileName.contains('.')
        ? originalFileName.split('.').last.toLowerCase()
        : '';

    final document = VaultDocumentModel(
      id: id,
      fileName: originalFileName,
      category: category,
      encryptedPath: encryptedFile.path,
      fileType: extension,
      fileSizeBytes: clearBytes.length,
      createdAt: DateTime.now(),
    );

    final documents = await getDocuments();
    documents.insert(0, document);
    await _saveIndex(documents);

    return document;
  }

  Future<File> decryptToTemporaryFile(VaultDocumentModel document) async {
    final encryptedFile = File(document.encryptedPath);
    if (!await encryptedFile.exists()) {
      throw Exception('Encrypted vault file is missing.');
    }

    final payload = Map<String, dynamic>.from(
      jsonDecode(await encryptedFile.readAsString()) as Map,
    );

    final box = SecretBox(
      base64Decode(payload['cipherText']?.toString() ?? ''),
      nonce: base64Decode(payload['nonce']?.toString() ?? ''),
      mac: Mac(base64Decode(payload['mac']?.toString() ?? '')),
    );

    final clearBytes = await _algorithm.decrypt(
      box,
      secretKey: await _masterKey(),
    );

    final temp = await getTemporaryDirectory();
    final safeName = document.fileName.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

    final output = File('${temp.path}/vault_$safeName');
    await output.writeAsBytes(clearBytes, flush: true);
    return output;
  }

  Future<void> deleteDocument(VaultDocumentModel document) async {
    final encryptedFile = File(document.encryptedPath);
    if (await encryptedFile.exists()) {
      await encryptedFile.delete();
    }

    final documents = await getDocuments();
    documents.removeWhere((item) => item.id == document.id);
    await _saveIndex(documents);
  }

  Future<void> updateDocument({
    required VaultDocumentModel document,
    required String fileName,
    required String category,
  }) async {
    final String cleanName = fileName.trim();
    final String cleanCategory = category.trim();

    if (cleanName.isEmpty) {
      throw ArgumentError('File name cannot be empty.');
    }

    final List<VaultDocumentModel> documents = await getDocuments();

    final int index = documents.indexWhere((item) => item.id == document.id);

    if (index < 0) {
      throw StateError('Vault document was not found.');
    }

    documents[index] = VaultDocumentModel(
      id: document.id,
      fileName: cleanName,
      category: cleanCategory.isEmpty ? 'Personal Files' : cleanCategory,
      encryptedPath: document.encryptedPath,
      fileType: document.fileType,
      fileSizeBytes: document.fileSizeBytes,
      createdAt: document.createdAt,
      isEncrypted: document.isEncrypted,
    );

    await _saveIndex(documents);
  }

  Future<int> getStorageUsedBytes() async {
    final documents = await getDocuments();
    return documents.fold<int>(0, (sum, item) => sum + item.fileSizeBytes);
  }

  Future<void> clearVault() async {
    final dir = await _directory();
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    await dir.create(recursive: true);
    await _secureStorage.delete(key: _keyName);
  }
}
