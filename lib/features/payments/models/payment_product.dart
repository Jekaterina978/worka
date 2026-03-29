class PaymentProduct {
  final String id;
  final String title;
  final String subtitle;
  final int cents;
  final int? credits;
  final bool isMostPopular;
  final bool isBestValue;
  final bool isDefaultSelected;
  final String? badgeLabel;

  const PaymentProduct({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.cents,
    this.credits,
    this.isMostPopular = false,
    this.isBestValue = false,
    this.isDefaultSelected = false,
    this.badgeLabel,
  });

  String get priceLabel {
    final value = (cents / 100).toStringAsFixed(2);
    return '€ $value';
  }

  Map<String, Object> toAnalyticsPayload() {
    return <String, Object>{
      'product_id': id,
      'product_title': title,
      'amount_cents': cents,
      'currency': 'EUR',
      if (credits != null) 'credits': credits!,
      'is_most_popular': isMostPopular,
      'is_best_value': isBestValue,
    };
  }
}

class PaymentProducts {
  static const credit1 = PaymentProduct(
    id: 'contact_1',
    title: '1 контакт',
    subtitle: 'Разблокировать 1 кандидата',
    cents: 299,
    credits: 1,
  );

  static const contactPackage10 = PaymentProduct(
    id: 'contact_10',
    title: '10 контактов',
    subtitle: 'Пакет контактов',
    cents: 2499,
    credits: 10,
    isMostPopular: true,
    isDefaultSelected: true,
    badgeLabel: 'Самый популярный',
  );

  static const contactPackage30 = PaymentProduct(
    id: 'contact_30',
    title: '30 контактов',
    subtitle: 'Экономия 33%',
    cents: 5999,
    credits: 30,
    isBestValue: true,
    badgeLabel: 'Экономия 33%',
  );

  static const bump = PaymentProduct(
    id: 'promotion_bump',
    title: 'Обновление в ленте',
    subtitle: '€ 4.99 / 72 часа',
    cents: 499,
  );

  static const urgent = PaymentProduct(
    id: 'promotion_urgent',
    title: 'Приоритет вакансии',
    subtitle: '€ 7.99 / 7 дней',
    cents: 799,
  );

  static const showEmployerContacts = PaymentProduct(
    id: 'promotion_show_employer_contacts',
    title: 'Показать контакты работодателя',
    subtitle: 'Доступ к контактам работодателя',
    cents: 5000,
  );

  static const highlightCv = PaymentProduct(
    id: 'highlight_cv_7d',
    title: 'Выделение CV',
    subtitle: '€ 2.49 / 7d',
    cents: 249,
  );

  static const priorityCv = PaymentProduct(
    id: 'priority_cv_7d',
    title: 'Приоритет CV',
    subtitle: '€ 3.99 / 7d',
    cents: 399,
  );

  static const highlightJob = PaymentProduct(
    id: 'highlight_job_7d',
    title: 'Выделение вакансии',
    subtitle: '€ 6.99 / 7d',
    cents: 699,
  );

  static const verification = PaymentProduct(
    id: 'employer_verification',
    title: 'Верификация работодателя',
    subtitle: '€ 19.00 единоразово',
    cents: 1900,
  );

  static const creditPackages = <PaymentProduct>[
    credit1,
    contactPackage10,
    contactPackage30,
  ];
  static const contactPackages = <PaymentProduct>[
    contactPackage10,
    contactPackage30,
  ];
  static const cvPromotionPackages = <PaymentProduct>[
    highlightCv,
    bump,
    priorityCv,
  ];
  static const vacancyPromotionPackages = <PaymentProduct>[
    highlightJob,
    urgent,
    bump,
    showEmployerContacts,
  ];
  static const employerPromotionPackages = <PaymentProduct>[
    showEmployerContacts,
  ];

  static PaymentProduct get defaultContactProduct => creditPackages.firstWhere(
    (p) => p.isDefaultSelected,
    orElse: () => contactPackage10,
  );

  static PaymentProduct? byId(String id) {
    final clean = id.trim();
    if (clean.isEmpty) return null;
    for (final p in [
      ...creditPackages,
      ...contactPackages,
      ...vacancyPromotionPackages,
      ...employerPromotionPackages,
      verification,
      highlightCv,
      priorityCv,
      highlightJob,
    ]) {
      if (p.id == clean) return p;
    }
    return null;
  }

  static String paywallOfferLine(PaymentProduct product) {
    if (product.credits == 1) {
      return '${product.priceLabel} — 1 кандидат';
    }
    return '${product.title} — ${product.priceLabel}';
  }
}
