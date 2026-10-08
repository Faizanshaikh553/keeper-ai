import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';

class VaultSecurityService {
  VaultSecurityService._();

  static final VaultSecurityService instance = VaultSecurityService._();

  static const String _pinHashKey = 'keeper_vault_pin_hash_v2';
  static const String _legacyPinHashKey = 'keeper_vault_pin_hash_v1';
  static const String _biometricEnabledKey =
      'keeper_vault_biometric_enabled_v2';
  static const String _legacyBiometricEnabledKey =
      'keeper_vault_biometric_enabled_v1';
  static const String _securityFileName = 'keeper_vault_security_v2.json';

  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();
  final Sha256 _sha256 = Sha256();

  bool _isUnlocked = false;

  bool get isUnlocked => _isUnlocked;

  Future<File> _securityFile() async {
    final Directory directory = await getApplicationSupportDirectory();

    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    return File('${directory.path}/$_securityFileName');
  }

  Future<Map<String, dynamic>> _readFileData() async {
    try {
      final File file = await _securityFile();

      if (!await file.exists()) {
        return <String, dynamic>{};
      }

      final String raw = await file.readAsString();

      if (raw.trim().isEmpty) {
        return <String, dynamic>{};
      }

      final Object? decoded = jsonDecode(raw);

      if (decoded is! Map) {
        return <String, dynamic>{};
      }

      return Map<String, dynamic>.from(decoded);
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  Future<void> _writeFileData(Map<String, dynamic> data) async {
    final File file = await _securityFile();

    await file.writeAsString(jsonEncode(data), flush: true);
  }

  Future<String?> _readSecure(String key) async {
    try {
      return await _secureStorage.read(key: key);
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeSecure(String key, String value) async {
    try {
      await _secureStorage.write(key: key, value: value);
    } catch (_) {
      // The app-private security file remains the reliable source.
    }
  }

  Future<void> _deleteSecure(String key) async {
    try {
      await _secureStorage.delete(key: key);
    } catch (_) {
      // Continue clearing app-private data.
    }
  }

  Future<String> _hashPin(String pin) async {
    final Hash hash = await _sha256.hash(utf8.encode(pin));

    return base64Encode(hash.bytes);
  }

  bool isValidPinFormat(String pin) {
    return RegExp(r'^\d{6}$').hasMatch(pin);
  }

  Future<String?> _storedPinHash() async {
    final Map<String, dynamic> fileData = await _readFileData();

    final String fileHash = fileData[_pinHashKey]?.toString() ?? '';

    if (fileHash.isNotEmpty) {
      return fileHash;
    }

    final String secureHash = (await _readSecure(_pinHashKey)) ?? '';

    if (secureHash.isNotEmpty) {
      fileData[_pinHashKey] = secureHash;
      await _writeFileData(fileData);
      return secureHash;
    }

    final String legacyHash = (await _readSecure(_legacyPinHashKey)) ?? '';

    if (legacyHash.isNotEmpty) {
      fileData[_pinHashKey] = legacyHash;
      await _writeFileData(fileData);
      await _writeSecure(_pinHashKey, legacyHash);
      return legacyHash;
    }

    return null;
  }

  Future<bool> hasPin() async {
    final String? hash = await _storedPinHash();
    return hash != null && hash.isNotEmpty;
  }

  Future<void> createPin(String pin) async {
    if (!isValidPinFormat(pin)) {
      throw ArgumentError('Vault PIN must contain exactly 6 digits.');
    }

    final String hash = await _hashPin(pin);
    final Map<String, dynamic> fileData = await _readFileData();

    fileData[_pinHashKey] = hash;
    await _writeFileData(fileData);
    await _writeSecure(_pinHashKey, hash);

    final String? verificationHash = await _storedPinHash();

    if (verificationHash != hash) {
      throw StateError('Vault PIN could not be saved.');
    }

    _isUnlocked = true;
  }

  Future<bool> verifyPin(String pin) async {
    if (!isValidPinFormat(pin)) return false;

    try {
      final String? storedHash = await _storedPinHash();

      if (storedHash == null || storedHash.isEmpty) {
        return false;
      }

      final String enteredHash = await _hashPin(pin);
      final bool valid = storedHash == enteredHash;

      if (valid) {
        _isUnlocked = true;
      }

      return valid;
    } catch (_) {
      return false;
    }
  }

  Future<void> setBiometricEnabled(bool enabled) async {
    final String value = enabled.toString();
    final Map<String, dynamic> fileData = await _readFileData();

    fileData[_biometricEnabledKey] = value;
    await _writeFileData(fileData);
    await _writeSecure(_biometricEnabledKey, value);
  }

  Future<bool> isBiometricEnabled() async {
    final Map<String, dynamic> fileData = await _readFileData();

    final String fileValue = fileData[_biometricEnabledKey]?.toString() ?? '';

    if (fileValue.isNotEmpty) {
      return fileValue == 'true';
    }

    final String secureValue =
        (await _readSecure(_biometricEnabledKey)) ??
        (await _readSecure(_legacyBiometricEnabledKey)) ??
        '';

    if (secureValue.isNotEmpty) {
      fileData[_biometricEnabledKey] = secureValue;
      await _writeFileData(fileData);
      return secureValue == 'true';
    }

    return false;
  }

  void unlockAfterBiometric() {
    _isUnlocked = true;
  }

  void lockVault() {
    _isUnlocked = false;
  }

  Future<void> resetVaultSecurity() async {
    final Map<String, dynamic> fileData = await _readFileData();

    fileData.remove(_pinHashKey);
    fileData.remove(_biometricEnabledKey);
    await _writeFileData(fileData);

    await _deleteSecure(_pinHashKey);
    await _deleteSecure(_legacyPinHashKey);
    await _deleteSecure(_biometricEnabledKey);
    await _deleteSecure(_legacyBiometricEnabledKey);

    _isUnlocked = false;
  }
}
