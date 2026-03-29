import '../contact_access_controller.dart';
import '../domain/models/credits_models.dart';

class GetWalletUseCase {
  GetWalletUseCase({ContactAccessController? controller})
    : _controller = controller ?? ContactAccessController.instance;

  final ContactAccessController _controller;

  Future<EmployerWallet> call({String? uid}) => _controller.getWallet(uid: uid);
}
