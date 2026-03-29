import 'package:worka/features/payments/contact_unlock_store.dart';

class CreditsLocalDataSource {
  final ContactUnlockStore _store;

  CreditsLocalDataSource({ContactUnlockStore? store})
    : _store = store ?? ContactUnlockStore.instance;

  Future<void> load({String? uid}) => _store.load(uid: uid);

  Future<void> markOpened(String candidateId, {String? uid}) {
    return _store.markOpened(candidateId, uid: uid);
  }

  bool isOpened(String candidateId) => _store.isOpened(candidateId);

  Set<String> getOpenedIds() => _store.openedIdsSnapshot();
}
