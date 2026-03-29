import 'package:flutter/material.dart';
import 'package:worka/theme/worka_colors.dart';

import '../models/employer_payment_models.dart';
import '../payments_i18n.dart';
import '../repository/payments_repository.dart';

class VerificationStatusScreen extends StatefulWidget {
  const VerificationStatusScreen({super.key});

  @override
  State<VerificationStatusScreen> createState() => _VerificationStatusScreenState();
}

class _VerificationStatusScreenState extends State<VerificationStatusScreen> {
  final _repo = PaymentsRepository();

  VerificationStatusResult? _status;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await _repo.getVerificationStatus();
      if (!mounted) return;
      setState(() => _status = data);
    } catch (_) {
      if (!mounted) return;
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'pending':
        return PaymentsI18n.t(context, 'status_pending');
      case 'approved':
        return PaymentsI18n.t(context, 'status_approved');
      case 'rejected':
        return PaymentsI18n.t(context, 'status_rejected');
      default:
        return PaymentsI18n.t(context, 'status_none');
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'approved':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      default:
        return WorkaColors.textGreyDark;
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _status?.status ?? 'none';
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        title: Text(
          PaymentsI18n.t(context, 'verification'),
          style: const TextStyle(color: WorkaColors.blue, fontWeight: FontWeight.w900),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
          : Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: WorkaColors.fieldBorder),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.verified_user_outlined, color: _statusColor(status)),
                        const SizedBox(width: 10),
                        Text(
                          _statusLabel(status),
                          style: TextStyle(
                            color: _statusColor(status),
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if ((_status?.notes ?? '').isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      _status!.notes,
                      style: const TextStyle(
                        color: WorkaColors.textGreyDark,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: OutlinedButton(
                      onPressed: _load,
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: WorkaColors.blue),
                        foregroundColor: WorkaColors.blue,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text('Обновить статус'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
