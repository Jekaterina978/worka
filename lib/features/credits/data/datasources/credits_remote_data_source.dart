import 'package:worka/features/payments/models/employer_payment_models.dart';
import 'package:worka/features/payments/models/payment_product.dart';
import 'package:worka/features/payments/repository/payments_repository.dart';
import 'package:worka/features/payments/services/payment_sheet_service.dart';

class CreditsRemoteDataSource {
  final PaymentsRepository _paymentsRepository;
  final PaymentSheetService _paymentSheetService;

  CreditsRemoteDataSource({
    PaymentsRepository? paymentsRepository,
    PaymentSheetService? paymentSheetService,
  }) : _paymentsRepository = paymentsRepository ?? PaymentsRepository(),
       _paymentSheetService =
           paymentSheetService ?? const PaymentSheetService();

  Future<EmployerMe> fetchEmployerWallet() {
    return _paymentsRepository.getEmployerMe();
  }

  Future<Set<String>> fetchUnlockedCandidateIds() {
    return _paymentsRepository.getUnlockedCandidateIds();
  }

  Future<ConsumeCreditResult> consumeCandidateContact(String candidateId) {
    return _paymentsRepository.consumeCredit(candidateId: candidateId);
  }

  Future<void> purchaseProduct(PaymentProduct product) async {
    final clientSecret = await _paymentsRepository.createPaymentIntent(
      productId: product.id,
    );
    await _paymentSheetService.pay(clientSecret: clientSecret);
  }
}
