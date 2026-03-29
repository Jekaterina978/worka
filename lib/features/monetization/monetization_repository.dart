import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:worka/services/firestore_paths.dart';

import 'pricing.dart';

class WorkerEntitlements {
  final int activeCvLimit;
  final bool hasWorkerPlus;
  final int boostsPerWeek;
  final bool priorityRanking;
  final bool verified;

  const WorkerEntitlements({
    required this.activeCvLimit,
    required this.hasWorkerPlus,
    required this.boostsPerWeek,
    required this.priorityRanking,
    required this.verified,
  });
}

class EmployerEntitlements {
  final EmployerType employerType;
  final EmployerPlan plan;
  final int activeJobLimit;
  final int includedCreditsMonthly;
  final int bumpsMonthly;
  final int urgentMonthly;

  const EmployerEntitlements({
    required this.employerType,
    required this.plan,
    required this.activeJobLimit,
    required this.includedCreditsMonthly,
    required this.bumpsMonthly,
    required this.urgentMonthly,
  });
}

class MonetizationRepository {
  MonetizationRepository(this._db);

  final FirebaseFirestore _db;

  static int workerCvLimitFromUser(Map<String, dynamic> user) {
    final freeLimit = MonetizationPricing.workerFreeActiveCvLimit;
    final raw = user['activeCvLimit'];
    if (raw is int && raw > 0) return raw < freeLimit ? freeLimit : raw;

    final worker = user['worker'] is Map
        ? Map<String, dynamic>.from(user['worker'] as Map)
        : const <String, dynamic>{};
    final wRaw = worker['activeCvLimit'];
    if (wRaw is int && wRaw > 0) return wRaw < freeLimit ? freeLimit : wRaw;

    final planRaw = (user['workerPlan'] ?? worker['plan'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    if (planRaw == 'worker_plus') {
      return freeLimit + MonetizationPricing.workerPlusExtraCv;
    }
    return freeLimit;
  }

  Future<Map<String, dynamic>> getUserDoc(String uid) async {
    final snap = await _db.collection('users').doc(uid).get();
    return snap.data() ?? const <String, dynamic>{};
  }

  Stream<int> watchWorkerCvLimit(String uid) {
    return _db.collection('users').doc(uid).snapshots().map((snap) {
      final data = snap.data() ?? const <String, dynamic>{};
      return workerCvLimitFromUser(data);
    });
  }

  Future<WorkerEntitlements> getWorkerEntitlements(String uid) async {
    final data = await getUserDoc(uid);
    final worker = data['worker'] is Map
        ? Map<String, dynamic>.from(data['worker'] as Map)
        : const <String, dynamic>{};
    final planRaw = (data['workerPlan'] ?? worker['plan'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final hasWorkerPlus = planRaw == 'worker_plus';
    return WorkerEntitlements(
      activeCvLimit: workerCvLimitFromUser(data),
      hasWorkerPlus: hasWorkerPlus,
      boostsPerWeek: hasWorkerPlus ? 1 : 0,
      priorityRanking: hasWorkerPlus,
      verified: (worker['verified'] == true) || (data['verified'] == true),
    );
  }

  Future<EmployerEntitlements> getEmployerEntitlements(String uid) async {
    final data = await getUserDoc(uid);
    final business = data['business'] is Map
        ? Map<String, dynamic>.from(data['business'] as Map)
        : const <String, dynamic>{};

    final typeRaw =
        (data['employerType'] ?? business['employerType'] ?? 'private')
            .toString()
            .trim()
            .toLowerCase();
    final EmployerType type = switch (typeRaw) {
      'agency' => EmployerType.agency,
      'business' || 'company' => EmployerType.business,
      _ => EmployerType.private,
    };

    final planRaw =
        (data['employerPlan'] ??
                business['plan'] ??
                data['plan'] ??
                'private_free')
            .toString()
            .trim()
            .toLowerCase();
    final EmployerPlan plan = switch (planRaw) {
      'private_plus' => EmployerPlan.privatePlus,
      'private_starter' => EmployerPlan.privateStarter,
      _ => EmployerPlan.privateFree,
    };

    if (type != EmployerType.private) {
      return const EmployerEntitlements(
        employerType: EmployerType.business,
        plan: EmployerPlan.privateFree,
        activeJobLimit: 1,
        includedCreditsMonthly: 0,
        bumpsMonthly: 0,
        urgentMonthly: 0,
      );
    }

    return switch (plan) {
      EmployerPlan.privateStarter => const EmployerEntitlements(
        employerType: EmployerType.private,
        plan: EmployerPlan.privateStarter,
        activeJobLimit: MonetizationPricing.privateStarterActiveJobs,
        includedCreditsMonthly: MonetizationPricing.privateStarterCredits,
        bumpsMonthly: MonetizationPricing.privateStarterBumps,
        urgentMonthly: MonetizationPricing.privateStarterUrgent,
      ),
      EmployerPlan.privatePlus => const EmployerEntitlements(
        employerType: EmployerType.private,
        plan: EmployerPlan.privatePlus,
        activeJobLimit: MonetizationPricing.privatePlusActiveJobs,
        includedCreditsMonthly: MonetizationPricing.privatePlusCredits,
        bumpsMonthly: MonetizationPricing.privatePlusBumps,
        urgentMonthly: MonetizationPricing.privatePlusUrgent,
      ),
      EmployerPlan.privateFree => const EmployerEntitlements(
        employerType: EmployerType.private,
        plan: EmployerPlan.privateFree,
        activeJobLimit: MonetizationPricing.privateFreeActiveJobs,
        includedCreditsMonthly: MonetizationPricing.privateFreeCredits,
        bumpsMonthly: 0,
        urgentMonthly: 0,
      ),
    };
  }

  Future<int> countActiveVacancies(String uid) async {
    final snap = await _db
        .collection(FirestorePaths.vacancies)
        .where('ownerId', isEqualTo: uid)
        .where('isDeleted', isEqualTo: false)
        .where('isDraft', isEqualTo: false)
        .get();
    return snap.docs.length;
  }
}
