import '../models/vault_document_model.dart';

class VaultSearchService {
  // Search by File Name

  List<VaultDocumentModel> searchByName(
    List<VaultDocumentModel> files,
    String query,
  ) {
    return files.where((file) {
      return file.fileName.toLowerCase().contains(query.toLowerCase());
    }).toList();
  }

  // Search by Category

  List<VaultDocumentModel> searchByCategory(
    List<VaultDocumentModel> files,
    String category,
  ) {
    return files.where((file) {
      return file.category == category;
    }).toList();
  }

  // Search by File Type

  List<VaultDocumentModel> searchByFileType(
    List<VaultDocumentModel> files,
    String type,
  ) {
    return files.where((file) {
      return file.fileType == type;
    }).toList();
  }

  // Total Search

  List<VaultDocumentModel> searchFiles(
    List<VaultDocumentModel> files,
    String query,
  ) {
    return files.where((file) {
      return file.fileName.toLowerCase().contains(query.toLowerCase()) ||
          file.category.toLowerCase().contains(query.toLowerCase()) ||
          file.fileType.toLowerCase().contains(query.toLowerCase());
    }).toList();
  }
}
