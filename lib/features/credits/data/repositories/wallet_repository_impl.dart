import 'package:firebase_auth/firebase_auth.dart';
import 'package:worka/features/payments/contact_access_controller.dart';

import '../../domain/entities/employer_wallet.dart';
import '../../domain/repositories/wallet_repository.dart';
import '../datasources/credits_local_data_source.dart';

class WalletRepositoryImpl implements WalletRepository {
  final ContactAccessController _controller;
  final CreditsLocalDataSource _local;

  WalletRepositoryImpl({
    ContactAccessController? controller,
    CreditsLocalDataSource? local,
  }) : _controller = controller ?? ContactAccessController.instance,
       _local = local ?? CreditsLocalDataSource();

  @override
  Future<EmployerWallet> getWallet({String? uid}) async {
    await _controller.bootstrap(
      uid: uid ?? FirebaseAuth.instance.currentUser?.uid,
    );
    final wallet = await _controller.getWallet(
      uid: uid ?? FirebaseAuth.instance.currentUser?.uid,
    );
    return EmployerWallet(
      uid: wallet.uid,
      balance: wallet.balance,
      unlockedCandidateIds: wallet.unlockedCandidateIds,
    );
  }

  @override
  Future<Set<String>> getUnlockedCandidateIds({String? uid}) async {
    final serverIds = await _controller.getUnlockedCandidateIds(
      uid: uid ?? FirebaseAuth.instance.currentUser?.uid,
    );
    // Keep local layer warm for UX fallback without using it as source-of-truth.
    await _local.load(uid: uid);
    for (final id in serverIds) {
      await _local.markOpened(
        id,
        uid: uid ?? FirebaseAuth.instance.currentUser?.uid,
      );
    }
    return serverIds;
  }

  @override
  Future<EmployerWallet> refreshWallet({String? uid}) {
    return getWallet(uid: uid ?? FirebaseAuth.instance.currentUser?.uid);
  }
}
