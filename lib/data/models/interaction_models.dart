import 'package:cloud_firestore/cloud_firestore.dart';

enum InteractionStatusValue { sent, viewed, accepted, rejected, postponed }

extension InteractionStatusValueX on InteractionStatusValue {
  String get wire {
    switch (this) {
      case InteractionStatusValue.sent:
        return 'sent';
      case InteractionStatusValue.viewed:
        return 'viewed';
      case InteractionStatusValue.accepted:
        return 'accepted';
      case InteractionStatusValue.rejected:
        return 'rejected';
      case InteractionStatusValue.postponed:
        return 'postponed';
    }
  }
}

class ApplicationCreate {
  final String vacancyId;
  final String vacancyOwnerId;
  final String vacancyOwnerType;
  final String candidateId;
  final String cvId;
  /// Profile type of the applicant at the time of sending ('personal'/'business').
  final String applicantProfileType;
  final String applicantNameSnapshot;
  final String applicantEmailSnapshot;
  final String applicantPhoneSnapshot;
  final String cvTitleSnapshot;
  final String cvLocationSnapshot;
  final String cvCategorySnapshot;
  final List<String> cvSkillsSnapshot;
  final Map<String, dynamic> vacancySnapshot;
  final Map<String, dynamic> candidateSnapshot;

  const ApplicationCreate({
    required this.vacancyId,
    required this.vacancyOwnerId,
    this.vacancyOwnerType = 'personal',
    required this.candidateId,
    required this.cvId,
    this.applicantProfileType = 'personal',
    this.applicantNameSnapshot = '',
    this.applicantEmailSnapshot = '',
    this.applicantPhoneSnapshot = '',
    this.cvTitleSnapshot = '',
    this.cvLocationSnapshot = '',
    this.cvCategorySnapshot = '',
    this.cvSkillsSnapshot = const <String>[],
    this.vacancySnapshot = const <String, dynamic>{},
    this.candidateSnapshot = const <String, dynamic>{},
  });

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'type': 'apply',
      'vacancyId': vacancyId,
      'vacancyOwnerId': vacancyOwnerId,
      'vacancyOwnerType': vacancyOwnerType,
      'candidateId': candidateId,
      'candidateOwnerId': candidateId,
      'cvId': cvId,
      'applicantProfileType': applicantProfileType,
      // Flattened snapshots for easy display in letter without extra reads.
      'applicantNameSnapshot': applicantNameSnapshot,
      'applicantEmailSnapshot': applicantEmailSnapshot,
      'applicantPhoneSnapshot': applicantPhoneSnapshot,
      'cvTitleSnapshot': cvTitleSnapshot,
      'cvLocationSnapshot': cvLocationSnapshot,
      'cvCategorySnapshot': cvCategorySnapshot,
      'cvSkillsSnapshot': cvSkillsSnapshot,
      'status': InteractionStatusValue.sent.wire,
      'statusEmployer': InteractionStatusValue.sent.wire,
      'statusCandidate': InteractionStatusValue.sent.wire,
      'isNew': true,
      'unreadForEmployer': true,
      'unreadForCandidate': false,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'vacancySnapshot': vacancySnapshot,
      'candidateSnapshot': candidateSnapshot,
    };
  }
}

class OfferCreate {
  final String vacancyId;
  final String vacancyOwnerId;
  final String vacancyOwnerType;
  final String candidateId;
  final String cvId;
  final String employerType;
  /// Profile type of the offer recipient (candidate). Always 'personal' since CVs are private.
  final String recipientProfileType;
  // Flattened CV snapshots for letter display resilience.
  final String cvTitleSnapshot;
  final String cvLocationSnapshot;
  final String cvCategorySnapshot;
  final List<String> cvSkillsSnapshot;
  final String candidateNameSnapshot;
  final String candidateEmailSnapshot;
  final String candidatePhoneSnapshot;
  final Map<String, dynamic> vacancySnapshot;
  final Map<String, dynamic> candidateSnapshot;
  final Map<String, dynamic> employerContactsSnapshot;

  const OfferCreate({
    required this.vacancyId,
    required this.vacancyOwnerId,
    this.vacancyOwnerType = 'personal',
    required this.candidateId,
    required this.cvId,
    this.employerType = 'personal',
    this.recipientProfileType = 'personal',
    this.cvTitleSnapshot = '',
    this.cvLocationSnapshot = '',
    this.cvCategorySnapshot = '',
    this.cvSkillsSnapshot = const <String>[],
    this.candidateNameSnapshot = '',
    this.candidateEmailSnapshot = '',
    this.candidatePhoneSnapshot = '',
    this.vacancySnapshot = const <String, dynamic>{},
    this.candidateSnapshot = const <String, dynamic>{},
    this.employerContactsSnapshot = const <String, dynamic>{},
  });

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'type': 'offer',
      'vacancyId': vacancyId,
      'vacancyOwnerId': vacancyOwnerId,
      'vacancyOwnerType': vacancyOwnerType,
      'employerId': vacancyOwnerId,
      'employerType': employerType,
      'candidateId': candidateId,
      'candidateOwnerId': candidateId,
      'cvId': cvId,
      'recipientProfileType': recipientProfileType,
      // Flattened snapshots for easy display in letter without extra reads.
      'cvTitleSnapshot': cvTitleSnapshot,
      'cvLocationSnapshot': cvLocationSnapshot,
      'cvCategorySnapshot': cvCategorySnapshot,
      'cvSkillsSnapshot': cvSkillsSnapshot,
      'candidateNameSnapshot': candidateNameSnapshot,
      'candidateEmailSnapshot': candidateEmailSnapshot,
      'candidatePhoneSnapshot': candidatePhoneSnapshot,
      'status': InteractionStatusValue.sent.wire,
      'statusEmployer': InteractionStatusValue.sent.wire,
      'statusCandidate': InteractionStatusValue.sent.wire,
      'isNew': true,
      'unreadForCandidate': true,
      'unreadForEmployer': false,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'vacancySnapshot': vacancySnapshot,
      'candidateSnapshot': candidateSnapshot,
      'employerContactsSnapshot': employerContactsSnapshot,
    };
  }
}
