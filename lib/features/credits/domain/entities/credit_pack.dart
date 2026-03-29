class CreditPack {
  final String id;
  final int contacts;
  final int cents;
  final String title;
  final String subtitle;
  final bool isPopular;
  final bool isSavings;

  const CreditPack({
    required this.id,
    required this.contacts,
    required this.cents,
    required this.title,
    required this.subtitle,
    this.isPopular = false,
    this.isSavings = false,
  });

  String get priceLabel => '€ ${(cents / 100).toStringAsFixed(2)}';
}
