import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../contact_access_controller.dart';
import '../models/employer_payment_models.dart';

class CandidateContactSection extends StatefulWidget {
  const CandidateContactSection({
    super.key,
    required this.candidateId,
    required this.candidateName,
    required this.lockedBuilder,
    required this.unlockedBuilder,
  });

  final String candidateId;
  final String candidateName;
  final Widget Function(VoidCallback onUnlock, bool loading) lockedBuilder;
  final Widget Function(CandidateContact? contact) unlockedBuilder;

  @override
  State<CandidateContactSection> createState() =>
      _CandidateContactSectionState();
}

class _CandidateContactSectionState extends State<CandidateContactSection> {
  final _controller = ContactAccessController.instance;
  bool _loading = false;
  CandidateContact? _contact;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onControllerChanged);
    _contact = _controller.contactForCandidate(widget.candidateId);
    _controller
        .bootstrap(uid: FirebaseAuth.instance.currentUser?.uid)
        .then((_) {
          if (!mounted) return;
          setState(() {
            _contact = _controller.contactForCandidate(widget.candidateId);
          });
        })
        .catchError((_) {});
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (!mounted) return;
    setState(() {
      _contact = _controller.contactForCandidate(widget.candidateId);
    });
  }

  void _showMessage(String text) {
    final message = text.trim();
    if (message.isEmpty) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _unlockNow() async {
    if (_loading || _controller.isUnlockInProgress(widget.candidateId)) {
      return;
    }
    setState(() => _loading = true);
    try {
      final result = await _controller.ensureContactUnlocked(
        context,
        candidateId: widget.candidateId,
        candidateName: widget.candidateName,
        entryPoint: 'candidate_contact_section',
      );
      if (!mounted) return;

      switch (result.status) {
        case ContactUnlockStatus.unlocked:
        case ContactUnlockStatus.alreadyUnlocked:
          break;
        case ContactUnlockStatus.purchasePending:
          _showMessage(
            result.message.isNotEmpty
                ? result.message
                : 'Платёж обрабатывается...',
          );
          break;
        case ContactUnlockStatus.cancelled:
          _showMessage(
            result.message.isNotEmpty ? result.message : 'Операция отменена',
          );
          break;
        case ContactUnlockStatus.failed:
          _showMessage(
            result.message.isNotEmpty
                ? result.message
                : 'Не удалось открыть контакты',
          );
          break;
      }

      setState(() {
        _loading = false;
        _contact =
            result.contact ??
            _controller.contactForCandidate(widget.candidateId) ??
            _contact;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      _showMessage('Не удалось открыть контакты');
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasAccess = _controller.hasAccessToCandidateContact(
      widget.candidateId,
    );
    debugPrint(
      '[CANDIDATE_SECTION] rebuild candidateId=${widget.candidateId} '
      'hasAccess=$hasAccess hasContact=${_contact != null} ctrlHash=${identityHashCode(_controller)}',
    );
    final busy = _loading || _controller.isUnlockInProgress(widget.candidateId);
    if (!hasAccess) {
      return widget.lockedBuilder(_unlockNow, busy);
    }
    return widget.unlockedBuilder(_contact);
  }
}
