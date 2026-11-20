import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:med_ai/models.dart';
import 'package:med_ai/services/api.dart';

void main() {
  test('protected 401 preserves medicines and signals session recovery', () async {
    final api = Api(client: MockClient((_) async =>
        http.Response('{"detail":"Session expired or invalid"}', 401)));
    final state = AppState(api: api);
    state.userId = 'existing-account';
    api.token = 'expired';
    state.medicines.add(Medicine(name: 'Saved medicine', quantity: 20));
    state.budget = 60000;
    await expectLater(api.request('GET', '/state'), throwsA(isA<ApiError>()));
    expect(state.needsSignIn, isTrue);
    expect(state.medicines.single.quantity, 20);
    expect(state.budget, 60000);
    api.close();
  });
  test('incorrect password does not invalidate a session', () async {
    final api = Api(client: MockClient((_) async =>
        http.Response('{"detail":"Invalid credentials"}', 401)));
    var invalidated = false;
    api.onUnauthorized = () => invalidated = true;
    await expectLater(api.request('POST', '/auth/login', {}), throwsA(isA<ApiError>()));
    expect(invalidated, isFalse);
    api.close();
  });
  test('old response cannot invalidate replacement token', () async {
    late Api api;
    api = Api(client: MockClient((_) async {
      api.token = 'replacement';
      return http.Response('{"detail":"expired"}', 401);
    }));
    api.token = 'old';
    var invalidated = false;
    api.onUnauthorized = () => invalidated = true;
    await expectLater(api.request('GET', '/state'), throwsA(isA<ApiError>()));
    expect(invalidated, isFalse);
    api.close();
  });
}
