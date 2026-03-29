import 'payment_product.dart';

enum VacancyPaymentFeature { highlightJob, urgent, bump, showEmployerContacts }

class VacancyPaymentProductSpec {
  const VacancyPaymentProductSpec({
    required this.feature,
    required this.canonicalId,
    required this.backendProductId,
    required this.displayTitle,
    required this.durationLabel,
  });

  final VacancyPaymentFeature feature;
  final String canonicalId;
  final String backendProductId;
  final String displayTitle;
  final String durationLabel;

  PaymentProduct get paymentProduct =>
      PaymentProducts.byId(backendProductId) ?? PaymentProducts.bump;
}

class VacancyPaymentFeatures {
  const VacancyPaymentFeatures._();

  static const String canonicalHighlight = 'job_highlight';
  static const String canonicalUrgent = 'job_urgent';
  static const String canonicalBoost = 'job_boost';
  static const String canonicalShowEmployerContacts =
      'job_show_employer_contacts';

  // IMPORTANT: Vacancy promotion UI must use ONLY this canonical 4-item list.
  // Hardcoded tariff lists are forbidden.
  static const List<VacancyPaymentFeature> displayOrder =
      <VacancyPaymentFeature>[
        VacancyPaymentFeature.highlightJob,
        VacancyPaymentFeature.urgent,
        VacancyPaymentFeature.bump,
        VacancyPaymentFeature.showEmployerContacts,
      ];

  static final Map<VacancyPaymentFeature, VacancyPaymentProductSpec> products =
      <VacancyPaymentFeature, VacancyPaymentProductSpec>{
        VacancyPaymentFeature.highlightJob: VacancyPaymentProductSpec(
          feature: VacancyPaymentFeature.highlightJob,
          canonicalId: canonicalHighlight,
          backendProductId: PaymentProducts.highlightJob.id,
          displayTitle: 'Выделение вакансии',
          durationLabel: '7 дней',
        ),
        VacancyPaymentFeature.urgent: VacancyPaymentProductSpec(
          feature: VacancyPaymentFeature.urgent,
          canonicalId: canonicalUrgent,
          backendProductId: PaymentProducts.urgent.id,
          displayTitle: 'Приоритет вакансии',
          durationLabel: '7 дней',
        ),
        VacancyPaymentFeature.bump: VacancyPaymentProductSpec(
          feature: VacancyPaymentFeature.bump,
          canonicalId: canonicalBoost,
          backendProductId: PaymentProducts.bump.id,
          displayTitle: 'Обновление в ленте',
          durationLabel: '72 часа',
        ),
        VacancyPaymentFeature.showEmployerContacts: VacancyPaymentProductSpec(
          feature: VacancyPaymentFeature.showEmployerContacts,
          canonicalId: canonicalShowEmployerContacts,
          backendProductId: PaymentProducts.showEmployerContacts.id,
          displayTitle: 'Показать контакты работодателя',
          durationLabel: 'Без срока',
        ),
      };

  static List<VacancyPaymentProductSpec> get allProducts =>
      displayOrder.map((f) => products[f]!).toList(growable: false);

  static VacancyPaymentProductSpec? byAnyId(String id) {
    final clean = id.trim();
    if (clean.isEmpty) return null;
    for (final spec in products.values) {
      if (spec.canonicalId == clean || spec.backendProductId == clean) {
        return spec;
      }
    }
    return null;
  }
}
