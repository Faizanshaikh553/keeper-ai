import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

class VaultBiometricService {
  final LocalAuthentication _auth = LocalAuthentication();

  String? lastError;

  Future<bool> isBiometricSupported() async {
    try {
      return await _auth.isDeviceSupported();
    } catch (error) {
      lastError = error.toString();
      return false;
    }
  }

  Future<bool> canCheckBiometrics() async {
    try {
      return await _auth.canCheckBiometrics;
    } catch (error) {
      lastError = error.toString();
      return false;
    }
  }

  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _auth.getAvailableBiometrics();
    } catch (error) {
      lastError = error.toString();
      return const <BiometricType>[];
    }
  }

  Future<bool> authenticateUser() async {
    lastError = null;

    try {
      final bool supported = await _auth.isDeviceSupported();
      final bool canCheck = await _auth.canCheckBiometrics;
      final List<BiometricType> available = await _auth
          .getAvailableBiometrics();

      if (!supported || !canCheck || available.isEmpty) {
        lastError =
            'Fingerprint or face unlock is not enrolled on this device.';
        return false;
      }

      return await _auth.authenticate(
        localizedReason: 'Authenticate to unlock your Personal Vault.',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
          useErrorDialogs: true,
        ),
      );
    } on PlatformException catch (error) {
      lastError = error.message ?? error.code;
      return false;
    } catch (error) {
      lastError = error.toString();
      return false;
    }
  }
}
