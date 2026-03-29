class PaymentIntentResponse {
  const PaymentIntentResponse({
    required this.clientSecret,
    required this.paymentIntentId,
    required this.amount,
    required this.currency,
    required this.productId,
  });

  final String clientSecret;
  final String paymentIntentId;
  final int amount;
  final String currency;
  final String productId;

  factory PaymentIntentResponse.fromJson(Map<String, dynamic> json) {
    final clientSecret = (json['clientSecret'] ?? '').toString().trim();
    final paymentIntentId = (json['paymentIntentId'] ?? '').toString().trim();
    final productId = (json['productId'] ?? '').toString().trim();
    final currency = (json['currency'] ?? '').toString().trim().toLowerCase();

    int amount = 0;
    final rawAmount = json['amount'];
    if (rawAmount is int) {
      amount = rawAmount;
    } else if (rawAmount is num) {
      amount = rawAmount.toInt();
    } else if (rawAmount != null) {
      amount = int.tryParse(rawAmount.toString()) ?? 0;
    }

    if (clientSecret.isEmpty) {
      throw StateError('Missing clientSecret in payment intent response.');
    }
    if (paymentIntentId.isEmpty) {
      throw StateError('Missing paymentIntentId in payment intent response.');
    }

    return PaymentIntentResponse(
      clientSecret: clientSecret,
      paymentIntentId: paymentIntentId,
      amount: amount,
      currency: currency,
      productId: productId,
    );
  }
}
