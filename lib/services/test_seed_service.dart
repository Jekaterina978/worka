library;

import 'package:cloud_firestore/cloud_firestore.dart';

class TestSeedService {
  static const String kMetaDoc = 'meta';
  static const String kSeedDoc = 'seed_v1';

  static Future<void> ensureSeeded(FirebaseFirestore db) async {
    try {
      final metaRef = db.collection('app_test').doc(kMetaDoc);
      final metaSnap = await metaRef.get();
      final already = (metaSnap.data()?['seeded_$kSeedDoc'] ?? false) == true;
      if (already) return;

      // если в jobs_test и cvs_test уже есть данные — тоже считаем, что seeded
      final jobsSnap = await db.collection('jobs_test').limit(1).get();
      final cvsSnap = await db.collection('cvs_test').limit(1).get();
      if (jobsSnap.docs.isNotEmpty || cvsSnap.docs.isNotEmpty) {
        await metaRef.set({'seeded_$kSeedDoc': true}, SetOptions(merge: true));
        return;
      }

      final now = FieldValue.serverTimestamp();

      // ====== TEST JOBS ======
      final job1 = await db.collection('jobs_test').add({
        'title': 'Уборщик (тест)',
        'city': 'Таллинн',
        'country': 'Эстония',
        'salaryText': '7–10 EUR/час',
        'category': 'Клининг',
        'type': 'Полная занятость',
        'experience': 'Без опыта',
        'description': 'Тестовая вакансия для проверки откликов и статусов.',
        'housingProvided': true,
        'transportProvided': false,
        'teenFriendly': true,
        'employerId': 'test_employer',
        'createdAt': now,
        'updatedAt': now,
        'test': true,
      });

      await db.collection('jobs_test').add({
        'title': 'Кладовщик (тест)',
        'city': 'Тарту',
        'country': 'Эстония',
        'salaryText': '1200 EUR/мес',
        'category': 'Склад',
        'type': 'Частичная занятость',
        'experience': '1–2 года',
        'description': 'Ещё одна тестовая вакансия.',
        'housingProvided': false,
        'transportProvided': true,
        'teenFriendly': false,
        'employerId': 'test_employer',
        'createdAt': now,
        'updatedAt': now,
        'test': true,
      });

      // ====== TEST CVS ======
      await db.collection('cvs_test').add({
        'ownerUid': null,
        'contacts': {
          'name': 'Тестовый Кандидат',
          'email': 'test@example.com',
          'phone': '+372 0000 0000',
        },
        'title': 'CV: Уборка / Клининг (тест)',
        'summary': 'Тестовое CV для проверки предложений/откликов.',
        'experience': [
          {'position': 'Уборщик', 'company': 'Test OÜ', 'description': 'Тестовое описание'}
        ],
        'languages': [
          {'language': 'Русский', 'level': 'Свободный'}
        ],
        'education': [],
        'desired': {
          'category': 'Клининг',
          'positions': ['Уборщик'],
          'locations': ['Таллинн'],
          'employmentTypes': ['Полная занятость'],
        },
        'createdAt': now,
        'updatedAt': now,
        'source': 'seed',
        'mode': 'test',
        'test': true,
      });

      // ====== OPTIONAL: TEST APPLICATION ======
      await db.collection('applications').add({
        'type': 'apply',
        'vacancyId': job1.id,
        'jobId': job1.id,
        'applicantId': 'test_worker',
        'candidateOwnerId': 'test_worker',
        'employerOwnerId': 'test_employer',
        'createdAt': now,
        'updatedAt': now,
        'status': 'sent',
        'test': true,
      });

      await metaRef.set({'seeded_$kSeedDoc': true, 'seededAt': now}, SetOptions(merge: true));
    } catch (_) {
      // тестовый сервис не должен валить приложение
    }
  }
}
