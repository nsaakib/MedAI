import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:med_ai/models.dart';
import 'package:med_ai/screens/medicines_live.dart';
import 'package:med_ai/services/vault.dart';

class SaveVault extends Vault {
  Map<String, dynamic>? saved;
  @override
  Future<void> write(String user, Map<String, dynamic> value) async {
    saved = jsonDecode(jsonEncode(value));
  }
}

class SaveState extends AppState {
  SaveState(this.memory) : super(vault: memory) {
    userId = 'a' * 32;
  }
  final SaveVault memory;
  bool fail = false;
  int alarmCalls = 0;
  Completer<bool>? pendingAlarm;
  @override
  Future<bool> applyReminders({bool? exact, bool prompt = true}) {
    alarmCalls++;
    return pendingAlarm?.future ?? Future.value(false);
  }

  @override
  Future<void> commit() async {
    if (fail) throw StateError('Synthetic disk failure');
    await persist();
    emit();
  }
}

void main() {
  Future<void> open(WidgetTester tester, SaveState state) async {
    await tester.pumpWidget(
      Scope(
        state: state,
        child: MaterialApp(
          home: Builder(
            builder: (c) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.push(
                  c,
                  MaterialPageRoute<void>(
                    builder: (_) => const MedicineLive(
                      initial: {
                        'name': 'OCR original',
                        'strength': '20 mg',
                        'form': 'tablet',
                        'source_document_id': 'source-image',
                      },
                    ),
                  ),
                ),
                child: const Text('Review OCR'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Review OCR'));
    await tester.pumpAndSettle();
  }

  Future<void> edit(WidgetTester tester, String label, String value) async {
    final field = find.widgetWithText(TextFormField, label);
    await tester.ensureVisible(field);
    await tester.enterText(field, value);
    await tester.pump();
  }

  Future<void> save(WidgetTester tester) async {
    final button = find.text('Save Medication');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  testWidgets(
    'edited OCR values persist locally without a backend or alarm plugin',
    (tester) async {
      final state = SaveState(SaveVault());
      await open(tester, state);
      await edit(tester, 'Medicine name', 'Corrected medicine');
      await edit(tester, 'Strength', '40 mg');
      await edit(tester, 'Meal timing', 'after meal');
      await edit(tester, 'Route', 'oral');
      await edit(tester, 'Quantity for this prescription or refill', '১২');
      await save(tester);
      expect(state.medicines.single.name, 'Corrected medicine');
      expect(state.medicines.single.strength, '40 mg');
      expect(state.medicines.single.meal, 'after meal');
      expect(state.medicines.single.route, 'oral');
      expect(state.medicines.single.quantity, 12);
      expect(state.medicines.single.sourceDocumentId, 'source-image');
      final stored = (state.memory.saved!['state']['medicines'] as List).single;
      expect(stored['name'], 'Corrected medicine');
      expect(find.byType(MedicineLive), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
  );
  testWidgets(
    'validation is visible and fixing it allows the same Save action',
    (tester) async {
      final state = SaveState(SaveVault());
      await open(tester, state);
      await save(tester);
      expect(state.medicines, isEmpty);
      expect(find.text('Enter a quantity from 1 to 100000'), findsWidgets);
      await edit(tester, 'Quantity for this prescription or refill', '5');
      await save(tester);
      expect(state.medicines.single.quantity, 5);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      state.dispose();
    },
  );
  testWidgets('failed storage rolls back and Save remains retryable', (
    tester,
  ) async {
    final state = SaveState(SaveVault())..fail = true;
    await open(tester, state);
    await edit(tester, 'Quantity for this prescription or refill', '5');
    await save(tester);
    expect(state.medicines, isEmpty);
    expect(find.textContaining('Synthetic disk failure'), findsWidgets);
    state.fail = false;
    await save(tester);
    expect(state.medicines.length, 1);
    expect(state.memory.saved, isNotNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  });
  testWidgets('pending phone scheduling does not hold the medicine Save open', (
    tester,
  ) async {
    final state = SaveState(SaveVault())
      ..pendingAlarm = Completer<bool>()
      ..mealMinutes = [480, 840, 1320]
      ..afterMealMinutes = 15;
    await open(tester, state);
    await edit(tester, 'Frequency as prescribed', '1+0+1');
    await edit(tester, 'Meal timing', 'after meal');
    await edit(tester, 'Duration', '3 days');
    await edit(tester, 'Quantity for this prescription or refill', '6');
    final reviewed = find.text(
      'I checked these fields against the prescription.',
    );
    await tester.ensureVisible(reviewed);
    await tester.tap(reviewed);
    await tester.pump();
    await save(tester);
    expect(state.memory.saved, isNotNull);
    expect(state.medicines.single.verified, true);
    expect(find.byType(MedicineLive), findsNothing);
    expect(state.alarmCalls, 1);
    state.pendingAlarm!.complete(false);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    state.dispose();
  });
}
