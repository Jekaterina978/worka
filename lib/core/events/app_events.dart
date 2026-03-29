import 'dart:async';

/// Global app-wide events.
class AppEvents {
  static final _paymentCompletedController =
      StreamController<String>.broadcast();

  /// Stream of jobCodes for completed payments.
  static Stream<String> get onPaymentCompleted =>
      _paymentCompletedController.stream;

  /// Emit a payment completed event for a given jobCode.
  static void emitPaymentCompleted(String jobCode) {
    _paymentCompletedController.add(jobCode);
  }
}
