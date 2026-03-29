part of 'package:worka/screens/profile_screen.dart';

Widget buildMenuRow({
  required Color iconBg,
  required Color iconColor,
  required IconData icon,
  required String title,
  required Widget badge,
  required VoidCallback onTap,
}) {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    child: Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 16,
                offset: const Offset(0, 4),
              ),
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: iconBg,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 18, color: iconColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF101828),
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              badge,
              const SizedBox(width: 6),
              const Icon(
                Icons.chevron_right,
                color: Color(0xFF74809A),
                size: 18,
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

Widget buildMenuCardBusiness(
  _ProfileScreenState s, {
  required String businessUid,
  required bool isTestMode,
}) {
  return Container(
    margin: const EdgeInsets.symmetric(horizontal: 16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.08),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: Column(
      children: [
        buildMenuRow(
          iconBg: const Color(0xFFEEF3FF),
          iconColor: const Color(0xFF4A6FDB),
          icon: Icons.work_outline_rounded,
          title: 'Мои вакансии',
          badge: StreamBuilder<int>(
            stream: s._jobsCount(businessUid, ownerType: 'business'),
            builder: (ctx, snap) => Text(
              '${snap.data ?? 0}',
              style: const TextStyle(
                color: Color(0xFF4A6FDB),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          onTap: () => Navigator.push(
            s.context,
            MaterialPageRoute(
              builder: (_) => MyPublicationsScreen(
                testMode: isTestMode,
                showEditActions: true,
              ),
            ),
          ),
        ),
        const Divider(height: 1, color: Color(0xFFE9EDF4)),
        buildMenuRow(
          iconBg: const Color(0xFFEEF3FF),
          iconColor: const Color(0xFF4A6FDB),
          icon: Icons.local_offer_outlined,
          title: 'Мои предложения',
          badge: StreamBuilder<ResponseStats>(
            stream: s._employerOffersSentStats(
              businessUid,
              profileType: 'business',
            ),
            builder: (ctx, snap) => Text(
              '${snap.data?.total ?? 0}',
              style: const TextStyle(
                color: Color(0xFF4A6FDB),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          onTap: () => Navigator.push(
            s.context,
            MaterialPageRoute(
              builder: (_) => OffersListScreen(
                testMode: isTestMode,
                workerUid: '',
                employerUid: businessUid,
                profileType: 'business',
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

Widget buildMenuCardPersonal(
  _ProfileScreenState s, {
  required String uid,
  required bool isTestMode,
}) {
  return Container(
    margin: const EdgeInsets.symmetric(horizontal: 16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.08),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 6,
          offset: const Offset(0, 2),
        ),
      ],
    ),
    child: Column(
      children: [
        buildMenuRow(
          iconBg: const Color(0xFFEEF3FF),
          iconColor: const Color(0xFF4A6FDB),
          icon: Icons.description_outlined,
          title: 'CV',
          badge: StreamBuilder<int>(
            stream: s._cvCount(uid),
            builder: (ctx, snap) => Text(
              '${snap.data ?? 0}',
              style: const TextStyle(
                color: Color(0xFF4A6FDB),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          onTap: s._openMyCvs,
        ),
        const Divider(height: 1, color: Color(0xFFE9EDF4)),
        buildMenuRow(
          iconBg: const Color(0xFFEEF3FF),
          iconColor: const Color(0xFF4A6FDB),
          icon: Icons.work_outline_rounded,
          title: 'Отклики на вакансии',
          badge: StreamBuilder<ResponseStats>(
            stream: s._workerResponsesSentStats(uid),
            builder: (ctx, snap) => Text(
              '${snap.data?.total ?? 0}',
              style: const TextStyle(
                color: Color(0xFF4A6FDB),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          onTap: () => Navigator.push(
            s.context,
            MaterialPageRoute(
              builder: (_) => ApplicationsListScreen(
                testMode: isTestMode,
                jobId: '',
                employerUid: '',
                candidateUid: uid,
                profileType: 'personal',
              ),
            ),
          ),
        ),
        const Divider(height: 1, color: Color(0xFFE9EDF4)),
        buildMenuRow(
          iconBg: const Color(0xFFEEF3FF),
          iconColor: const Color(0xFF4A6FDB),
          icon: Icons.local_offer_outlined,
          title: 'Мои предложения',
          badge: StreamBuilder<ResponseStats>(
            stream: s._employerOffersSentStats(
              uid,
              profileType: 'personal',
            ),
            builder: (ctx, snap) => Text(
              '${snap.data?.total ?? 0}',
              style: const TextStyle(
                color: Color(0xFF4A6FDB),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          onTap: () => Navigator.push(
            s.context,
            MaterialPageRoute(
              builder: (_) => OffersListScreen(
                testMode: isTestMode,
                workerUid: '',
                employerUid: uid,
                profileType: 'personal',
              ),
            ),
          ),
        ),
        const Divider(height: 1, color: Color(0xFFE9EDF4)),
        buildMenuRow(
          iconBg: const Color(0xFFEEF3FF),
          iconColor: const Color(0xFF4A6FDB),
          icon: Icons.work_outline_rounded,
          title: 'Вакансии',
          badge: StreamBuilder<int>(
            stream: s._jobsCount(uid, ownerType: 'personal'),
            builder: (ctx, snap) => Text(
              '${snap.data ?? 0}',
              style: const TextStyle(
                color: Color(0xFF4A6FDB),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          onTap: () => Navigator.push(
            s.context,
            MaterialPageRoute(
              builder: (_) => MyPublicationsScreen(
                testMode: isTestMode,
                showEditActions: true,
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
