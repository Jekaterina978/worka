import 'interaction_status.dart';
import 'package:flutter/material.dart';
import '../theme/worka_colors.dart';

enum InteractionCardState { sent, viewed, accepted, rejected }

enum InteractionStatusContext {
  generic,
  employerApplications,
  workerApplications,
  employerOffers,
  workerOffers,
}

class InteractionCardPresentation {
  const InteractionCardPresentation({
    required this.state,
    required this.label,
    required this.backgroundColor,
  });

  final InteractionCardState state;
  final String label;
  final Color backgroundColor;
}

class InteractionCardStatusResolver {
  InteractionCardStatusResolver._();

  static InteractionCardState resolve(
    String rawStatus, {
    required bool isOffer,
  }) {
    final normalized = InteractionStatus.normalize(rawStatus);
    if (normalized == InteractionStatus.accepted) {
      return InteractionCardState.accepted;
    }
    if (normalized == InteractionStatus.rejected) {
      return InteractionCardState.rejected;
    }
    if (normalized == InteractionStatus.viewed ||
        normalized == InteractionStatus.postponed) {
      return InteractionCardState.viewed;
    }
    return InteractionCardState.sent;
  }

  static bool isFinal(InteractionCardState state) {
    return state == InteractionCardState.accepted ||
        state == InteractionCardState.rejected;
  }

  static String label(InteractionCardState state) {
    switch (state) {
      case InteractionCardState.accepted:
        return 'Принято';
      case InteractionCardState.rejected:
        return 'Отклонено';
      case InteractionCardState.viewed:
        return 'Просмотрено';
      case InteractionCardState.sent:
        return 'Отправлено';
    }
  }

  static InteractionCardPresentation presentation(
    String rawStatus, {
    required InteractionStatusContext context,
  }) {
    final state = resolve(rawStatus, isOffer: false);
    switch (state) {
      case InteractionCardState.accepted:
        return const InteractionCardPresentation(
          state: InteractionCardState.accepted,
          label: 'Принято',
          backgroundColor: Color(0xFF22C55E),
        );
      case InteractionCardState.rejected:
        return const InteractionCardPresentation(
          state: InteractionCardState.rejected,
          label: 'Отклонено',
          backgroundColor: Color(0xFFEF4444),
        );
      case InteractionCardState.viewed:
        return InteractionCardPresentation(
          state: InteractionCardState.viewed,
          label: switch (context) {
            InteractionStatusContext.employerOffers => 'Просмотрено',
            InteractionStatusContext.workerOffers => 'Просмотрено',
            InteractionStatusContext.workerApplications =>
              'Просмотрено работодателем',
            _ => 'Просмотрено',
          },
          backgroundColor: WorkaColors.blue,
        );
      case InteractionCardState.sent:
        return InteractionCardPresentation(
          state: InteractionCardState.sent,
          label: switch (context) {
            InteractionStatusContext.employerApplications => 'Новый отклик',
            InteractionStatusContext.workerApplications => 'Отклик отправлен',
            InteractionStatusContext.employerOffers => 'Предложение отправлено',
            InteractionStatusContext.workerOffers => 'Новое предложение',
            InteractionStatusContext.generic => 'Отправлено',
          },
          backgroundColor: const Color(0xFFFF8A00),
        );
    }
  }
}
