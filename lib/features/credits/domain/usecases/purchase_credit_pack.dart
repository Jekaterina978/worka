import '../entities/credit_pack.dart';
import '../entities/purchase_result.dart';
import '../repositories/billing_repository.dart';

class PurchaseCreditPack {
  final BillingRepository repository;
  const PurchaseCreditPack(this.repository);

  Future<PurchaseResult> call(CreditPack pack) =>
      repository.purchaseCreditPack(pack);
}
