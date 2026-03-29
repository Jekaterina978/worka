import 'package:flutter_stripe/flutter_stripe.dart';

enum PaymentSheetFlowStatus { success, cancelled, failed }

class PaymentSheetFlowResult {
  const PaymentSheetFlowResult({required this.status, this.message = ''});

  final PaymentSheetFlowStatus status;
  final String message;
}

class PaymentSheetService {
  const PaymentSheetService();

  bool _isCancelled(StripeException e) {
    final raw = '${e.error.code}'.toLowerCase();
    if (e.error.code == FailureCode.Canceled) return true;
    return raw.contains('canceled') || raw.contains('cancelled');
  }

  Future<PaymentSheetFlowResult> payWithStatus({
    required String clientSecret,
    String merchantDisplayName = 'Worka',
  }) async {
    try {
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: clientSecret,
          merchantDisplayName: merchantDisplayName,
          allowsDelayedPaymentMethods: true,
        ),
      );

      await Stripe.instance.presentPaymentSheet();
      return const PaymentSheetFlowResult(
        status: PaymentSheetFlowStatus.success,
      );
    } on StripeException catch (e) {
      if (_isCancelled(e)) {
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

  Future<void> pay({
    required String clientSecret,
    String merchantDisplayName = 'Worka',
  }) async {
    final result = await payWithStatus(
      clientSecret: clientSecret,
      merchantDisplayName: merchantDisplayName,
    );
    if (result.status == PaymentSheetFlowStatus.success) return;
    throw StateError(
      result.message.isEmpty ? 'Payment failed' : result.message,
    );
  }
}
