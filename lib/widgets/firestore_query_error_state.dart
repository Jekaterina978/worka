import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/worka_colors.dart';
import 'firestore_index_debug_banner.dart';

class FirestoreQueryErrorState extends StatelessWidget {
  const FirestoreQueryErrorState({
    super.key,
    required this.message,
    required this.isIndexError,
    required this.onRetry,
    this.padding = const EdgeInsets.all(16),
  });

  final String message;
  final bool isIndexError;
  final VoidCallback onRetry;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final showDebugBanner = kDebugMode && isIndexError;
    final text = kDebugMode
        ? (isIndexError
              ? 'Ошибка загрузки. Проверьте индексы Firestore.'
              : 'Ошибка загрузки: $message')
        : 'Ошибка загрузки. Попробуйте позже.';
    return Center(
      child: Padding(
        padding: padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showDebugBanner) ...[
              FirestoreIndexDebugBanner(fullMessage: message),
              const SizedBox(height: 10),
            ],
            Text(
              text,
              maxLines: kDebugMode && !isIndexError ? 3 : 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: WorkaColors.textGreyDark,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: onRetry,
              child: const Text('Повторить'),
            ),
          ],
        ),
      ),
    );
  }
}
