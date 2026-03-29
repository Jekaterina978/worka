import 'package:flutter/material.dart';

import '../../data/repositories/contact_access_repository_impl.dart';
import '../../domain/entities/unlock_contact_result.dart';
import '../../domain/usecases/has_access_to_candidate_contact.dart';
import '../../domain/usecases/unlock_candidate_contact.dart';

class UnlockContactFlowController {
  UnlockContactFlowController({
    HasAccessToCandidateContact? hasAccessToCandidateContact,
    UnlockCandidateContact? unlockCandidateContact,
  }) : _hasAccessToCandidateContact =
           hasAccessToCandidateContact ??
           HasAccessToCandidateContact(ContactAccessRepositoryImpl()),
       _unlockCandidateContact =
           unlockCandidateContact ??
           UnlockCandidateContact(ContactAccessRepositoryImpl());

  final HasAccessToCandidateContact _hasAccessToCandidateContact;
  final UnlockCandidateContact _unlockCandidateContact;

  Future<UnlockContactResult> unlock(
    BuildContext context, {
    required String candidateId,
    String? candidateName,
  }) async {
    final access = await _hasAccessToCandidateContact(candidateId);
    if (access.hasAccess) {
      return const UnlockContactResult(
        status: UnlockContactStatus.alreadyUnlocked,
        phase: UnlockContactPhase.alreadyUnlocked,
      );
    }
    if (!context.mounted) {
      return const UnlockContactResult(
        status: UnlockContactStatus.cancelled,
        phase: UnlockContactPhase.walletSynced,
      );
    }
    return _unlockCandidateContact(
      candidateId: candidateId,
      candidateName: candidateName,
      flowContext: context,
    );
  }
}
