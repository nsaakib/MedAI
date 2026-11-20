import 'package:flutter/services.dart';
import 'package:med_ai/services/vault.dart';
import 'package:med_ai/services/dose_tracking.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:med_ai/localization.dart';
import 'package:med_ai/models.dart';
import 'package:med_ai/design.dart';
import 'package:med_ai/main.dart';
import 'package:med_ai/screens/chat_doctor_list.dart';
import 'package:med_ai/screens/medicines_live.dart';
import 'package:med_ai/screens/sos_live.dart';
import 'package:med_ai/services/api.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'dart:convert';

class MemoryVault extends Vault {
  Map<String, dynamic>? saved;
  @override
  Future<void> write(String user, Map<String, dynamic> data) async {
    saved = data;
  }
}

void main() {
  tearDown(() => UiLanguage.use('en'));
  test(
    'language selection persists and participates in account sync',
    () async {
      final storage = <String, String>{};
      const channel = MethodChannel(
        'plugins.it_nomads.com/flutter_secure_storage',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            final args = Map<String, dynamic>.from(call.arguments as Map);
            if (call.method == 'write') {
              storage[args['key'] as String] = args['value'] as String;
              return null;
            }
            if (call.method == 'read') return storage[args['key']];
            return null;
          });
      final vault = MemoryVault();
      final state = AppState(vault: vault);
      state.userId = 'a' * 32;
      state.api.token = 'test';
      state.needsSignIn = true;
      await state.setLanguage('bn');
      expect(state.snapshot['language'], 'Bangla');
      expect(vault.saved?['state']['language'], 'Bangla');
      UiLanguage.use('en');
      await UiLanguage.initialize();
      expect(UiLanguage.locale.value.languageCode, 'bn');
      state.dispose();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    },
  );

  test(
    'language templates retain clinical values and nullable decoration values',
    () {
      UiLanguage.use('bn');
      expect(tr('Brand alternatives'), 'বিকল্প ব্র্যান্ড');
      expect(tr('Last checked: 12:34'), 'সর্বশেষ দেখা হয়েছে: 12:34');
      expect(
        tr('Prescribed: Exium 40 mg · Cap'),
        'প্রেসক্রিপশনে: Exium 40 mg · Cap',
      );
      expect(tr<String?>(null), isNull);
      expect(tr('Zopride 50mg'), 'Zopride 50mg');
      UiLanguage.use('en');
      expect(tr('Brand alternatives'), 'Brand alternatives');
    },
  );
  testWidgets(
    'scheduled intake is stored per dose and a previous day remains pending',
    (tester) async {
      final vault = MemoryVault();
      final s = AppState(vault: vault);
      s.userId = 'a' * 32;
      s.api.token = 'test';
      s.needsSignIn = true;
      final med = Medicine(name: 'Zopride', verified: true);
      s.medicines.add(med);
      s.reminders.addAll([
        {
          'id': 'r1',
          'medicine_id': med.id,
          'hour': 8,
          'minute': 0,
          'enabled': true,
        },
        {
          'id': 'r2',
          'medicine_id': med.id,
          'hour': 20,
          'minute': 0,
          'enabled': true,
        },
      ]);
      final day = s.notification.dayNow(s.timezone);
      s.doses.add({
        'id': 'old',
        'medicine_id': med.id,
        'logged_at': DateTime.now().toUtc().toIso8601String(),
        'scheduled_key': scheduledDoseKey(
          'r1',
          day.subtract(const Duration(days: 1)),
        ),
      });
      await tester.pumpWidget(
        MaterialApp(
          home: Scope(
            state: s,
            child: Scaffold(body: TodayDoseStatus(medicine: med)),
          ),
        ),
      );
      expect(find.text('Pending · Mark taken'), findsNWidgets(2));
      await tester.tap(find.text('Pending · Mark taken').first);
      await tester.pumpAndSettle();
      expect(find.text('Taken'), findsOneWidget);
      expect(find.text('Pending · Mark taken'), findsOneWidget);
      expect(s.doses.length, 2);
      expect(vault.saved, isNotNull);
      expect(s.doses.last['scheduled_key'], scheduledDoseKey('r1', day));
      await tester.pumpWidget(const SizedBox());
      s.dispose();
    },
  );

  testWidgets('actual doctor list renders rows without a square Tile wrapper', (
    tester,
  ) async {
    const turn = <String, dynamic>{
      'triage': {'level': 'routine'},
      'language': 'en',
      'specialty': 'Cardiology',
      'doctors': [
        {
          'doctor_id': 'test-row',
          'full_name': 'Directory test doctor',
          'specialties': 'Cardiology',
          'hospital_name': 'Test clinic',
          'division': 'Dhaka',
        },
      ],
    };
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: ChatDoctorList(turn: turn)),
      ),
    );
    expect(find.text('Directory test doctor'), findsOneWidget);
    expect(find.textContaining('Test clinic'), findsOneWidget);
    expect(find.byType(Tile), findsNothing);
    expect(find.text('Find matching doctors'), findsOneWidget);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ChatDoctorList(
      turn: {...turn, 'triage': {'level': 'clarify'}},
    ))));
    expect(find.text('Directory test doctor'), findsOneWidget);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ChatDoctorList(
      turn: {...turn, 'triage': {'level': 'emergency'}},
    ))));
    expect(find.text('Directory test doctor'), findsNothing);

  });
  testWidgets(
    'medicine actions are filled rounded controls on every medicine card',
    (tester) async {
      final s = AppState();
      s.medicines.addAll([
        Medicine(name: 'Napa', verified: true),
        Medicine(name: 'Zopride', verified: false),
      ]);
      await tester.pumpWidget(
        MaterialApp(
          home: Scope(state: s, child: const MedicineListLive()),
        ),
      );
      expect(find.text('Brand alternatives'), findsNWidgets(2));
      expect(find.text('Auto-schedule reminders'), findsNWidgets(2));
      expect(find.text('Mark taken'), findsNWidgets(2));
      // The sync-status notice is not a medicine card and keeps its styling.
      expect(
        tester
            .widgetList<Tile>(find.byType(Tile))
            .where((tile) => !tile.outlined)
            .length,
        greaterThanOrEqualTo(4),
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      s.dispose();
    },
  );
  testWidgets('Bangla locale is applied to MaterialApp and screen text', (
    tester,
  ) async {
    UiLanguage.use('bn');
    final s = AppState();
    await tester.pumpWidget(MedAiApp(state: s));
    await tester.pumpAndSettle();
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.locale, const Locale('bn'));
    expect(find.text('শুরু করুন'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    s.dispose();
  });
  testWidgets(
    'refresh shows completion and replaces disabled config with latest status',
    (tester) async {
      var configCalls = 0;
      final api = Api(
        client: MockClient((request) async {
          if (request.url.path.endsWith('/sos/config')) {
            configCalls++;
            return http.Response(
              jsonEncode({
                'enabled': configCalls > 1,
                'mode': configCalls > 1 ? 'live' : 'disabled',
                'map': {},
              }),
              200,
            );
          }
          if (request.url.path.endsWith('/sos/requests'))
            return http.Response('[]', 200);
          return http.Response('{}', 200);
        }),
      );
      final s = AppState(api: api);
      s.userId = 'test';
      api.token = 'test-token';
      await tester.pumpWidget(
        MaterialApp(
          home: Scope(state: s, child: const EmergencySosLive()),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Live partner dispatch has not been enabled'),
        findsOneWidget,
      );
      await tester.ensureVisible(find.text('Refresh status'));
      await tester.tap(find.text('Refresh status'));
      await tester.pumpAndSettle();
      expect(configCalls, 2);
      expect(
        find.textContaining('Live partner dispatch has not been enabled'),
        findsNothing,
      );
      expect(find.textContaining('Last checked:'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      s.dispose();
    },
  );
}
