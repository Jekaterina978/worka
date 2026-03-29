import '../entities/employer_wallet.dart';

abstract class WalletRepository {
  Future<EmployerWallet> getWallet({String? uid});
  Future<EmployerWallet> refreshWallet({String? uid});
  Future<Set<String>> getUnlockedCandidateIds({String? uid});
}
