import 'package:flutter/material.dart';
import 'package:worka/features/payments/contact_access_controller.dart';

import '../../domain/entities/candidate_contact_access.dart';
import '../../domain/entities/unlock_contact_result.dart';
import '../../domain/repositories/contact_access_repository.dart';

class ContactAccessRepositoryImpl implements ContactAccessRepository {
  final ContactAccessController _controller;

  ContactAccessRepositoryImpl({ContactAccessController? controller})
    : _controller = controller ?? ContactAccessController.instance;

  @override
  Future<CandidateContactAccess> hasAccessToCandidateContact(
    String candidateId,
  ) async {
    final hasAccess = await _controller.syncHasAccessToCandidateContact(
      candidateId,
    );
    return CandidateContactAccess(
      candidateId: candidateId.trim(),
      hasAccess: hasAccess,
    );
  }

  @override
  Future<UnlockContactResult> unlockCandidateContact({
    required String candidateId,
    String? candidateName,
    required Object flowContext,
  }) async {
    final context = flowContext as BuildContext;
    final result = await _controller.unlockCandidateContact(
      context,
      candidateId: candidateId,
      candidateName: candidateName,
    );

    final phase = _mapPhase(result);
    final status = switch (result.status) {
      ContactUnlockStatus.unlocked => UnlockContactStatus.unlocked,
      ContactUnlockStatus.alreadyUnlocked =>
        UnlockContactStatus.alreadyUnlocked,
      ContactUnlockStatus.cancelled => UnlockContactStatus.cancelled,
      ContactUnlockStatus.purchasePending => UnlockContactStatus.pending,
      ContactUnlockStatus.failed => UnlockContactStatus.failed,
    };

    return UnlockContactResult(
      status: status,
      creditsLeft: result.creditsLeft,
      message: _mapMessage(result, phase: phase, coarseStatus: status),
      phase: phase,
      recentPurchase: result.recentPurchase,
    );
  }

  UnlockContactPhase _mapPhase(ContactUnlockResult result) {
    final stage = result.stabilizationStage.trim();
    switch (stage) {
      case 'already_unlocked':
      case 'already_unlocked_during_stabilization':
        return UnlockContactPhase.alreadyUnlocked;
      case 'wallet_sync_pending':
        return UnlockContactPhase.walletSyncPending;
      case 'unlock_retry_pending':
        return UnlockContactPhase.unlockRetryPending;
      case 'unlock_completed':
      case 'unlock_completed_after_retry':
        return UnlockContactPhase.unlockCompleted;
      case 'unlock_failed':
        return UnlockContactPhase.unlockFailedAfterStabilization;
      default:
        switch (result.status) {
          case ContactUnlockStatus.alreadyUnlocked:
            return UnlockContactPhase.alreadyUnlocked;
          case ContactUnlockStatus.unlocked:
            return UnlockContactPhase.unlockCompleted;
          case ContactUnlockStatus.purchasePending:
            return result.recentPurchase
                ? UnlockContactPhase.paymentConfirmed
                : UnlockContactPhase.unlockRetryPending;
          case ContactUnlockStatus.failed:
            return UnlockContactPhase.unlockFailedAfterStabilization;
          case ContactUnlockStatus.cancelled:
            return result.recentPurchase
                ? UnlockContactPhase.paymentConfirmed
                : UnlockContactPhase.walletSynced;
        }
    }
  }

  String _mapMessage(
    ContactUnlockResult result, {
    required UnlockContactPhase phase,
    required UnlockContactStatus coarseStatus,
  }) {
    final original = result.message.trim();
    if (original.isNotEmpty &&
        phase != UnlockContactPhase.walletSyncPending &&
        phase != UnlockContactPhase.unlockRetryPending) {
      return original;
    }

    switch (phase) {
      case UnlockContactPhase.walletSyncPending:
        return 'Платёж подтверждён, ждём обновления кошелька';
      case UnlockContactPhase.unlockRetryPending:
        return 'Кошелёк обновлён, повторяем открытие контакта';
      case UnlockContactPhase.unlockFailedAfterStabilization:
        return original.isNotEmpty
            ? original
            : 'Оплата прошла, но контакт ещё не открылся. Попробуйте снова.';
      case UnlockContactPhase.alreadyUnlocked:
      case UnlockContactPhase.paymentConfirmed:
      case UnlockContactPhase.walletSynced:
      case UnlockContactPhase.unlockCompleted:
        return original;
    }
  }
}
