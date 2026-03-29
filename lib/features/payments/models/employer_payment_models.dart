class EmployerMe {
  final String uid;
  final String email;
  final String vatId;
  final int credits;
  final String plan;
  final String verificationStatus;

  const EmployerMe({
    required this.uid,
    required this.email,
    required this.vatId,
    required this.credits,
    required this.plan,
    required this.verificationStatus,
  });

  factory EmployerMe.fromJson(Map<String, dynamic> json) {
    int credits = 0;
    final rawCredits = json['credits'];
    if (rawCredits is int) {
      credits = rawCredits;
    } else if (rawCredits is num) {
      credits = rawCredits.toInt();
    } else if (rawCredits != null) {
      credits = int.tryParse(rawCredits.toString()) ?? 0;
    }

    return EmployerMe(
      uid: (json['uid'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      vatId: (json['vatId'] ?? '').toString(),
      credits: credits,
      plan: (json['plan'] ?? '').toString(),
      verificationStatus: (json['verificationStatus'] ?? 'none').toString(),
    );
  }
}

class CreditHistoryItem {
  final String id;
  final int delta;
  final String reason;
  final String refId;
  final String createdAt;

  const CreditHistoryItem({
    required this.id,
    required this.delta,
    required this.reason,
    required this.refId,
    required this.createdAt,
  });

  factory CreditHistoryItem.fromJson(Map<String, dynamic> json) {
    int delta = 0;
    final raw = json['delta'];
    if (raw is int) {
      delta = raw;
    } else if (raw is num) {
      delta = raw.toInt();
    } else if (raw != null) {
      delta = int.tryParse(raw.toString()) ?? 0;
    }

    return CreditHistoryItem(
      id: (json['id'] ?? '').toString(),
      delta: delta,
      reason: (json['reason'] ?? '').toString(),
      refId: (json['refId'] ?? '').toString(),
      createdAt: (json['createdAt'] ?? '').toString(),
    );
  }
}

class CandidateContact {
  final String candidateId;
  final String name;
  final String email;
  final String phone;
  final String whatsapp;
  final String telegram;
  final String viber;
  final String messenger;

  const CandidateContact({
    required this.candidateId,
    required this.name,
    required this.email,
    required this.phone,
    this.whatsapp = '',
    this.telegram = '',
    this.viber = '',
    this.messenger = '',
  });

  factory CandidateContact.fromJson(Map<String, dynamic> json) {
    return CandidateContact(
      candidateId: (json['candidateId'] ?? '').toString(),
      name: (json['name'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      phone: (json['phone'] ?? '').toString(),
      whatsapp: (json['whatsapp'] ?? '').toString(),
      telegram: (json['telegram'] ?? '').toString(),
      viber: (json['viber'] ?? '').toString(),
      messenger: (json['messenger'] ?? '').toString(),
    );
  }
}

class ConsumeCreditResult {
  final int creditsLeft;
  final CandidateContact contact;

  const ConsumeCreditResult({required this.creditsLeft, required this.contact});

  factory ConsumeCreditResult.fromJson(Map<String, dynamic> json) {
    int creditsLeft = 0;
    final raw = json['creditsLeft'];
    if (raw is int) {
      creditsLeft = raw;
    } else if (raw is num) {
      creditsLeft = raw.toInt();
    } else if (raw != null) {
      creditsLeft = int.tryParse(raw.toString()) ?? 0;
    }

    final contactJson = (json['contact'] is Map)
        ? Map<String, dynamic>.from(json['contact'] as Map)
        : <String, dynamic>{};

    return ConsumeCreditResult(
      creditsLeft: creditsLeft,
      contact: CandidateContact.fromJson(contactJson),
    );
  }
}

class VerificationStatusResult {
  final String status;
  final String fileUrl;
  final String notes;
  final String updatedAt;

  const VerificationStatusResult({
    required this.status,
    required this.fileUrl,
    required this.notes,
    required this.updatedAt,
  });

  factory VerificationStatusResult.fromJson(Map<String, dynamic> json) {
    return VerificationStatusResult(
      status: (json['status'] ?? 'none').toString(),
      fileUrl: (json['fileUrl'] ?? '').toString(),
      notes: (json['notes'] ?? '').toString(),
      updatedAt: (json['updatedAt'] ?? '').toString(),
    );
  }
}
