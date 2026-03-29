import 'package:cloud_firestore/cloud_firestore.dart';

enum ResponseType { apply, offer }

enum ResponseStatus { sent, viewed, accepted, rejected, postponed }

extension ResponseTypeX on ResponseType {
  String get wire => this == ResponseType.apply ? 'apply' : 'offer';
}

extension ResponseStatusX on ResponseStatus {
  String get wire {
    switch (this) {
      case ResponseStatus.sent:
        return 'sent';
      case ResponseStatus.viewed:
        return 'viewed';
      case ResponseStatus.accepted:
        return 'accepted';
      case ResponseStatus.rejected:
        return 'rejected';
      case ResponseStatus.postponed:
        return 'postponed';
    }
  }
}

class ResponseDoc {
  final String id;
  final ResponseType type;
  final ResponseStatus status;
  final String jobId;
  final String jobOwnerId;
  final String candidateOwnerId;
  final String candidateCvId;
  final String employerOwnerId;
  final Timestamp? createdAt;
  final Timestamp? updatedAt;

  const ResponseDoc({
    required this.id,
    required this.type,
    required this.status,
    required this.jobId,
    required this.jobOwnerId,
    required this.candidateOwnerId,
    required this.candidateCvId,
    required this.employerOwnerId,
    required this.createdAt,
    required this.updatedAt,
  });

  static ResponseType _parseType(dynamic v) {
    final t = (v ?? '').toString().trim().toLowerCase();
    return t == 'offer' ? ResponseType.offer : ResponseType.apply;
  }

  static ResponseStatus _parseStatus(dynamic v) {
    switch ((v ?? '').toString().trim().toLowerCase()) {
      case 'viewed':
        return ResponseStatus.viewed;
      case 'accepted':
        return ResponseStatus.accepted;
      case 'rejected':
        return ResponseStatus.rejected;
      case 'postponed':
        return ResponseStatus.postponed;
      default:
        return ResponseStatus.sent;
    }
  }

  factory ResponseDoc.fromMap(String id, Map<String, dynamic> m) {
    return ResponseDoc(
      id: id,
      type: _parseType(m['type']),
      status: _parseStatus(m['status']),
      jobId: (m['jobId'] ?? '').toString().trim(),
      jobOwnerId: (m['jobOwnerId'] ?? '').toString().trim(),
      candidateOwnerId: (m['candidateOwnerId'] ?? '').toString().trim(),
      candidateCvId: (m['candidateCvId'] ?? '').toString().trim(),
      employerOwnerId: (m['employerOwnerId'] ?? '').toString().trim(),
      createdAt: m['createdAt'] as Timestamp?,
      updatedAt: m['updatedAt'] as Timestamp?,
    );
  }
}
