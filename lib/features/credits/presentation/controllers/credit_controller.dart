import 'package:flutter/material.dart';
import 'package:worka/features/payments/models/payment_product.dart';

import '../../data/repositories/billing_repository_impl.dart';
import '../../data/repositories/wallet_repository_impl.dart';
import '../../domain/entities/credit_pack.dart';
import '../../domain/usecases/get_credit_packs.dart';
import '../../domain/usecases/get_wallet.dart';
import '../../domain/usecases/purchase_credit_pack.dart';
import '../../domain/usecases/refresh_credit_state.dart';
import 'credit_state.dart';

class CreditController extends ChangeNotifier {
  CreditController({
    GetCreditPacks? getCreditPacks,
    GetWallet? getWallet,
    PurchaseCreditPack? purchaseCreditPack,
    RefreshCreditState? refreshCreditState,
  }) : _getCreditPacks =
           getCreditPacks ?? GetCreditPacks(BillingRepositoryImpl()),
       _getWallet = getWallet ?? GetWallet(WalletRepositoryImpl()),
       _purchaseCreditPack =
           purchaseCreditPack ?? PurchaseCreditPack(BillingRepositoryImpl()),
       _refreshCreditState =
           refreshCreditState ?? RefreshCreditState(WalletRepositoryImpl());

  final GetCreditPacks _getCreditPacks;
  final GetWallet _getWallet;
  final PurchaseCreditPack _purchaseCreditPack;
  final RefreshCreditState _refreshCreditState;

  CreditState _state = const CreditState();
  CreditState get state => _state;

  Future<void> load() async {
    _state = _state.copyWith(loading: true, error: '');
    notifyListeners();
    try {
      final packs = _getCreditPacks();
      final wallet = await _getWallet();
      _state = _state.copyWith(
        loading: false,
        balance: wallet.balance,
        packs: packs,
        selectedPack: packs.firstWhere(
          (p) => p.id == PaymentProducts.defaultContactProduct.id,
          orElse: () => packs.first,
        ),
      );
    } catch (e) {
      _state = _state.copyWith(loading: false, error: e.toString());
    }
    notifyListeners();
  }

  void selectPack(CreditPack pack) {
    _state = _state.copyWith(selectedPack: pack);
    notifyListeners();
  }

  Future<bool> buySelected() async {
    final pack = _state.selectedPack;
    if (pack == null) return false;
    _state = _state.copyWith(loading: true, error: '');
    notifyListeners();
    final result = await _purchaseCreditPack(pack);
    if (!result.success) {
      _state = _state.copyWith(loading: false, error: result.message);
      notifyListeners();
      return false;
    }
    final wallet = await _refreshCreditState();
    _state = _state.copyWith(loading: false, balance: wallet.balance);
    notifyListeners();
    return true;
  }
}
