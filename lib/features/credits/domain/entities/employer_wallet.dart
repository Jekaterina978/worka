class EmployerWallet {
  final String uid;
  final int balance;
  final Set<String> unlockedCandidateIds;

  const EmployerWallet({
    required this.uid,
    required this.balance,
    required this.unlockedCandidateIds,
  });
}
