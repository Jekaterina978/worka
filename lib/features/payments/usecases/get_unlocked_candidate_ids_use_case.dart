import '../contact_access_controller.dart';

class GetUnlockedCandidateIdsUseCase {
  GetUnlockedCandidateIdsUseCase({ContactAccessController? controller})
    : _controller = controller ?? ContactAccessController.instance;

  final ContactAccessController _controller;

  Future<Set<String>> call({String? uid}) {
    return _controller.getUnlockedCandidateIds(uid: uid);
  }
}
