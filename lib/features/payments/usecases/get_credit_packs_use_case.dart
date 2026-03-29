import '../contact_access_controller.dart';
import '../domain/models/credits_models.dart';

class GetCreditPacksUseCase {
  GetCreditPacksUseCase({ContactAccessController? controller})
    : _controller = controller ?? ContactAccessController.instance;

  final ContactAccessController _controller;

  List<CreditPack> call() => _controller.getCreditPacks();
}
