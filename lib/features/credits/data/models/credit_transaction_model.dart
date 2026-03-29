import '../../domain/entities/credit_transaction.dart';

class CreditTransactionModel extends CreditTransaction {
  const CreditTransactionModel({
    required super.id,
    required super.type,
    required super.delta,
    required super.reason,
  });
}
