import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/vault_biometric_service.dart';
import '../services/vault_security_service.dart';

class VaultLockScreen extends StatefulWidget {
  const VaultLockScreen({super.key});

  @override
  State<VaultLockScreen> createState() => _VaultLockScreenState();
}

class _VaultLockScreenState extends State<VaultLockScreen> {
  final TextEditingController _pinController = TextEditingController();
  final TextEditingController _confirmPinController = TextEditingController();

  final VaultSecurityService _security = VaultSecurityService.instance;
  final VaultBiometricService _biometric = VaultBiometricService();

  bool _isLoading = true;
  bool _isProcessing = false;
  bool _hasPin = false;
  bool _biometricAvailable = false;
  bool _biometricEnabled = false;
  bool _obscurePin = true;
  bool _isCompleting = false;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void dispose() {
    _pinController.dispose();
    _confirmPinController.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _finishUnlock() async {
    if (_isCompleting || !mounted) return;

    _isCompleting = true;

    // Let the current frame and any biometric/dialog route finish first.
    await Future<void>.delayed(const Duration(milliseconds: 120));

    if (!mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final NavigatorState navigator = Navigator.of(context);
      if (navigator.canPop()) {
        navigator.pop(true);
      }
    });
  }

  Future<void> _initialize() async {
    try {
      final bool hasPin = await _security.hasPin();
      final bool supported = await _biometric.isBiometricSupported();
      final bool canCheck = await _biometric.canCheckBiometrics();
      final bool enabled = await _security.isBiometricEnabled();

      if (!mounted) return;

      setState(() {
        _hasPin = hasPin;
        _biometricAvailable = supported && canCheck;
        _biometricEnabled = supported && canCheck && enabled;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      _showMessage('Unable to initialize Vault security.');
    }
  }

  Future<void> _createPin() async {
    final String pin = _pinController.text.trim();
    final String confirmPin = _confirmPinController.text.trim();

    if (!_security.isValidPinFormat(pin)) {
      _showMessage('Enter a 6-digit Vault PIN.');
      return;
    }

    if (pin != confirmPin) {
      _showMessage('PIN confirmation does not match.');
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      await _security.createPin(pin);
      await _security.setBiometricEnabled(
        _biometricAvailable && _biometricEnabled,
      );

      if (!mounted) return;
      await _finishUnlock();
    } catch (error) {
      _showMessage('Unable to create Vault PIN: $error');
    } finally {
      if (mounted && !_isCompleting) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _unlockWithPin() async {
    final String pin = _pinController.text.trim();

    if (!_security.isValidPinFormat(pin)) {
      _showMessage('Enter your 6-digit Vault PIN.');
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      final bool valid = await _security.verifyPin(pin);

      if (!mounted) return;

      if (!valid) {
        _showMessage(
          'Incorrect PIN. Reset it using your signed-in Keeper account if needed.',
        );
        return;
      }

      await _finishUnlock();
    } catch (error) {
      _showMessage('Unable to unlock Personal Vault: $error');
    } finally {
      if (mounted && !_isCompleting) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _unlockWithBiometric() async {
    if (!_biometricAvailable || _isProcessing) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      final bool authenticated = await _biometric.authenticateUser();

      if (!mounted) return;

      if (!authenticated) {
        _showMessage(
          _biometric.lastError ?? 'Biometric authentication was not completed.',
        );
        return;
      }

      _security.unlockAfterBiometric();
      await _finishUnlock();
    } finally {
      if (mounted && !_isCompleting) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Future<bool> _confirmSignedInAccount() async {
    final User? user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      _showMessage(
        'Sign in to your Keeper account before resetting the Vault PIN.',
      );
      return false;
    }

    try {
      await user.reload();
      await user.getIdToken(true);
    } catch (_) {
      _showMessage(
        'Your login session could not be verified. Sign in again and retry.',
      );
      return false;
    }

    if (!mounted) return false;

    final String account = user.email?.trim().isNotEmpty == true
        ? user.email!
        : 'your current Keeper account';

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF151B2A),
          title: const Text(
            'Verify Keeper account',
            style: TextStyle(color: Colors.white),
          ),
          content: Text(
            'Reset the Vault PIN using the signed-in account:\n\n$account\n\nYour encrypted files will not be deleted.',
            style: const TextStyle(color: Color(0xFFB8BBC7), height: 1.45),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Verify & Reset'),
            ),
          ],
        );
      },
    );

    return confirmed == true;
  }

  Future<void> _resetPin() async {
    if (_isProcessing) return;

    final bool verified = await _confirmSignedInAccount();

    if (!verified || !mounted) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      await _security.resetVaultSecurity();

      if (!mounted) return;

      _pinController.clear();
      _confirmPinController.clear();

      setState(() {
        _hasPin = false;
        _biometricEnabled = false;
      });

      _showMessage('Account verified. Create a new 6-digit Vault PIN.');
    } catch (error) {
      _showMessage('Unable to reset Vault PIN: $error');
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  InputDecoration _pinDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: Color(0xFF9CA3AF)),
      prefixIcon: const Icon(Icons.password_rounded, color: Color(0xFFAAA4FF)),
      suffixIcon: IconButton(
        onPressed: () {
          setState(() {
            _obscurePin = !_obscurePin;
          });
        },
        icon: Icon(
          _obscurePin ? Icons.visibility_off_rounded : Icons.visibility_rounded,
          color: const Color(0xFF8E91A3),
        ),
      ),
      filled: true,
      fillColor: const Color(0xFF121725),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(17)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(17),
        borderSide: const BorderSide(color: Color(0xFF292F42)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(17),
        borderSide: const BorderSide(color: Color(0xFF766DFF)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_isProcessing,
      child: Scaffold(
        backgroundColor: const Color(0xFF090D18),
        appBar: AppBar(
          backgroundColor: const Color(0xFF090D18),
          foregroundColor: Colors.white,
          elevation: 0,
          title: Text(
            _hasPin ? 'Unlock Personal Vault' : 'Secure Personal Vault',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ),
        body: _isLoading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFF766DFF)),
              )
            : SafeArea(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(22, 22, 22, 30),
                  children: [
                    Center(
                      child: Container(
                        width: 96,
                        height: 96,
                        decoration: const BoxDecoration(
                          color: Color(0xFF24205A),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _hasPin
                              ? Icons.lock_rounded
                              : Icons.enhanced_encryption_rounded,
                          size: 48,
                          color: const Color(0xFFAAA4FF),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text(
                      _hasPin
                          ? 'Enter your Vault PIN'
                          : 'Create a 6-digit Vault PIN',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 23,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 9),
                    Text(
                      _hasPin
                          ? 'Your encrypted local files stay locked until you authenticate.'
                          : 'This PIN protects files stored inside Keeper’s encrypted local vault.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF9CA3AF),
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 28),
                    TextField(
                      controller: _pinController,
                      enabled: !_isProcessing,
                      autofocus: true,
                      obscureText: _obscurePin,
                      keyboardType: TextInputType.number,
                      textInputAction: _hasPin
                          ? TextInputAction.done
                          : TextInputAction.next,
                      maxLength: 6,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(6),
                      ],
                      onSubmitted: (_) {
                        if (_hasPin) {
                          _unlockWithPin();
                        }
                      },
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        letterSpacing: 8,
                      ),
                      decoration: _pinDecoration(
                        _hasPin ? 'Vault PIN' : 'Create PIN',
                      ).copyWith(counterText: ''),
                    ),
                    if (!_hasPin) ...[
                      const SizedBox(height: 15),
                      TextField(
                        controller: _confirmPinController,
                        enabled: !_isProcessing,
                        obscureText: _obscurePin,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        maxLength: 6,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(6),
                        ],
                        onSubmitted: (_) => _createPin(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          letterSpacing: 8,
                        ),
                        decoration: _pinDecoration(
                          'Confirm PIN',
                        ).copyWith(counterText: ''),
                      ),
                    ],
                    if (!_hasPin && _biometricAvailable) ...[
                      const SizedBox(height: 12),
                      SwitchListTile(
                        value: _biometricEnabled,
                        onChanged: _isProcessing
                            ? null
                            : (value) {
                                setState(() {
                                  _biometricEnabled = value;
                                });
                              },
                        activeThumbColor: const Color(0xFFAAA4FF),
                        title: const Text(
                          'Enable biometric unlock',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        subtitle: const Text(
                          'Use fingerprint or face authentication.',
                          style: TextStyle(color: Color(0xFF8E91A3)),
                        ),
                      ),
                    ],
                    const SizedBox(height: 22),
                    SizedBox(
                      height: 54,
                      child: ElevatedButton.icon(
                        onPressed: _isProcessing
                            ? null
                            : (_hasPin ? _unlockWithPin : _createPin),
                        icon: _isProcessing
                            ? const SizedBox(
                                width: 19,
                                height: 19,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : Icon(
                                _hasPin
                                    ? Icons.lock_open_rounded
                                    : Icons.shield_rounded,
                              ),
                        label: Text(
                          _hasPin ? 'Unlock Vault' : 'Create Secure Vault',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF766DFF),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(17),
                          ),
                        ),
                      ),
                    ),
                    if (_hasPin &&
                        _biometricAvailable &&
                        _biometricEnabled) ...[
                      const SizedBox(height: 13),
                      OutlinedButton.icon(
                        onPressed: _isProcessing ? null : _unlockWithBiometric,
                        icon: const Icon(Icons.fingerprint_rounded),
                        label: const Text('Use biometric unlock'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFAAA4FF),
                          minimumSize: const Size.fromHeight(52),
                          side: const BorderSide(color: Color(0xFF5147E5)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(17),
                          ),
                        ),
                      ),
                    ],
                    if (_hasPin) ...[
                      const SizedBox(height: 13),
                      TextButton(
                        onPressed: _isProcessing ? null : _resetPin,
                        child: const Text(
                          'Reset Vault PIN using Keeper account',
                          style: TextStyle(
                            color: Color(0xFFFF8FA3),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.cloud_off_rounded,
                          color: Color(0xFF6FCF97),
                          size: 17,
                        ),
                        SizedBox(width: 7),
                        Flexible(
                          child: Text(
                            'Local only • No AI access • No cloud sync',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Color(0xFF8E91A3),
                              fontSize: 11,
                            ),
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
}
