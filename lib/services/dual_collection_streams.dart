import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

typedef FirestoreDocList = List<QueryDocumentSnapshot<Map<String, dynamic>>>;

class DualCollectionStreams {
  DualCollectionStreams._();

  static Stream<FirestoreDocList> mergeDocs({
    required FirebaseFirestore db,
    required String firstCollection,
    required String secondCollection,
  }) {
    if (firstCollection == secondCollection) {
      return db.collection(firstCollection).snapshots().map((s) => [...s.docs]);
    }

    late StreamController<FirestoreDocList> controller;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? firstSub;
    StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? secondSub;
    QuerySnapshot<Map<String, dynamic>>? firstSnap;
    QuerySnapshot<Map<String, dynamic>>? secondSnap;

    void emit() {
      controller.add(<QueryDocumentSnapshot<Map<String, dynamic>>>[
        ...?firstSnap?.docs,
        ...?secondSnap?.docs,
      ]);
    }

    controller = StreamController<FirestoreDocList>(
      onListen: () {
        firstSub = db.collection(firstCollection).snapshots().listen((s) {
          firstSnap = s;
          emit();
        }, onError: controller.addError);
        secondSub = db.collection(secondCollection).snapshots().listen((s) {
          secondSnap = s;
          emit();
        }, onError: controller.addError);
      },
      onCancel: () async {
        await firstSub?.cancel();
        await secondSub?.cancel();
      },
    );

    return controller.stream;
  }
}
