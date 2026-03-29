import '../../domain/entities/credit_pack.dart';

class CreditState {
  final bool loading;
  final int balance;
  final List<CreditPack> packs;
  final CreditPack? selectedPack;
  final String error;

  const CreditState({
    this.loading = false,
    this.balance = 0,
    this.packs = const <CreditPack>[],
    this.selectedPack,
    this.error = '',
  });

  CreditState copyWith({
    bool? loading,
    int? balance,
    List<CreditPack>? packs,
    CreditPack? selectedPack,
    String? error,
  }) {
    return CreditState(
      loading: loading ?? this.loading,
      balance: balance ?? this.balance,
      packs: packs ?? this.packs,
      selectedPack: selectedPack ?? this.selectedPack,
      error: error ?? this.error,
    );
  }
}
