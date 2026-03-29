import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:worka/widgets/firestore_index_debug_banner.dart';
import 'package:worka/widgets/firestore_query_error_state.dart';

void main() {
  testWidgets('FirestoreIndexDebugBanner keeps compact one-line url', (
    tester,
  ) async {
    const message =
        'FirebaseException: failed-precondition https://console.firebase.google.com/project/worka-416c0/firestore/indexes?create_composite=Ck9wcm9qZWN0cy93b3JrYS00MTZjMC9kYXRhYmFzZXMvKGRlZmF1bHQpL2NvbGxlY3Rpb25Hcm91cHMvcmVzcG9uc2VzL2luZGV4ZXMvXxABGg0KCHR5cGUSAVoQARoTCg9jYW5kaWRhdGVPd25lcklkEAEaDQoJY3JlYXRlZEF0EAIaDAoIX19uYW1lX18QAg';
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: EdgeInsets.all(12),
            child: FirestoreIndexDebugBanner(fullMessage: message),
          ),
        ),
      ),
    );

    expect(find.text('Нужен индекс Firestore'), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);

    final linkText = tester.widget<Text>(
      find.byWidgetPredicate(
        (w) =>
            w is Text &&
            (w.data ?? '').startsWith('https://console.firebase.google.com/'),
      ),
    );
    expect(linkText.maxLines, 1);
    expect(linkText.overflow, TextOverflow.ellipsis);
  });

  testWidgets('FirestoreQueryErrorState hides raw index text', (tester) async {
    const message =
        'FirebaseException: [cloud_firestore/failed-precondition] The query requires an index';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FirestoreQueryErrorState(
            message: message,
            isIndexError: true,
            onRetry: () {},
          ),
        ),
      ),
    );

    expect(find.text('Нужен индекс Firestore'), findsOneWidget);
    expect(
      find.text('Ошибка загрузки. Проверьте индексы Firestore.'),
      findsOneWidget,
    );
    expect(find.textContaining('requires an index'), findsNothing);
  });
}
