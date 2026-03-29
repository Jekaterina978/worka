import '../../domain/entities/purchase_result.dart';

class PurchaseResultModel extends PurchaseResult {
  const PurchaseResultModel({
    required super.status,
    required super.productId,
    required super.cents,
    super.message,
  });
}
