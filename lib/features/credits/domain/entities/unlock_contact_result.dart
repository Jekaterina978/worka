enum UnlockContactStatus {
  unlocked,
  alreadyUnlocked,
  cancelled,
  pending,
  failed,
}

enum UnlockContactPhase {
  alreadyUnlocked,
  paymentConfirmed,
  walletSyncPending,
  walletSynced,
  unlockRetryPending,
  unlockCompleted,
  unlockFailedAfterStabilization,
}

class UnlockContactResult {
  final UnlockContactStatus status;
  final int creditsLeft;
  final String message;
  final UnlockContactPhase phase;
  final bool recentPurchase;

  const UnlockContactResult({
    required this.status,
    this.creditsLeft = 0,
    this.message = '',
    this.phase = UnlockContactPhase.unlockCompleted,
    this.recentPurchase = false,
  });

  bool get success =>
      status == UnlockContactStatus.unlocked ||
      status == UnlockContactStatus.alreadyUnlocked;
}
