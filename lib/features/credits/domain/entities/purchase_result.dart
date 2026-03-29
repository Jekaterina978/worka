enum PurchaseStatus { success, pending, failed, cancelled }

class PurchaseResult {
  final PurchaseStatus status;
  final String productId;
  final int cents;
  final String message;

  const PurchaseResult({
    required this.status,
    required this.productId,
    required this.cents,
    this.message = '',
  });

  bool get success => status == PurchaseStatus.success;
}
