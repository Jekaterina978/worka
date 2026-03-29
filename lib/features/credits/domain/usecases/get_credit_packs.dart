import '../entities/credit_pack.dart';
import '../repositories/billing_repository.dart';

class GetCreditPacks {
  final BillingRepository repository;
  const GetCreditPacks(this.repository);

  List<CreditPack> call() => repository.getCreditPacks();
}
