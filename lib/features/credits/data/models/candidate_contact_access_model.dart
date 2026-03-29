import '../../domain/entities/candidate_contact_access.dart';

class CandidateContactAccessModel extends CandidateContactAccess {
  const CandidateContactAccessModel({
    required super.candidateId,
    required super.hasAccess,
  });

  factory CandidateContactAccessModel.fromJson(Map<String, dynamic> json) {
    return CandidateContactAccessModel(
      candidateId: (json['candidateId'] ?? '').toString(),
      hasAccess: json['hasAccess'] == true,
    );
  }
}
