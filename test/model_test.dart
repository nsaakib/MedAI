import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:med_ai/models.dart';
import 'package:med_ai/services/api.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('new account model has no fictional patient data', () {
    final s = AppState();
    expect(s.medicines, isEmpty);
    expect(s.vitals, isEmpty);
    expect(s.name, isEmpty);
    expect(s.documents, isEmpty);
    s.dispose();
  });
  test('prices use integer minor currency units', () {
    expect(minorAmount('12.35'), 1235);
    expect(minorAmount('0'), 0);
    expect(minorAmount('-5'), isNull);
    expect(minorAmount('1.999'), isNull);
    expect(money(1235), '৳12.35');
  });
  test('medicine round trip retains source and review state', () {
    final m = Medicine(
      name: 'Entered item',
      quantity: 30,
      unitPrice: 125,
      verified: true,
      sourceDocumentId: 'document-1',
    );
    final copy = Medicine.fromJson(m.toJson());
    expect(copy.total, 3750);
    expect(copy.verified, isTrue);
    expect(copy.sourceDocumentId, 'document-1');
  });
  test('budget includes selected whole quantities and one delivery fee', () {
    final s = AppState();
    s.medicines.addAll([
      Medicine(id: 'a', name: 'A', quantity: 30, unitPrice: 1000),
      Medicine(id: 'b', name: 'B', quantity: 20, unitPrice: 1500),
      Medicine(id: 'c', name: 'C', quantity: 10, unitPrice: 2000),
    ]);
    s.budget = 65000;
    s.delivery = 5000;
    s.selectedIds.addAll(['a', 'b']);
    expect(s.subtotal, 80000);
    expect(s.selectedTotal, 65000);
    expect(s.remaining, 0);
    s.selectedIds.clear();
    expect(s.selectedTotal, 0);
    s.dispose();
  });
  test('API sends bearer token and preserves conflict errors', () async {
    final api = Api(
      client: MockClient((request) async {
        expect(request.headers['Authorization'], 'Bearer session-token');
        return http.Response(
          jsonEncode({
            'detail': {'message': 'stale'},
          }),
          409,
        );
      }),
    );
    api.token = 'session-token';
    await expectLater(
      api.request('GET', '/state'),
      throwsA(isA<ApiError>().having((e) => e.status, 'status', 409)),
    );
    api.close();
  });
}
