import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:worka/controllers/paid_entitlements_controller.dart';
import 'package:worka/theme/worka_colors.dart';

import '../models/vacancy_payment_display.dart';
import '../payments_i18n.dart';
import '../repository/payments_repository.dart';
import '../widgets/money_primary_button.dart';

class PromoteJobScreen extends StatefulWidget {
  const PromoteJobScreen({super.key, required this.jobCode});

  final String jobCode;

  @override
  State<PromoteJobScreen> createState() => _PromoteJobScreenState();
}

class _VacancyPaymentDisplayTile extends StatelessWidget {
  const _VacancyPaymentDisplayTile({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final VacancyPaymentDisplayItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Ink(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFFFF7EF) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? WorkaColors.orange : WorkaColors.divider,
            width: selected ? 1.4 : 1,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: WorkaColors.orange.withValues(alpha: 0.16),
                    blurRadius: 14,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    style: const TextStyle(
                      color: WorkaColors.textDark,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (item.subtitle.trim().isNotEmpty)
                    Text(
                      item.subtitle,
                      style: const TextStyle(
                        color: WorkaColors.textGreyDark,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
            ),
            Text(
              item.priceLabel,
              style: const TextStyle(
                color: WorkaColors.orange,
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PromoteJobScreenState extends State<PromoteJobScreen> {
  final _repo = PaymentsRepository();
  late final List<VacancyPaymentDisplayItem> _products =
      VacancyPaymentDisplayCatalog.allProducts;
  late VacancyPaymentDisplayItem _selected;
  bool _loading = false;

  String get _safeJobCode => widget.jobCode.trim();

  @override
  void initState() {
    super.initState();
    assert(
      _products.length == 4,
      'Vacancy promotion must render exactly 4 tariffs from VacancyPaymentFeatures.displayOrder',
    );
    _selected = _products.first;
  }

  Future<void> _pay() async {
    if (_safeJobCode.isEmpty) return;
    setState(() => _loading = true);
    try {
      final checkoutUrl = await _repo.createVacancyCheckoutSessionUrl(
        canonicalProductId: _selected.canonicalProductId,
        jobId: _safeJobCode, // repo still expects jobId param; value is jobCode
        returnOrigin: kIsWeb ? Uri.base.origin : null,
        sourceScreen: 'promote_job_screen',
      );
      final uri = Uri.parse(checkoutUrl);
      final opened = await launchUrl(
        uri,
        mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.inAppBrowserView,
        webOnlyWindowName: kIsWeb ? '_self' : null,
      );
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Не удалось открыть оплату')),
        );
      } else if (!mounted) {
        return;
      } else {
        Navigator.maybePop(context);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка оплаты: $e'),
          backgroundColor: Colors.red.shade700,
        ),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_safeJobCode.isEmpty) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.white,
          elevation: 0,
          title: Text(
            PaymentsI18n.t(context, 'promote_job'),
            style: const TextStyle(
              color: WorkaColors.blue,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        body: const Center(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'Не удалось определить вакансию. Вернитесь к поиску и откройте продвижение заново.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: WorkaColors.textGreyDark,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        title: Text(
          PaymentsI18n.t(context, 'promote_job'),
          style: const TextStyle(
            color: WorkaColors.blue,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          _ActiveStatusChips(jobId: _safeJobCode),
          const SizedBox(height: 8),
          ..._products.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _VacancyPaymentDisplayTile(
                item: item,
                selected:
                    _selected.canonicalProductId == item.canonicalProductId,
                onTap: () => setState(() => _selected = item),
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: MoneyPrimaryButton(
              text: '${PaymentsI18n.t(context, 'pay')} ${_selected.priceLabel}',
              onPressed: _pay,
              isLoading: _loading,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActiveStatusChips extends StatelessWidget {
  const _ActiveStatusChips({required this.jobId});

  final String jobId;

  @override
  Widget build(BuildContext context) {
    final paid = context.watch<PaidEntitlementsController>();
    if (jobId.isNotEmpty && paid.jobEntitlementsById[jobId] == null) {
      Future.microtask(() => paid.refreshJobEntitlements(jobId));
    }
    final chips = <Widget>[];
    if (paid.hasJobFeature(jobId, 'highlight')) {
      chips.add(_pill('Выделение активно', WorkaColors.orange));
    }
    if (paid.hasJobFeature(jobId, 'urgent')) {
      chips.add(_pill('Срочно активно', Colors.redAccent));
    }
    if (paid.hasJobFeature(jobId, 'bump')) {
      chips.add(_pill('Поднято', Colors.blueGrey));
    }
    if (chips.isEmpty) return const SizedBox.shrink();
    return Wrap(spacing: 8, runSpacing: 6, children: chips);
  }

  Widget _pill(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}
