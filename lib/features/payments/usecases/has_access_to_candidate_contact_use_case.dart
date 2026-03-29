import '../contact_access_controller.dart';
import '../domain/models/credits_models.dart';

class HasAccessToCandidateContactUseCase {
  HasAccessToCandidateContactUseCase({ContactAccessController? controller})
    : _controller = controller ?? ContactAccessController.instance;

  final ContactAccessController _controller;

  CandidateContactAccess call(String candidateId) {
    final has = _controller.hasAccessToCandidateContact(candidateId);
    return CandidateContactAccess(
      candidateId: candidateId.trim(),
      hasAccess: has,
      unlockedPermanently: has,
      checkedAt: DateTime.now(),
    );
  }
}
