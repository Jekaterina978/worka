import 'package:flutter/foundation.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/payment_intent_response.dart';
import '../models/payment_product.dart';
import '../repository/stripe_checkout_repository.dart';
import 'payment_sheet_service.dart';

class StripePaymentSheetService {
  StripePaymentSheetService({StripeCheckoutRepository? checkoutRepository})
    : _checkoutRepository = checkoutRepository ?? StripeCheckoutRepository();

  final StripeCheckoutRepository _checkoutRepository;

  Future<PaymentIntentResponse> createPaymentIntent({
    required String productId,
    int quantity = 1,
    Map<String, dynamic>? context,
    String? vatId,
  }) {
    return _checkoutRepository.createPaymentIntent(
      productId: productId,
      quantity: quantity,
      context: context,
      vatId: vatId,
    );
  }

  Future<void> initPaymentSheet({
    required String clientSecret,
    String merchantDisplayName = 'Worka',
  }) {
    return Stripe.instance.initPaymentSheet(
      paymentSheetParameters: SetupPaymentSheetParameters(
        paymentIntentClientSecret: clientSecret,
        merchantDisplayName: merchantDisplayName,
        allowsDelayedPaymentMethods: true,
      ),
    );
  }

  Future<PaymentSheetFlowResult> presentPaymentSheet() async {
    try {
      await Stripe.instance.presentPaymentSheet();
      return const PaymentSheetFlowResult(
        status: PaymentSheetFlowStatus.success,
      );
    } on StripeException catch (e) {
      final code = '${e.error.code}'.toLowerCase();
      final cancelled =
          e.error.code == FailureCode.Canceled ||
          code.contains('canceled') ||
          code.contains('cancelled');
      if (cancelled) {
        return PaymentSheetFlowResult(
          status: PaymentSheetFlowStatus.cancelled,
          message: e.error.localizedMessage ?? 'Payment cancelled',
        );
      }
      return PaymentSheetFlowResult(
        status: PaymentSheetFlowStatus.failed,
        message: e.error.localizedMessage ?? e.toString(),
      );
    } catch (e) {
      return PaymentSheetFlowResult(
        status: PaymentSheetFlowStatus.failed,
        message: e.toString(),
      );
    }
  }

  Future<PaymentSheetFlowResult> startCheckout({
    required String productId,
    int? amountCents,
    int quantity = 1,
    Map<String, dynamic>? context,
    String? vatId,
    String merchantDisplayName = 'Worka',
    String? ownerId,
    String ownerType = 'user',
    String? targetId,
    String? targetType,
  }) async {
    try {
      final product = PaymentProducts.byId(productId);
      final cents = amountCents ?? product?.cents ?? 0;
      if (cents <= 0) {
        return const PaymentSheetFlowResult(
          status: PaymentSheetFlowStatus.failed,
          message: 'Unknown product for checkout',
        );
      }
      debugPrint(
        'startCheckout featureKey=$productId amount=€${(cents / 100).toStringAsFixed(2)} platform=${kIsWeb ? "web" : "mobile"}',
      );
      final uid = FirebaseAuth.instance.currentUser?.uid.trim();
      final effectiveOwnerId = (ownerId ?? uid ?? '').trim();
      final effectiveTargetId = (targetId ?? effectiveOwnerId);
      final effectiveTargetType =
          (targetType ?? ownerType).trim().isEmpty ? ownerType : targetType;
      final checkoutUrl = await _checkoutRepository.createCheckoutSessionUrl(
        productId: productId,
        amountCents: cents,
        ownerId: effectiveOwnerId.isEmpty ? uid : effectiveOwnerId,
        ownerType: ownerType,
        targetId: effectiveTargetId,
        targetType: effectiveTargetType,
      );
      final opened = await launchUrl(
        Uri.parse(checkoutUrl),
        mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.inAppBrowserView,
        webOnlyWindowName: kIsWeb ? '_self' : null,
      );
      if (!opened) {
        return const PaymentSheetFlowResult(
          status: PaymentSheetFlowStatus.failed,
          message: 'Failed to open Stripe Checkout',
        );
      }
      return const PaymentSheetFlowResult(
        status: PaymentSheetFlowStatus.success,
      );
    } catch (e) {
      return PaymentSheetFlowResult(
        status: PaymentSheetFlowStatus.failed,
        message: e.toString(),
      );
    }
  }
}
