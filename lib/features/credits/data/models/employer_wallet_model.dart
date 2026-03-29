import '../../domain/entities/employer_wallet.dart';

class EmployerWalletModel extends EmployerWallet {
  const EmployerWalletModel({
    required super.uid,
    required super.balance,
    required super.unlockedCandidateIds,
  });

  factory EmployerWalletModel.fromJson(Map<String, dynamic> json) {
    final unlocked =
        (json['unlockedCandidateIds'] as List?)
            ?.map((e) => e.toString().trim())
            .where((e) => e.isNotEmpty)
            .toSet() ??
        <String>{};
    return EmployerWalletModel(
      uid: (json['uid'] ?? '').toString(),
      balance: (json['balance'] as num?)?.toInt() ?? 0,
      unlockedCandidateIds: unlocked,
    );
  }

  Map<String, dynamic> toJson() => {
    'uid': uid,
    'balance': balance,
    'unlockedCandidateIds': unlockedCandidateIds.toList(),
  };
}
