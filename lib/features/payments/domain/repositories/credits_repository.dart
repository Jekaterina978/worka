import '../models/credits_models.dart';

abstract class CreditsRepository {
  List<CreditPack> getCreditPacks();

  Future<EmployerWallet> getWallet({String? uid});

  Future<Set<String>> getUnlockedCandidateIds({String? uid});

  bool hasAccessToCandidateContact(String candidateId);

  Future<PurchaseTransaction> purchaseCreditPack(CreditPack pack);

  Future<CreditSpendTransaction> unlockCandidateContact({
    required String candidateId,
  });
}
