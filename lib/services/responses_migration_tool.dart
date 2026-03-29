import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class ResponsesMigrationTool {
  ResponsesMigrationTool._();

  static Future<void> migrateLegacyResponses(
    FirebaseFirestore db, {
    int batchSize = 200,
  }) async {
    // Legacy `responses` writes are intentionally disabled.
    // New interactions must use `applications` and `jobOffers` only.
    debugPrint(
      '[responses_migration] skipped: legacy responses writes are disabled; use applications/jobOffers only',
    );
    return;
  }
}
