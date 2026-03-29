import 'dart:async';

import 'package:flutter/foundation.dart';

typedef MonetizationAnalyticsSink =
    Future<void> Function(String eventName, Map<String, Object?> params);

class MonetizationAnalytics {
  MonetizationAnalytics({MonetizationAnalyticsSink? sink})
    : _sink = sink ?? _debugSink;

  static final MonetizationAnalytics instance = MonetizationAnalytics();

  final MonetizationAnalyticsSink _sink;

  static Future<void> _debugSink(
    String eventName,
    Map<String, Object?> params,
  ) async {
    if (!kDebugMode) return;
    debugPrint('[monetization] $eventName $params');
  }

  static String candidateSafeId(String? rawId) {
    final input = (rawId ?? '').trim();
    if (input.isEmpty) return '';
    var hash = 0x811C9DC5;
    for (final codeUnit in input.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  void trackPaywallOpened({
    required String entryPoint,
    String? candidateId,
    String? packId,
    int? creditsBefore,
    String? ctaVariant,
    String? socialProofVariant,
    String? valueVariant,
    String? firstTimeVariant,
    bool? isFirstUnlockMode,
  }) {
    _track('paywall_opened', <String, Object?>{
      'entry_point': entryPoint,
      'pack_id': packId ?? '',
      'credits_before': creditsBefore,
      'candidate_safe_id': candidateSafeId(candidateId),
      'cta_variant': ctaVariant,
      'social_proof_variant': socialProofVariant,
      'value_variant': valueVariant,
      'first_time_variant': firstTimeVariant,
      'is_first_unlock_mode': isFirstUnlockMode == null
          ? null
          : (isFirstUnlockMode ? 1 : 0),
    });
  }

  void trackPackSelected({
    required String entryPoint,
    required String packId,
    int? creditsBefore,
    String? candidateId,
  }) {
    _track('pack_selected', <String, Object?>{
      'entry_point': entryPoint,
      'pack_id': packId,
      'credits_before': creditsBefore,
      'candidate_safe_id': candidateSafeId(candidateId),
    });
  }

  void trackPurchaseStarted({
    required String entryPoint,
    required String packId,
    int? creditsBefore,
    String? candidateId,
  }) {
    _track('purchase_started', <String, Object?>{
      'entry_point': entryPoint,
      'pack_id': packId,
      'credits_before': creditsBefore,
      'candidate_safe_id': candidateSafeId(candidateId),
    });
  }

  void trackPurchaseSuccess({
    required String entryPoint,
    required String packId,
    int? creditsBefore,
    int? creditsAfter,
    String? candidateId,
  }) {
    _track('purchase_success', <String, Object?>{
      'entry_point': entryPoint,
      'pack_id': packId,
      'credits_before': creditsBefore,
      'credits_after': creditsAfter,
      'result_status': 'success',
      'candidate_safe_id': candidateSafeId(candidateId),
    });
  }

  void trackPurchaseFailed({
    required String entryPoint,
    required String packId,
    int? creditsBefore,
    int? creditsAfter,
    String? resultStatus,
    String? candidateId,
  }) {
    _track('purchase_failed', <String, Object?>{
      'entry_point': entryPoint,
      'pack_id': packId,
      'credits_before': creditsBefore,
      'credits_after': creditsAfter,
      'result_status': (resultStatus ?? 'failed').trim(),
      'candidate_safe_id': candidateSafeId(candidateId),
    });
  }

  void trackContactUnlockTap({
    required String entryPoint,
    required String candidateId,
    int? creditsBefore,
  }) {
    _track('contact_unlock_tap', <String, Object?>{
      'entry_point': entryPoint,
      'candidate_safe_id': candidateSafeId(candidateId),
      'credits_before': creditsBefore,
    });
  }

  void trackContactUnlockConfirmed({
    required String entryPoint,
    required String candidateId,
    int? creditsBefore,
  }) {
    _track('contact_unlock_confirmed', <String, Object?>{
      'entry_point': entryPoint,
      'candidate_safe_id': candidateSafeId(candidateId),
      'credits_before': creditsBefore,
    });
  }

  void trackContactUnlockSuccess({
    required String entryPoint,
    required String candidateId,
    int? creditsBefore,
    int? creditsAfter,
  }) {
    _track('contact_unlock_success', <String, Object?>{
      'entry_point': entryPoint,
      'candidate_safe_id': candidateSafeId(candidateId),
      'credits_before': creditsBefore,
      'credits_after': creditsAfter,
      'result_status': 'success',
    });
  }

  void trackContactUnlockFailed({
    required String entryPoint,
    required String candidateId,
    int? creditsBefore,
    int? creditsAfter,
    String? resultStatus,
  }) {
    _track('contact_unlock_failed', <String, Object?>{
      'entry_point': entryPoint,
      'candidate_safe_id': candidateSafeId(candidateId),
      'credits_before': creditsBefore,
      'credits_after': creditsAfter,
      'result_status': (resultStatus ?? 'failed').trim(),
    });
  }

  void trackContactAlreadyUnlocked({
    required String entryPoint,
    required String candidateId,
    int? creditsBefore,
  }) {
    _track('contact_already_unlocked', <String, Object?>{
      'entry_point': entryPoint,
      'candidate_safe_id': candidateSafeId(candidateId),
      'credits_before': creditsBefore,
      'result_status': 'already_unlocked',
    });
  }

  void trackPurchaseWalletSyncPending({
    required String entryPoint,
    required String packId,
    int? creditsBefore,
    int? creditsAfter,
    String? candidateId,
  }) {
    _track('purchase_wallet_sync_pending', <String, Object?>{
      'entry_point': entryPoint,
      'pack_id': packId,
      'credits_before': creditsBefore,
      'credits_after': creditsAfter,
      'candidate_safe_id': candidateSafeId(candidateId),
      'result_status': 'wallet_sync_pending',
    });
  }

  void trackPurchaseWalletSyncedAfterDelay({
    required String entryPoint,
    required String packId,
    int? creditsBefore,
    int? creditsAfter,
    String? candidateId,
    int? attempt,
  }) {
    _track('purchase_wallet_synced_after_delay', <String, Object?>{
      'entry_point': entryPoint,
      'pack_id': packId,
      'credits_before': creditsBefore,
      'credits_after': creditsAfter,
      'candidate_safe_id': candidateSafeId(candidateId),
      'attempt': attempt,
      'result_status': 'wallet_synced_after_delay',
    });
  }

  void trackConsumeInsufficientCreditsAfterPurchase({
    required String entryPoint,
    required String candidateId,
    int? creditsBefore,
    int? creditsAfter,
    int? attempt,
  }) {
    _track('consume_insufficient_after_purchase', <String, Object?>{
      'entry_point': entryPoint,
      'candidate_safe_id': candidateSafeId(candidateId),
      'credits_before': creditsBefore,
      'credits_after': creditsAfter,
      'attempt': attempt,
      'result_status': 'insufficient_after_purchase',
    });
  }

  void trackUnlockSucceededAfterRetry({
    required String entryPoint,
    required String candidateId,
    int? creditsBefore,
    int? creditsAfter,
    int? attempt,
  }) {
    _track('contact_unlock_succeeded_after_retry', <String, Object?>{
      'entry_point': entryPoint,
      'candidate_safe_id': candidateSafeId(candidateId),
      'credits_before': creditsBefore,
      'credits_after': creditsAfter,
      'attempt': attempt,
      'result_status': 'unlock_succeeded_after_retry',
    });
  }

  void trackUnlockFailedAfterStabilization({
    required String entryPoint,
    required String candidateId,
    int? creditsBefore,
    int? creditsAfter,
    String? resultStatus,
  }) {
    _track('contact_unlock_failed_after_stabilization', <String, Object?>{
      'entry_point': entryPoint,
      'candidate_safe_id': candidateSafeId(candidateId),
      'credits_before': creditsBefore,
      'credits_after': creditsAfter,
      'result_status': (resultStatus ?? 'failed_after_stabilization').trim(),
    });
  }

  void trackAlreadyUnlockedDuringStabilization({
    required String entryPoint,
    required String candidateId,
    int? creditsBefore,
    int? attempt,
  }) {
    _track('contact_already_unlocked_during_stabilization', <String, Object?>{
      'entry_point': entryPoint,
      'candidate_safe_id': candidateSafeId(candidateId),
      'credits_before': creditsBefore,
      'attempt': attempt,
      'result_status': 'already_unlocked_during_stabilization',
    });
  }

  void trackCreditsScreenOpened({
    required String entryPoint,
    int? creditsBefore,
  }) {
    _track('credits_screen_opened', <String, Object?>{
      'entry_point': entryPoint,
      'credits_before': creditsBefore,
    });
  }

  void _track(String eventName, Map<String, Object?> params) {
    final payload = <String, Object?>{};
    params.forEach((key, value) {
      if (value == null) return;
      if (value is String && value.trim().isEmpty) return;
      payload[key] = value;
    });
    unawaited(
      _sink(eventName, payload).catchError((_) {
        if (kDebugMode) {
          debugPrint('[monetization] failed to log $eventName');
        }
      }),
    );
  }
}
