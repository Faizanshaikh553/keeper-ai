class VaultDocumentModel {
  final String id;
  final String fileName;
  final String category;
  final String encryptedPath;
  final String fileType;
  final int fileSizeBytes;
  final DateTime createdAt;
  final bool isEncrypted;

  const VaultDocumentModel({
    required this.id,
    required this.fileName,
    required this.category,
    required this.encryptedPath,
    required this.fileType,
    required this.fileSizeBytes,
    required this.createdAt,
    this.isEncrypted = true,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'fileName': fileName,
    'category': category,
    'encryptedPath': encryptedPath,
    'fileType': fileType,
    'fileSizeBytes': fileSizeBytes,
    'createdAt': createdAt.toIso8601String(),
    'isEncrypted': isEncrypted,
  };

  factory VaultDocumentModel.fromJson(Map<String, dynamic> json) {
    return VaultDocumentModel(
      id: json['id']?.toString() ?? '',
      fileName: json['fileName']?.toString() ?? 'Vault file',
      category: json['category']?.toString() ?? 'Others',
      encryptedPath: json['encryptedPath']?.toString() ?? '',
      fileType: json['fileType']?.toString() ?? '',
      fileSizeBytes: (json['fileSizeBytes'] as num?)?.toInt() ?? 0,
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
      isEncrypted: json['isEncrypted'] as bool? ?? true,
    );
  }
}
