class CheckoutSessionStatus {
  const CheckoutSessionStatus({
    required this.sessionId,
    required this.checkoutStatus,
    required this.paymentStatus,
    required this.status,
    required this.productId,
    required this.canonicalProductId,
    required this.jobId,
    required this.applied,
    required this.isVacancyCheckout,
  });

  final String sessionId;
  final String checkoutStatus;
  final String paymentStatus;
  final String status;
  final String productId;
  final String canonicalProductId;
  final String jobId;
  final bool applied;
  final bool isVacancyCheckout;

  factory CheckoutSessionStatus.fromJson(Map<String, dynamic> json) {
    return CheckoutSessionStatus(
      sessionId: (json['sessionId'] ?? '').toString(),
      checkoutStatus: (json['checkoutStatus'] ?? '').toString(),
      paymentStatus: (json['paymentStatus'] ?? '').toString(),
      status: (json['status'] ?? '').toString(),
      productId: (json['productId'] ?? '').toString(),
      canonicalProductId: (json['canonicalProductId'] ?? '').toString(),
      jobId: (json['jobId'] ?? '').toString(),
      applied: json['applied'] == true,
      isVacancyCheckout: json['isVacancyCheckout'] == true,
    );
  }
}
