// ignore_for_file: avoid_print
import 'package:flutter/foundation.dart';

import '../repository/payments_repository.dart';
import '_web_redirect_stub.dart'
    if (dart.library.html) '_web_redirect_impl.dart';

class WebCheckoutFlow {
  const WebCheckoutFlow._();

  static Future<void> start({
    required PaymentsRepository repository,
    required String screenName,
    required String selectedTariff,
    required String featureKey,
    required int amountCents,
    required String entityId,
    String ownerType = 'user',
    String? targetType,
  }) async {
    print('[PAYMENT DEBUG] START screen=$screenName');
    print('[PAYMENT DEBUG] featureKey=$featureKey');
    print('[PAYMENT DEBUG] targetType=${targetType ?? ownerType}');
    print('[PAYMENT DEBUG] targetId=$entityId');
    print('[PAYMENT DEBUG] ownerType=$ownerType');
    print('[PAYMENT DEBUG] ownerId=$entityId');
    print('[PAYMENT DEBUG] amountCents=$amountCents');

    if (kDebugMode) {
      debugPrint('[$screenName] selected tariff: $selectedTariff');
      debugPrint('[$screenName] Uri.base.origin before checkout: ${Uri.base.origin}');
    }

    String checkoutUrl;
    try {
      checkoutUrl = await repository.createCheckoutSessionUrl(
        productId: featureKey,
        amountCents: amountCents,
        ownerId: entityId,
        ownerType: ownerType,
        targetId: entityId,
        targetType: targetType ?? ownerType,
      );
    } catch (e) {
      print('[PAYMENT DEBUG] ERROR createCheckoutSessionUrl failed: $e');
      rethrow;
    }

    print('[PAYMENT DEBUG] checkoutUrl=$checkoutUrl');

    if (kIsWeb) {
      print('[PAYMENT DEBUG] redirecting via html.window.location.href');
      webNavigateTo(checkoutUrl);
    } else {
      throw UnsupportedError('WebCheckoutFlow.start called on non-web platform');
    }
  }
}
