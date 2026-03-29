import 'package:flutter/material.dart';

class CreditBalanceChip extends StatelessWidget {
  final int balance;
  const CreditBalanceChip({super.key, required this.balance});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF3FF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'Кредиты: $balance',
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }
}
