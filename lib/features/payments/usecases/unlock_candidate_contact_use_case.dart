import 'package:flutter/material.dart';

import '../contact_access_controller.dart';

class UnlockCandidateContactUseCase {
  UnlockCandidateContactUseCase({ContactAccessController? controller})
    : _controller = controller ?? ContactAccessController.instance;

  final ContactAccessController _controller;

  Future<ContactUnlockResult> call(
    BuildContext context, {
    required String candidateId,
    String? candidateName,
    String entryPoint = 'unknown',
  }) {
    return _controller.ensureContactUnlocked(
      context,
      candidateId: candidateId,
      candidateName: candidateName,
      entryPoint: entryPoint,
    );
  }
}
