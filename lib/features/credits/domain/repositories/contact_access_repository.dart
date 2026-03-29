import '../entities/candidate_contact_access.dart';
import '../entities/unlock_contact_result.dart';

abstract class ContactAccessRepository {
  Future<CandidateContactAccess> hasAccessToCandidateContact(
    String candidateId,
  );
  Future<UnlockContactResult> unlockCandidateContact({
    required String candidateId,
    String? candidateName,
    required Object flowContext,
  });
}
