enum CreditTransactionType { purchase, spend }

class CreditTransaction {
  final String id;
  final CreditTransactionType type;
  final int delta;
  final String reason;

  const CreditTransaction({
    required this.id,
    required this.type,
    required this.delta,
    required this.reason,
  });
}
