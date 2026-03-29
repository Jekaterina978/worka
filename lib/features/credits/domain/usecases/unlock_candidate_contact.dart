import '../entities/unlock_contact_result.dart';
import '../repositories/contact_access_repository.dart';

class UnlockCandidateContact {
  final ContactAccessRepository repository;
  const UnlockCandidateContact(this.repository);

  Future<UnlockContactResult> call({
    required String candidateId,
    String? candidateName,
    required Object flowContext,
  }) {
    return repository.unlockCandidateContact(
      candidateId: candidateId,
      candidateName: candidateName,
      flowContext: flowContext,
    );
  }
}
