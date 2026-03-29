import '../contact_access_controller.dart';
import '../domain/models/credits_models.dart';

class PurchaseCreditPackUseCase {
  PurchaseCreditPackUseCase({ContactAccessController? controller})
    : _controller = controller ?? ContactAccessController.instance;

  final ContactAccessController _controller;

  Future<PurchaseTransaction> call(CreditPack pack) {
    return _controller.purchaseCreditPack(pack);
  }
}
