import 'package:flutter/material.dart';

import '../../domain/entities/credit_transaction.dart';

class CreditTransactionList extends StatelessWidget {
  final List<CreditTransaction> items;
  const CreditTransactionList({super.key, required this.items});

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const Text('История пуста');
    return Column(
      children: items
          .map(
            (e) => ListTile(
              dense: true,
              title: Text(e.reason),
              trailing: Text('${e.delta > 0 ? '+' : ''}${e.delta}'),
            ),
          )
          .toList(),
    );
  }
}
