import '../../domain/entities/unlock_contact_result.dart';

class UnlockContactResultModel extends UnlockContactResult {
  const UnlockContactResultModel({
    required super.status,
    super.creditsLeft,
    super.message,
  });
}
