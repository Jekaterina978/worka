enum PurchaseStatus { pending, success, failed, cancelled }

enum CreditSpendStatus { success, alreadyOpened, insufficientCredits, failed }

class CreditPack {
  final String id;
  final int contacts;
  final int cents;
  final String title;
  final String subtitle;
  final bool isMostPopular;
  final bool isBestValue;

  const CreditPack({
    required this.id,
    required this.contacts,
    required this.cents,
    required this.title,
    required this.subtitle,
    this.isMostPopular = false,
    this.isBestValue = false,
  });

  String get priceLabel => '€ ${(cents / 100).toStringAsFixed(2)}';
}

class EmployerWallet {
  final String uid;
  final int balance;
  final Set<String> unlockedCandidateIds;
  final DateTime fetchedAt;

  const EmployerWallet({
    required this.uid,
    required this.balance,
    required this.unlockedCandidateIds,
    required this.fetchedAt,
  });
}

class CandidateContactAccess {
  final String candidateId;
  final bool hasAccess;
  final bool unlockedPermanently;
  final DateTime checkedAt;

  const CandidateContactAccess({
    required this.candidateId,
    required this.hasAccess,
    required this.unlockedPermanently,
    required this.checkedAt,
  });
}

class PurchaseTransaction {
  final String productId;
  final int amountCents;
  final PurchaseStatus status;
  final DateTime createdAt;
  final String message;

  const PurchaseTransaction({
    required this.productId,
    required this.amountCents,
    required this.status,
    required this.createdAt,
    this.message = '',
  });
}

class CreditSpendTransaction {
  final String candidateId;
  final int creditsBefore;
  final int creditsAfter;
  final CreditSpendStatus status;
  final DateTime createdAt;
  final String message;

  const CreditSpendTransaction({
    required this.candidateId,
    required this.creditsBefore,
    required this.creditsAfter,
    required this.status,
    required this.createdAt,
    this.message = '',
  });
}
