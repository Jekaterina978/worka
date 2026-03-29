import 'auth_guard.dart';

class OwnershipState {
  const OwnershipState({required this.known, required this.isOwner});

  final bool known;
  final bool isOwner;
}

class OwnershipResolver {
  OwnershipResolver._();

  static String currentUid() => (AuthGuard.effectiveUidOrNull() ?? '').trim();

  static String ownerFromMap(
    Map<String, dynamic> data, {
    List<String> keys = const <String>[],
  }) {
    final ownerKeys = keys.isEmpty
        ? const <String>['ownerId', 'ownerUid', 'ownerKey']
        : keys;
    for (final key in ownerKeys) {
      final value = (data[key] ?? '').toString().trim();
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  static OwnershipState byOwnerId(String ownerId, {String? currentUserId}) {
    final owner = ownerId.trim();
    if (owner.isEmpty) {
      return const OwnershipState(known: false, isOwner: false);
    }
    final current = (currentUserId ?? currentUid()).trim();
    final isOwner = current.isNotEmpty && current == owner;
    return OwnershipState(known: true, isOwner: isOwner);
  }

  static OwnershipState vacancyOwnership(
    Map<String, dynamic> vacancy, {
    String? currentUserId,
  }) {
    final ownerId = vacancyOwnerIdFromMap(vacancy);
    return byOwnerId(ownerId, currentUserId: currentUserId);
  }

  static OwnershipState cvOwnership(
    Map<String, dynamic> cv, {
    String? currentUserId,
  }) {
    final ownerId = cvOwnerIdFromMap(cv);
    return byOwnerId(ownerId, currentUserId: currentUserId);
  }

  static String vacancyOwnerIdFromMap(Map<String, dynamic> vacancy) {
    return ownerFromMap(
      vacancy,
      keys: const <String>[
        'ownerId',
        'ownerUid',
        'employerOwnerId',
        'employerUid',
      ],
    );
  }

  static String cvOwnerIdFromMap(Map<String, dynamic> cv) {
    return ownerFromMap(
      cv,
      keys: const <String>[
        'candidateOwnerId',
        'ownerId',
        'ownerUid',
        'candidateUid',
      ],
    );
  }
}
