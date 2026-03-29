import '../../domain/entities/credit_pack.dart';

class CreditPackModel extends CreditPack {
  const CreditPackModel({
    required super.id,
    required super.contacts,
    required super.cents,
    required super.title,
    required super.subtitle,
    super.isPopular,
    super.isSavings,
  });

  factory CreditPackModel.fromJson(Map<String, dynamic> json) {
    return CreditPackModel(
      id: (json['id'] ?? '').toString(),
      contacts: (json['contacts'] as num?)?.toInt() ?? 1,
      cents: (json['cents'] as num?)?.toInt() ?? 0,
      title: (json['title'] ?? '').toString(),
      subtitle: (json['subtitle'] ?? '').toString(),
      isPopular: json['isPopular'] == true,
      isSavings: json['isSavings'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'contacts': contacts,
    'cents': cents,
    'title': title,
    'subtitle': subtitle,
    'isPopular': isPopular,
    'isSavings': isSavings,
  };
}
