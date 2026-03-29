import 'vacancy_payment_feature.dart';

class VacancyPaymentDisplayItem {
  const VacancyPaymentDisplayItem({
    required this.displayOrder,
    required this.canonicalProductId,
    required this.backendProductId,
    required this.title,
    required this.subtitle,
    required this.durationLabel,
    required this.priceLabel,
  });

  final int displayOrder;
  final String canonicalProductId;
  final String backendProductId;
  final String title;
  final String subtitle;
  final String durationLabel;
  final String priceLabel;
}

class VacancyPaymentDisplayCatalog {
  const VacancyPaymentDisplayCatalog._();

  static List<VacancyPaymentDisplayItem> get allProducts {
    final specs = VacancyPaymentFeatures.allProducts;
    return List<VacancyPaymentDisplayItem>.generate(specs.length, (index) {
      final spec = specs[index];
      final product = spec.paymentProduct;
      return VacancyPaymentDisplayItem(
        displayOrder: index,
        canonicalProductId: spec.canonicalId,
        backendProductId: spec.backendProductId,
        title: spec.displayTitle,
        subtitle: product.subtitle,
        durationLabel: spec.durationLabel,
        priceLabel: product.priceLabel,
      );
    }, growable: false);
  }

  static VacancyPaymentDisplayItem? byAnyId(String id) {
    final clean = id.trim();
    if (clean.isEmpty) return null;
    for (final item in allProducts) {
      if (item.canonicalProductId == clean || item.backendProductId == clean) {
        return item;
      }
    }
    return null;
  }
}
