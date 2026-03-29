import '../repositories/wallet_repository.dart';

class GetUnlockedCandidateIds {
  final WalletRepository repository;
  const GetUnlockedCandidateIds(this.repository);

  Future<Set<String>> call({String? uid}) =>
      repository.getUnlockedCandidateIds(uid: uid);
}
