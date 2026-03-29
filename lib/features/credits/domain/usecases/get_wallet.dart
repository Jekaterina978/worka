import '../entities/employer_wallet.dart';
import '../repositories/wallet_repository.dart';

class GetWallet {
  final WalletRepository repository;
  const GetWallet(this.repository);

  Future<EmployerWallet> call({String? uid}) => repository.getWallet(uid: uid);
}
