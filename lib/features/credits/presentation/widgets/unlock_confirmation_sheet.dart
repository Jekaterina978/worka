import 'package:flutter/material.dart';

class UnlockConfirmationSheet extends StatelessWidget {
  final int creditsLeft;
  const UnlockConfirmationSheet({super.key, required this.creditsLeft});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Контакт открыт',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
          ),
          const SizedBox(height: 6),
          Text('Кредитов осталось: $creditsLeft'),
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Ок'),
          ),
        ],
      ),
    );
  }
}
