import '../entities/employer_wallet.dart';
import '../repositories/wallet_repository.dart';

class RefreshCreditState {
  final WalletRepository repository;
  const RefreshCreditState(this.repository);

  Future<EmployerWallet> call({String? uid}) =>
      repository.refreshWallet(uid: uid);
}
