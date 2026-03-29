import '../entities/candidate_contact_access.dart';
import '../repositories/contact_access_repository.dart';

class HasAccessToCandidateContact {
  final ContactAccessRepository repository;
  const HasAccessToCandidateContact(this.repository);

  Future<CandidateContactAccess> call(String candidateId) {
    return repository.hasAccessToCandidateContact(candidateId);
  }
}
