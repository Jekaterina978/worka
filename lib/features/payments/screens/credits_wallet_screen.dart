import 'package:flutter/material.dart';
import 'package:worka/theme/worka_colors.dart';

import '../analytics/monetization_analytics.dart';
import '../models/employer_payment_models.dart';
import '../models/payment_product.dart';
import '../payments_i18n.dart';
import '../repository/payments_repository.dart';
import '../services/payment_sheet_service.dart';
import '../services/stripe_payment_sheet_service.dart';
import '../widgets/money_primary_button.dart';
import '../widgets/payment_package_tile.dart';

class CreditsWalletScreen extends StatefulWidget {
  const CreditsWalletScreen({super.key});

  @override
  State<CreditsWalletScreen> createState() => _CreditsWalletScreenState();
}

class _CreditsWalletScreenState extends State<CreditsWalletScreen> {
  static const int _postPurchaseSyncAttempts = 8;
  static const Duration _postPurchaseSyncDelay = Duration(milliseconds: 800);

  final _repo = PaymentsRepository();
  final _payment = StripePaymentSheetService();
  final _analytics = MonetizationAnalytics.instance;

  EmployerMe? _me;
  List<CreditHistoryItem> _history = const [];
  bool _loading = true;
  bool _buying = false;
  PaymentProduct _selected = PaymentProducts.defaultContactProduct;

  @override
  void initState() {
    super.initState();
    _analytics.trackCreditsScreenOpened(
      entryPoint: 'credits_wallet_screen',
      creditsBefore: _me?.credits,
    );
    _reload();
  }

  void _toast(String text, {bool error = false}) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? Colors.red.shade700 : WorkaColors.textDark,
      ),
    );
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    try {
      final me = await _repo.getEmployerMe();
      final history = await _repo.getCreditsHistory();
      if (!mounted) return;
      setState(() {
        _me = me;
        _history = history;
      });
    } catch (e) {
      if (!mounted) return;
      _toast('$e', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _buySelected() async {
    setState(() => _buying = true);
    final creditsBefore = _me?.credits;
    _analytics.trackPurchaseStarted(
      entryPoint: 'credits_wallet_screen',
      packId: _selected.id,
      creditsBefore: creditsBefore,
    );
    try {
      debugPrint(
        '[CreditsWalletScreen] startCheckout product=${_selected.id} creditsBefore=${creditsBefore ?? 0}',
      );
      final payment = await _payment.startCheckout(
        productId: _selected.id,
        quantity: 1,
      );
      if (payment.status == PaymentSheetFlowStatus.cancelled) {
        _analytics.trackPurchaseFailed(
          entryPoint: 'credits_wallet_screen',
          packId: _selected.id,
          creditsBefore: creditsBefore,
          creditsAfter: _me?.credits,
          resultStatus: 'cancelled',
        );
        if (!mounted) return;
        _toast('Оплата отменена');
        return;
      }
      if (payment.status == PaymentSheetFlowStatus.failed) {
        throw StateError(
          payment.message.isEmpty ? 'Payment failed' : payment.message,
        );
      }
      final synced = await _waitForWalletSyncAfterPurchase(
        previousBalance: creditsBefore ?? 0,
      );
      if (synced) {
        _analytics.trackPurchaseSuccess(
          entryPoint: 'credits_wallet_screen',
          packId: _selected.id,
          creditsBefore: creditsBefore,
          creditsAfter: _me?.credits,
        );
      } else {
        _analytics.trackPurchaseFailed(
          entryPoint: 'credits_wallet_screen',
          packId: _selected.id,
          creditsBefore: creditsBefore,
          creditsAfter: _me?.credits,
          resultStatus: 'webhook_pending',
        );
      }
      if (!mounted) return;
      if (synced) {
        _toast(PaymentsI18n.t(context, 'success'));
      } else {
        _toast(
          'Платёж подтверждён. Баланс обновится после подтверждения сервера.',
        );
      }
    } catch (e) {
      _analytics.trackPurchaseFailed(
        entryPoint: 'credits_wallet_screen',
        packId: _selected.id,
        creditsBefore: creditsBefore,
        creditsAfter: _me?.credits,
        resultStatus: 'failed',
      );
      if (!mounted) return;
      _toast('${PaymentsI18n.t(context, 'failed')}: $e', error: true);
    } finally {
      if (mounted) setState(() => _buying = false);
    }
  }

  Future<bool> _waitForWalletSyncAfterPurchase({
    required int previousBalance,
  }) async {
    final normalizedPrevious = previousBalance < 0 ? 0 : previousBalance;
    for (var i = 0; i < _postPurchaseSyncAttempts; i++) {
      await _reload();
      final current = _me?.credits ?? 0;
      if (current > normalizedPrevious) return true;
      if (i < _postPurchaseSyncAttempts - 1) {
        await Future<void>.delayed(_postPurchaseSyncDelay);
      }
    }
    return false;
  }

  String _deltaText(int delta) {
    if (delta > 0) return '+$delta';
    return '$delta';
  }

  bool _isPopularPackage(PaymentProduct p) {
    return p.isMostPopular;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        title: Text(
          PaymentsI18n.t(context, 'credits'),
          style: const TextStyle(
            color: WorkaColors.blue,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : RefreshIndicator(
              onRefresh: _reload,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: WorkaColors.hoverBlueSoft,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: WorkaColors.fieldBorder),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.account_balance_wallet_outlined,
                          color: WorkaColors.blue,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '${PaymentsI18n.t(context, 'balance')}: ${_me?.credits ?? 0}',
                          style: const TextStyle(
                            color: WorkaColors.textDark,
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      '1 контакт = 1 кредит\nКредит используется, чтобы открыть телефон или email кандидата.\nКонтакт открывается навсегда.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.black87,
                        height: 1.3,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...PaymentProducts.creditPackages.map((p) {
                    final isPopular = _isPopularPackage(p);
                    final isSavings = p.isBestValue;
                    final badgeText = p.badgeLabel;
                    final badgeIcon = isPopular
                        ? Icons.local_fire_department_rounded
                        : (isSavings ? Icons.percent_rounded : null);
                    return Padding(
                      padding: EdgeInsets.only(
                        top: (isPopular || isSavings) ? 12 : 0,
                        bottom: 10,
                      ),
                      child: PaymentPackageTile(
                        product: p,
                        selected: _selected.id == p.id,
                        onTap: () {
                          if (_selected.id == p.id) return;
                          setState(() => _selected = p);
                          _analytics.trackPackSelected(
                            entryPoint: 'credits_wallet_screen',
                            packId: p.id,
                            creditsBefore: _me?.credits,
                          );
                        },
                        badgeText: badgeText,
                        badgeIcon: badgeIcon,
                      ),
                    );
                  }),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: MoneyPrimaryButton(
                      text:
                          '${PaymentsI18n.t(context, 'buy_credits')} • ${_selected.priceLabel}',
                      onPressed: _buySelected,
                      isLoading: _buying,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    PaymentsI18n.t(context, 'history'),
                    style: const TextStyle(
                      color: WorkaColors.textDark,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_history.isEmpty)
                    Text(
                      PaymentsI18n.t(context, 'history_empty'),
                      style: const TextStyle(
                        color: WorkaColors.textGreyDark,
                        fontWeight: FontWeight.w700,
                      ),
                    )
                  else
                    ..._history.map((item) {
                      final positive = item.delta >= 0;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: WorkaColors.divider),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.reason,
                                    style: const TextStyle(
                                      color: WorkaColors.textDark,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  if (item.createdAt.isNotEmpty)
                                    Text(
                                      item.createdAt,
                                      style: const TextStyle(
                                        color: WorkaColors.textGreyDark,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            Text(
                              _deltaText(item.delta),
                              style: TextStyle(
                                color: positive
                                    ? Colors.green.shade700
                                    : Colors.red.shade700,
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),
    );
  }
}
