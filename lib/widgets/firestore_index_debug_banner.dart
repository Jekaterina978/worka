import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/worka_colors.dart';

class FirestoreIndexDebugBanner extends StatelessWidget {
  const FirestoreIndexDebugBanner({
    super.key,
    required this.fullMessage,
  });

  final String fullMessage;

  static String extractIndexUrl(String message) {
    final re = RegExp(r'https://console\.firebase\.google\.com[^\s]+');
    final m = re.firstMatch(message);
    return m?.group(0) ?? '';
  }

  @override
  Widget build(BuildContext context) {
    if (!kDebugMode) return const SizedBox.shrink();
    final link = extractIndexUrl(fullMessage);

    return Container(
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: WorkaColors.orange.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: WorkaColors.orange.withValues(alpha: 0.32)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Нужен индекс Firestore',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: WorkaColors.textDark,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: link.isEmpty
                    ? null
                    : () async {
                        await Clipboard.setData(ClipboardData(text: link));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Ссылка скопирована')),
                          );
                        }
                      },
                child: const Text('Copy'),
              ),
            ],
          ),
          if (link.isNotEmpty)
            Text(
              link,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                color: WorkaColors.textGreyDark,
                fontWeight: FontWeight.w600,
              ),
            ),
          if (link.isEmpty)
            const Text(
              'Ссылка недоступна',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: WorkaColors.textGreyDark,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }
}
