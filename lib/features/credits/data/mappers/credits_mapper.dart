import 'package:worka/features/payments/models/payment_product.dart';

import '../../domain/entities/credit_pack.dart';

class CreditsMapper {
  static CreditPack fromPaymentProduct(PaymentProduct p) {
    final contacts =
        p.credits ??
        int.tryParse(RegExp(r'(\d+)').firstMatch(p.title)?.group(1) ?? '') ??
        1;
    return CreditPack(
      id: p.id,
      contacts: contacts,
      cents: p.cents,
      title: p.title,
      subtitle: p.subtitle,
      isPopular: p.isMostPopular,
      isSavings: p.isBestValue,
    );
  }

  static PaymentProduct toPaymentProduct(CreditPack pack) {
    return PaymentProduct(
      id: pack.id,
      title: pack.title,
      subtitle: pack.subtitle,
      cents: pack.cents,
    );
  }
}
