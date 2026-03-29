import '../entities/credit_pack.dart';
import '../entities/purchase_result.dart';

abstract class BillingRepository {
  List<CreditPack> getCreditPacks();
  Future<PurchaseResult> purchaseCreditPack(CreditPack pack);
}
