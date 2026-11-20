import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as data;
import 'package:timezone/timezone.dart' as tz;

import 'reminder_slots.dart';

typedef _Dose = ({
  Map<String, dynamic> row,
  tz.TZDateTime time,
  bool recurring,
});

class ReminderService {
  final plugin = FlutterLocalNotificationsPlugin();
  bool initialized = false;
  bool exactAlarmActive = false;
  bool _permissionBusy = false;
  static const _bridgeTimeout = Duration(seconds: 4);

  AndroidFlutterLocalNotificationsPlugin? get _android => plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  Future<bool> hasDeviceAlarmPermission() async =>
      await _android?.canScheduleExactNotifications().timeout(_bridgeTimeout) ==
      true;

  Future<bool> enableDeviceAlarms() async {
    if (_permissionBusy) return false;
    _permissionBusy = true;
    try {
      await init();
      final android = _android;
      if (android == null) return false;
      if (await hasDeviceAlarmPermission()) return true;
      return await android.requestExactAlarmsPermission().timeout(
            const Duration(seconds: 25),
          ) ==
          true;
    } finally {
      _permissionBusy = false;
    }
  }

  static bool zonesReady = false;
  static void ensureZones() {
    if (!zonesReady) {
      data.initializeTimeZones();
      zonesReady = true;
    }
  }

  Future<void> _pendingSchedules = Future.value();
  Future<void> init() async {
    if (initialized) return;
    ensureZones();
    await plugin
        .initialize(
          const InitializationSettings(
            android: AndroidInitializationSettings('ic_stat_medai'),
            iOS: DarwinInitializationSettings(
              requestAlertPermission: false,
              requestBadgePermission: false,
              requestSoundPermission: false,
            ),
          ),
        )
        .timeout(_bridgeTimeout);
    initialized = true;
  }

  Future<bool> schedule(
    List<Map<String, dynamic>> reminders,
    String zone, {
    bool exact = false,
    bool prompt = true,
    Map<String, String> medicineLabels = const {},
  }) async {
    final snapshot = reminders
        .map((r) => Map<String, dynamic>.from(r))
        .toList();
    final future = _pendingSchedules.then(
      (_) => _schedule(
        snapshot,
        zone,
        exact: exact,
        prompt: prompt,
        medicineLabels: medicineLabels,
      ),
    );
    _pendingSchedules = future.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return await future;
  }

  Future<bool> _schedule(
    List<Map<String, dynamic>> reminders,
    String zone, {
    required bool exact,
    required bool prompt,
    required Map<String, String> medicineLabels,
  }) async {
    await init();
    final android = _android;
    var androidAllowed = await android?.areNotificationsEnabled().timeout(
      _bridgeTimeout,
    );
    if (androidAllowed == false && prompt) {
      androidAllowed = await android?.requestNotificationsPermission().timeout(
        const Duration(seconds: 25),
      );
    }
    final ios = plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    final iosAllowed = !prompt
        ? null
        : await ios
              ?.requestPermissions(alert: true, badge: true, sound: true)
              .timeout(const Duration(seconds: 25));
    if (androidAllowed == false || iosAllowed == false) return false;
    exactAlarmActive = android != null && await hasDeviceAlarmPermission();

    final location = tz.getLocation(zone);
    final now = tz.TZDateTime.now(location);
    final today = DateTime.utc(now.year, now.month, now.day);
    final items = <_Dose>[];
    for (final r in reminders) {
      final hour = r['hour'], minute = r['minute'];
      if (r['enabled'] != true ||
          r['id'] is! String ||
          r['medicine_id'] is! String ||
          hour is! int ||
          hour < 0 ||
          hour > 23 ||
          minute is! int ||
          minute < 0 ||
          minute > 59)
        continue;
      final start = DateTime.tryParse(r['start_date'] as String? ?? '');
      final end = DateTime.tryParse(r['end_date'] as String? ?? '');
      tz.TZDateTime at(int d) => tz.TZDateTime(
        location,
        now.year,
        now.month,
        now.day + d,
        hour,
        minute,
      );
      if (end == null && (start == null || !today.isBefore(start))) {
        items.add((
          row: r,
          time: at(0).isAfter(now) ? at(0) : at(1),
          recurring: true,
        ));
        continue;
      }
      // Dated courses use separate occurrences and never turn into endless repeats.
      for (var d = 0; d < 120; d++) {
        final slot = at(d);
        final day = DateTime.utc(slot.year, slot.month, slot.day);
        if (end != null && day.isAfter(end)) break;
        if ((start == null || !day.isBefore(start)) && slot.isAfter(now)) {
          items.add((row: r, time: slot, recurring: false));
        }
      }
    }
    String dayKey(tz.TZDateTime t) => '${t.year}-${t.month}-${t.day}';
    final deduped = uniqueReminderSlots<_Dose>(
      items,
      clockKey: (d) =>
          '${d.row['medicine_id']}:${d.time.hour}:${d.time.minute}',
      calendarDay: (d) => dayKey(d.time),
      isRecurring: (d) => d.recurring,
    )..sort((a, b) => a.time.compareTo(b.time));
    final cap = defaultTargetPlatform == TargetPlatform.iOS ? 60 : 400;
    final desired = <int, _Dose>{};
    for (final d in deduped.take(cap)) {
      final label = medicineLabels[d.row['medicine_id']] ?? '';
      final occurrence = d.recurring ? 'daily' : dayKey(d.time);
      final key =
          'medai-dose-v3:${d.row['id']}:$zone:${d.time.hour}:${d.time.minute}:$occurrence:$exactAlarmActive:$label';
      desired[notificationId(key)] = d;
    }

    final timer = Stopwatch()..start();
    void checkBudget() {
      if (timer.elapsed >= const Duration(seconds: 17)) {
        throw StateError(
          'Reminder update took too long. Tap Save and Schedule to continue.',
        );
      }
    }

    String payload(_Dose d) => d.row['id'] as String;
    final pending = await plugin.pendingNotificationRequests().timeout(
      _bridgeTimeout,
    );
    final current = <int>{};
    for (final old in pending) {
      // Do not cancel refill alerts or notifications from other features.
      if (old.title != 'Medication reminder' || old.payload == null) continue;
      final replacement = desired[old.id];
      if (replacement != null && old.payload == payload(replacement)) {
        current.add(old.id);
      } else {
        checkBudget();
        await plugin.cancel(old.id).timeout(_bridgeTimeout);
      }
    }
    for (final entry in desired.entries.where(
      (entry) => !current.contains(entry.key),
    )) {
      checkBudget();
      final d = entry.value;
      await _scheduleDose(
        entry.key,
        d.row,
        d.time,
        exactAlarmActive,
        medicineLabels,
        daily: d.recurring,
      ).timeout(_bridgeTimeout);
    }
    return true;
  }

  Future<DateTime> localDay(String zone) async {
    return dayNow(zone);
  }

  DateTime dayNow(String zone) {
    ensureZones();
    final now = tz.TZDateTime.now(tz.getLocation(zone));
    return DateTime.utc(now.year, now.month, now.day);
  }

  Future<void> _scheduleDose(
    int id,
    Map<String, dynamic> r,
    tz.TZDateTime time,
    bool exact,
    Map<String, String> labels, {
    required bool daily,
  }) async {
    await plugin.zonedSchedule(
      id,
      'Medication reminder',
      labels[r['medicine_id']] == null
          ? 'Open Med.ai to review your prescribed schedule.'
          : "${labels[r['medicine_id']]} · Check your prescribed dose in Med.ai.",
      time,
      _alarmDetails(),
      androidScheduleMode: exact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: daily ? DateTimeComponents.time : null,
      payload: r['id'] as String,
    );
  }

  NotificationDetails _alarmDetails({bool test = false}) => NotificationDetails(
    android: AndroidNotificationDetails(
      'medai_medicine_audible_v3',
      'Medicine alarms',
      channelDescription: 'Audible alarms for scheduled medicine reminders',
      category: AndroidNotificationCategory.alarm,
      audioAttributesUsage: AudioAttributesUsage.alarm,
      sound: const UriAndroidNotificationSound('content://settings/system/alarm_alert'),
      playSound: true,
      importance: Importance.high,
      priority: Priority.high,
      visibility: NotificationVisibility.private,
      autoCancel: true,
      // Notification.FLAG_INSISTENT: repeat the tone, not the notification.
      additionalFlags: test ? null : Int32List.fromList([4]),
      timeoutAfter: test ? 10000 : null,
    ),
    iOS: const DarwinNotificationDetails(presentSound: true),
  );

  Future<bool> testAlarm() async {
    await init();
    final android = _android;
    if (await android?.areNotificationsEnabled().timeout(_bridgeTimeout) == false) {
      if (await android?.requestNotificationsPermission().timeout(const Duration(seconds: 25)) != true) {
        return false;
      }
    }
    final id = notificationId('medai-alarm-audio-test');
    await plugin.cancel(id).timeout(_bridgeTimeout);
    await plugin.show(id, 'Test medicine alarm', 'Dismiss this test alert when finished.',
        _alarmDetails(test: true)).timeout(_bridgeTimeout);
    return true;
  }

  Future<bool> refillAlert(String id) async {
    await init();
    final android = plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final ios = plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (await android?.requestNotificationsPermission() == false) return false;
    if (await ios?.requestPermissions(alert: true, badge: true, sound: true) ==
        false)
      return false;
    await plugin.show(
      notificationId('refill:$id'),
      'Medicine supply is low',
      'Open Med.ai to check your remaining supply and review what you need to buy.',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'medai_refills',
          'Refill reminders',
          importance: Importance.defaultImportance,
          visibility: NotificationVisibility.private,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
    return true;
  }

  static int notificationId(String id) {
    var hash = 0x811c9dc5;
    for (final code in id.codeUnits) {
      hash = ((hash ^ code) * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }

  Future<void> cancelReminder(String id) async {
    await init();
    await plugin.cancel(notificationId(id)).timeout(_bridgeTimeout);
    for (final entry in await plugin.pendingNotificationRequests().timeout(
      _bridgeTimeout,
    )) {
      if (entry.payload == id)
        await plugin.cancel(entry.id).timeout(_bridgeTimeout);
    }
  }

  Future<void> cancel() async {
    await init();
    await plugin.cancelAll();
  }
}
