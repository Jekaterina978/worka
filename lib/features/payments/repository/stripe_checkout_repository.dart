import 'payments_repository.dart';
import '../models/payment_intent_response.dart';

class StripeCheckoutRepository {
  StripeCheckoutRepository({PaymentsRepository? paymentsRepository})
    : _payments = paymentsRepository ?? PaymentsRepository();

  final PaymentsRepository _payments;

  Future<PaymentIntentResponse> createPaymentIntent({
    required String productId,
    int quantity = 1,
    Map<String, dynamic>? context,
    String? vatId,
  }) {
    return _payments.createPaymentIntentPayload(
      productId: productId,
      quantity: quantity,
      context: context,
      vatId: vatId,
    );
  }

  Future<String> createCheckoutSessionUrl({
    required String productId,
    required int amountCents,
    String? ownerId,
    String ownerType = 'user',
    String? targetId,
    String? targetType,
  }) {
    return _payments.createCheckoutSessionUrl(
      productId: productId,
      amountCents: amountCents,
      ownerId: ownerId,
      ownerType: ownerType,
      targetId: targetId,
      targetType: targetType,
    );
  }
}
