import '../../domain/entities/credit_pack.dart';
import '../../domain/entities/purchase_result.dart';
import 'credits_remote_data_source.dart';
import '../mappers/credits_mapper.dart';

class InAppPurchaseDataSource {
  final CreditsRemoteDataSource _remote;

  InAppPurchaseDataSource({CreditsRemoteDataSource? remote})
    : _remote = remote ?? CreditsRemoteDataSource();

  Future<PurchaseResult> purchase(CreditPack pack) async {
    try {
      await _remote.purchaseProduct(CreditsMapper.toPaymentProduct(pack));
      return PurchaseResult(
        status: PurchaseStatus.success,
        productId: pack.id,
        cents: pack.cents,
      );
    } catch (e) {
      return PurchaseResult(
        status: PurchaseStatus.failed,
        productId: pack.id,
        cents: pack.cents,
        message: e.toString(),
      );
    }
  }
}
