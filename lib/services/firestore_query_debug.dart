import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

final Set<String> _loggedQuerySignatures = <String>{};

void logQuerySignature(
  String name,
  Query<Map<String, dynamic>> query, {
  required String collectionPath,
  List<String> where = const <String>[],
  List<String> orderBy = const <String>[],
  int? limit,
}) {
  if (!kDebugMode) return;
  final signature = StringBuffer()
    ..writeln('[FirestoreQuery][$name]')
    ..writeln('collection: $collectionPath')
    ..writeln('where: ${where.isEmpty ? '[]' : where.join(', ')}')
    ..writeln('orderBy: ${orderBy.isEmpty ? '[]' : orderBy.join(', ')}')
    ..writeln('limit: ${limit?.toString() ?? '-'}')
    ..writeln('queryType: ${query.runtimeType}');

  final text = signature.toString();
  if (_loggedQuerySignatures.add(text)) {
    debugPrint(text);
  }
}

