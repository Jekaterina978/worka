import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/firestore_paths.dart';
import '../theme/worka_colors.dart';
import 'status_pill_badge.dart';

class CandidateOfferSentBadge extends StatelessWidget {
  const CandidateOfferSentBadge({
    super.key,
    required this.employerUid,
    required this.candidateOwnerId,
    this.compact = false,
  });

  final String employerUid;
  final String candidateOwnerId;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return CandidateOfferSentBuilder(
      employerUid: employerUid,
      candidateOwnerId: candidateOwnerId,
      builder: (context, hasOffer) {
        if (!hasOffer) return const SizedBox.shrink();
        return StatusPillBadge(
          label: 'Предложение отправлено',
          backgroundColor: WorkaColors.blue,
          textColor: Colors.white,
          padding: compact
              ? const EdgeInsets.symmetric(horizontal: 8, vertical: 4)
              : const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          fontSize: compact ? 10.5 : 11.5,
        );
      },
    );
  }
}

class CandidateOfferSentBuilder extends StatelessWidget {
  const CandidateOfferSentBuilder({
    super.key,
    required this.employerUid,
    required this.candidateOwnerId,
    required this.builder,
  });

  final String employerUid;
  final String candidateOwnerId;
  final Widget Function(BuildContext context, bool hasOffer) builder;

  @override
  Widget build(BuildContext context) {
    final employer = employerUid.trim();
    final candidate = candidateOwnerId.trim();
    if (employer.isEmpty || candidate.isEmpty) {
      return builder(context, false);
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection(FirestorePaths.jobOffers)
          .where('type', isEqualTo: 'offer')
          .where('employerOwnerId', isEqualTo: employer)
          .where('candidateOwnerId', isEqualTo: candidate)
          .where(
            'status',
            whereIn: const ['sent', 'viewed', 'accepted', 'rejected'],
          )
          .limit(1)
          .snapshots(),
      builder: (context, snap) {
        final hasOffer = (snap.data?.docs ?? const []).isNotEmpty;
        return builder(context, hasOffer);
      },
    );
  }
}
