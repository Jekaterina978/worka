import 'package:worka/features/payments/contact_access_controller.dart';
import '../../domain/entities/credit_pack.dart';
import '../../domain/entities/purchase_result.dart';
import '../../domain/repositories/billing_repository.dart';
import '../mappers/credits_mapper.dart';
import 'package:worka/features/payments/models/payment_product.dart';

class BillingRepositoryImpl implements BillingRepository {
  final ContactAccessController _controller;

  BillingRepositoryImpl({ContactAccessController? controller})
    : _controller = controller ?? ContactAccessController.instance;

  @override
  List<CreditPack> getCreditPacks() {
    return PaymentProducts.creditPackages
        .map(CreditsMapper.fromPaymentProduct)
        .toList(growable: false);
  }

  @override
  Future<PurchaseResult> purchaseCreditPack(CreditPack pack) {
    return _purchaseViaController(pack);
  }

  Future<PurchaseResult> _purchaseViaController(CreditPack pack) async {
    try {
      final tx = await _controller.purchaseContactProduct(
        CreditsMapper.toPaymentProduct(pack),
      );
      final purchaseStatus = switch (tx.status.name) {
        'success' => PurchaseStatus.success,
        'pending' => PurchaseStatus.pending,
        'cancelled' => PurchaseStatus.cancelled,
        _ => PurchaseStatus.failed,
      };
      return PurchaseResult(
        status: purchaseStatus,
        productId: pack.id,
        cents: pack.cents,
        message: tx.message,
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
