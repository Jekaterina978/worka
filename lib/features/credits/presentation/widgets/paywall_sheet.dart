import 'package:flutter/material.dart';

import '../controllers/credit_controller.dart';
import 'credit_pack_tile.dart';
import '../../../../shared/widgets/app_button.dart';
import '../../../../shared/widgets/bottom_sheet_container.dart';

class PaywallSheet extends StatelessWidget {
  final String? candidateName;
  final CreditController controller;

  const PaywallSheet({super.key, this.candidateName, required this.controller});

  @override
  Widget build(BuildContext context) {
    final state = controller.state;
    return BottomSheetContainer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Открыть контакт кандидата',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          if ((candidateName ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              candidateName!,
              style: const TextStyle(
                color: Color(0xFF2D5BCA),
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
          const SizedBox(height: 10),
          ...state.packs.map(
            (p) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: CreditPackTile(
                pack: p,
                selected: state.selectedPack?.id == p.id,
                onTap: () => controller.selectPack(p),
              ),
            ),
          ),
          const SizedBox(height: 8),
          AppButton(
            text: state.selectedPack == null
                ? 'Выберите пакет'
                : (state.selectedPack!.contacts == 1
                      ? 'Открыть за ${state.selectedPack!.priceLabel}'
                      : 'Купить пакет ${state.selectedPack!.priceLabel}'),
            onPressed: state.selectedPack == null
                ? null
                : () async {
                    final ok = await controller.buySelected();
                    if (!context.mounted) return;
                    if (ok) Navigator.pop(context, true);
                  },
            loading: state.loading,
          ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
        ],
      ),
    );
  }
}
