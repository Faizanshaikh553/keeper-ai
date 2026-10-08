import 'dart:async';

class VaultLockService {
  Timer? _autoLockTimer;

  bool _isVaultUnlocked = false;

  // Unlock Vault

  void unlockVault() {
    _isVaultUnlocked = true;
    startAutoLockTimer();
  }

  // Lock Vault

  void lockVault() {
    _isVaultUnlocked = false;
    _autoLockTimer?.cancel();
  }

  // Check Status

  bool isVaultUnlocked() {
    return _isVaultUnlocked;
  }

  // Auto Lock Timer
  // Currently 5 Minutes

  void startAutoLockTimer() {
    _autoLockTimer?.cancel();

    _autoLockTimer = Timer(const Duration(minutes: 5), () {
      lockVault();
    });
  }

  // Reset Timer

  void resetTimer() {
    if (_isVaultUnlocked) {
      startAutoLockTimer();
    }
  }

  // Lock when App goes Background

  void lockOnBackground() {
    lockVault();
  }

  // Lock when User exits Vault

  void lockOnExit() {
    lockVault();
  }

  // Dispose Timer

  void dispose() {
    _autoLockTimer?.cancel();
  }
}
