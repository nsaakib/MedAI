import '../localization.dart';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../design.dart';
import '../models.dart';
import '../services/medicine_schedule.dart';
import '../services/dose_tracking.dart';

Future<bool> setupMeals(BuildContext context, AppState s) async {
  final initial = s.mealsConfigured ? s.mealMinutes : <int>[570, 870, 1290];
  final selected = [...initial];
  var before = s.beforeMealMinutes?.toString() ?? '';
  var after = s.afterMealMinutes?.toString() ?? '';
  String? error;
  final result = await showDialog<bool>(
    context: context,
    builder: (dialog) => StatefulBuilder(
      builder: (c, refresh) => AlertDialog(
        title: Text(tr('Set up your meal times')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                tr(
                  'Set the usual time you eat each meal. Before/after offsets are optional; enter them only if confirmed by your clinician or pharmacist. These settings update eligible medicines together. Prescribed times and intervals take priority.',
                ),
              ),
              for (var i = 0; i < 3; i++)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(tr(['Breakfast', 'Lunch', 'Dinner'][i])),
                  trailing: Text(
                    tr(
                      TimeOfDay(
                        hour: selected[i] ~/ 60,
                        minute: selected[i] % 60,
                      ).format(c),
                    ),
                  ),
                  onTap: () async {
                    final time = await showTimePicker(
                      context: c,
                      initialTime: TimeOfDay(
                        hour: selected[i] ~/ 60,
                        minute: selected[i] % 60,
                      ),
                    );
                    if (c.mounted && time != null)
                      refresh(() => selected[i] = time.hour * 60 + time.minute);
                  },
                ),
              TextFormField(
                initialValue: before,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: tr('Confirmed minutes before meals'),
                ),
                onChanged: (v) => before = v.trim(),
              ),
              TextFormField(
                initialValue: after,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: tr('Confirmed minutes after meals'),
                ),
                onChanged: (v) => after = v.trim(),
              ),
              if (error != null)
                Text(tr(error!), style: const TextStyle(color: Colors.red)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: Text(tr('Not now')),
          ),
          TextButton(
            onPressed: () {
              bool valid(String v) =>
                  v.isEmpty ||
                  ((int.tryParse(v) ?? 0) >= 1 &&
                      (int.tryParse(v) ?? 0) <= 180);
              if (selected[0] >= selected[1] ||
                  selected[1] >= selected[2] ||
                  !valid(before) ||
                  !valid(after)) {
                refresh(
                  () => error =
                      'Choose the meals in order and use offsets from 1 to 180 minutes.',
                );
              } else {
                Navigator.pop(dialog, true);
              }
            },
            child: Text(tr('Save meal times')),
          ),
        ],
      ),
    ),
  );
  if (result != true || !context.mounted) return false;
  final oldMeals = [...s.mealMinutes];
  final oldBefore = s.beforeMealMinutes;
  final oldAfter = s.afterMealMinutes;
  final oldReminders = s.reminders.map((r) => {...r}).toList();
  s.mealMinutes = selected;
  s.beforeMealMinutes = int.tryParse(before);
  s.afterMealMinutes = int.tryParse(after);
  var changed = 0;
  var needsReview = 0;
  for (final m in s.medicines.where((m) => m.verified)) {
    if (isPrn('${m.frequency} ${m.meal} ${m.instruction}')) continue;
    final next = sharedMealTimes(s, m);
    final previous = mealSlotTimes(
      m.frequency,
      m.meal,
      oldMeals,
      before: oldBefore,
      after: oldAfter,
    );
    for (final row in s.reminders.where(
      (r) =>
          r['medicine_id'] == m.id &&
          r['enabled'] == true &&
          r['automatic'] == true,
    )) {
      final minute = (row['hour'] as int) * 60 + (row['minute'] as int);
      final inferred = previous?.entries
          .where((e) => e.value == minute)
          .firstOrNull
          ?.key;
      final slot = row['meal_slot'] as int? ?? inferred;
      if (slot == null) continue;
      final newMinute = next?[slot];
      if (newMinute == null) {
        if (activeScheduledDose(row, s.notification.dayNow(s.timezone)))
          needsReview++;
        continue;
      }
      if (newMinute == minute) continue;
      row['meal_slot'] = slot;
      row['hour'] = newMinute ~/ 60;
      row['minute'] = newMinute % 60;
      changed++;
    }
    changed += addSharedMealReminders(s, m);
  }
  try {
    await s.commit();
  } catch (e) {
    s.mealMinutes = oldMeals;
    s.beforeMealMinutes = oldBefore;
    s.afterMealMinutes = oldAfter;
    s.reminders
      ..clear()
      ..addAll(oldReminders);
    if (context.mounted)
      message(context, tr('Could not save meal times'), tr('$e'));
    return false;
  }
  var allowed = true;
  var scheduleFailed = false;
  if (changed > 0) {
    try {
      allowed = await s.applyReminders(prompt: false);
    } catch (_) {
      scheduleFailed = true;
    }
  }
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          tr(
            scheduleFailed
                ? 'Meal times saved. Open Medicine Reminders and tap Save and Schedule to retry the phone update.'
                : !allowed
                ? 'Meal times saved. Allow notifications and tap Save and Schedule in Medicine Reminders.'
                : 'Meal times saved. $changed reminder times updated or added.'
                      '${changed > 0 ? ' ${reminderDelivery(s)}' : ''}'
                      '${needsReview > 0 ? ' $needsReview kept their previous times and need review.' : ''}',
          ),
        ),
      ),
    );
  }
  return true;
}

Map<int, int>? sharedMealTimes(AppState s, Medicine m) => mealSlotTimes(
  m.frequency,
  m.meal,
  s.mealMinutes,
  before: s.beforeMealMinutes,
  after: s.afterMealMinutes,
);

int addSharedMealReminders(AppState s, Medicine m) {
  if (!m.verified ||
      m.meal.trim().isEmpty ||
      m.instruction.trim().isNotEmpty ||
      s.reminders.any((r) => r['medicine_id'] == m.id))
    return 0;
  final times = sharedMealTimes(s, m);
  final start = DateTime.tryParse(m.courseStart ?? '');
  final days = start == null ? null : courseDays(m.duration, start);
  if (times == null ||
      start == null ||
      days == null ||
      s.reminders.length + times.length > 400)
    return 0;
  final end = DateTime.utc(start.year, start.month, start.day + days - 1);
  if (end.isBefore(s.notification.dayNow(s.timezone))) return 0;
  s.reminders.addAll([
    for (final e in times.entries)
      <String, dynamic>{
        'id': identifier(),
        'medicine_id': m.id,
        'hour': e.value ~/ 60,
        'minute': e.value % 60,
        'enabled': true,
        'automatic': true,
        'meal_slot': e.key,
        'start_date': dateKey(start),
        'end_date': dateKey(end),
      },
  ]);
  return times.length;
}

String reminderDelivery(AppState s) {
  if (defaultTargetPlatform != TargetPlatform.android) {
    return 'Notifications are scheduled on this device.';
  }
  return s.notification.exactAlarmActive
      ? 'Medicine notifications are scheduled at their reminder times.'
      : 'Notifications are scheduled. Enable Alarms & reminders for exact alarm times.';
}

Future<void> enableMedicineAlerts(BuildContext c, AppState s) async {
  if (defaultTargetPlatform != TargetPlatform.android) return;
  try {
    final allowed = await s.notification.enableDeviceAlarms();
    if (!c.mounted) return;
    ScaffoldMessenger.of(c).showSnackBar(
      SnackBar(
        content: Text(
          tr(
            allowed
                ? 'Phone alarm permission is on. Tap Save and Schedule to apply your reminder changes.'
                : 'If needed, allow Alarms & reminders in Android settings. This button only manages access.',
          ),
        ),
      ),
    );
  } catch (_) {
    if (c.mounted)
      message(
        c,
        tr('Check phone alarm access'),
        tr(
          'Open Android Settings → Apps → Special access → Alarms & reminders. Then return and tap Save and Schedule.',
        ),
      );
  }
}

Future<int?> askUnits(
  BuildContext c,
  String title,
  String label, {
  int? initial,
  int min = 1,
}) async {
  var value = initial?.toString() ?? '';
  String? error;
  return showDialog<int>(
    context: c,
    builder: (dialog) => StatefulBuilder(
      builder: (context, refresh) => AlertDialog(
        title: Text(tr(title)),
        content: TextFormField(
          initialValue: value,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: tr(label),
            errorText: tr(error),
          ),
          onChanged: (v) => value = v.trim(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: Text(tr('Cancel')),
          ),
          TextButton(
            onPressed: () {
              final parsed = int.tryParse(value);
              if (parsed == null || parsed < min || parsed > 100000) {
                refresh(
                  () => error = 'Enter a whole number from $min to 100000.',
                );
              } else {
                Navigator.pop(dialog, parsed);
              }
            },
            child: Text(tr('Confirm')),
          ),
        ],
      ),
    ),
  );
}

Future<void> automaticSchedule(BuildContext c, AppState s, Medicine m) async {
  if (!m.verified || isPrn('${m.frequency} ${m.instruction} ${m.meal}')) {
    message(
      c,
      tr('Check the prescription'),
      tr(
        'Review the instructions first. As-needed medicines are not put on a fixed schedule.',
      ),
    );
    return;
  }
  if (m.instruction.isNotEmpty) {
    final acknowledged = await showDialog<bool>(
      context: c,
      builder: (d) => AlertDialog(
        title: Text(tr('Check special instructions')),
        content: Text(
          tr(
            '${m.instruction}\n\nContinue only if automatic clock times will not conflict with these directions.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: Text(tr('Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(d, true),
            child: Text(tr('Continue')),
          ),
        ],
      ),
    );
    if (acknowledged != true || !c.mounted) return;
  }
  final (_, prescribedTiming) = explicitDose(m.frequency);
  final count = doseCount(prescribedTiming);
  if (count == null) {
    message(
      c,
      tr('Confirm the timing'),
      tr(
        'Med.ai could not read an exact fixed frequency. Check the prescription, or open Reminders to choose the prescribed times yourself.',
      ),
    );
    return;
  }
  final interval = intervalHours(prescribedTiming);
  final usesAnchor =
      interval != null ||
      count == 4 ||
      (count == 1 && slotDoses(prescribedTiming) == null);
  if (!usesAnchor && !s.mealsConfigured && !await setupMeals(c, s)) return;
  if (!c.mounted) return;
  int? anchor;
  if (usesAnchor) {
    final time = await showTimePicker(
      context: c,
      initialTime: const TimeOfDay(hour: 8, minute: 0),
      helpText: interval != null
          ? 'Choose the prescribed first dose time'
          : 'Choose the confirmed first dose time',
    );
    if (time == null || !c.mounted) return;
    anchor = time.hour * 60 + time.minute;
  }
  final times = proposedTimes(
    m.frequency,
    m.meal,
    s.mealMinutes,
    before: s.beforeMealMinutes,
    after: s.afterMealMinutes,
    first: anchor,
    evenly: count == 4 && interval == null,
  );
  if (times == null || times.toSet().length != count) {
    message(
      c,
      tr('Timing needs confirmation'),
      tr(
        'Meal and interval instructions could not be combined safely. Set a confirmed meal offset or enter the prescribed times in Reminders.',
      ),
    );
    return;
  }
  final today = await s.notification.localDay(s.timezone);
  if (!c.mounted) return;
  final start = DateTime.tryParse(m.courseStart ?? '') ?? today;
  final days = courseDays(m.duration, start);
  if (days == null) {
    message(
      c,
      tr('Enter the prescribed duration'),
      tr(
        'Set an explicit duration in days, weeks or months before enabling automatic alarms.',
      ),
    );
    return;
  }
  final end = DateTime.utc(start.year, start.month, start.day + days - 1);
  if (end.isBefore(today)) {
    message(
      c,
      tr('Course has ended'),
      tr('Check the saved start date and duration with your prescription.'),
    );
    return;
  }
  final lastDay = (anchor != null && times.any((t) => t < anchor!))
      ? DateTime.utc(end.year, end.month, end.day + 1)
      : end;
  final formatted = times
      .map((x) => TimeOfDay(hour: x ~/ 60, minute: x % 60).format(c))
      .join(' · ');
  final ok = await showDialog<bool>(
    context: c,
    builder: (d) => AlertDialog(
      title: Text(tr('Confirm reminder times')),
      content: Text(
        tr(
          '${m.name}\n$formatted\nThrough ${dateKey(lastDay)}\n\n'
          '${count == 4 && interval == null ? 'These are proposed around-the-clock times. Use them only if the prescriber confirmed that spacing.\n\n' : ''}'
          'The prescription stays unchanged. Confirm these times follow it.',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(d, false),
          child: Text(tr('Cancel')),
        ),
        TextButton(
          onPressed: () => Navigator.pop(d, true),
          child: Text(tr('Schedule')),
        ),
      ],
    ),
  );
  if (ok != true || !c.mounted) return;
  final previous = s.reminders.where((r) => r['medicine_id'] == m.id).toList();
  String dayForTime(DateTime day, int minute) => dateKey(
    DateTime.utc(
      day.year,
      day.month,
      day.day + (anchor != null && minute < anchor! ? 1 : 0),
    ),
  );
  final mealSlots = sharedMealTimes(s, m);
  final rows = [
    for (final t in times)
      <String, dynamic>{
        'id': identifier(),
        'medicine_id': m.id,
        'hour': t ~/ 60,
        'minute': t % 60,
        'enabled': true,
        'automatic': true,
        if (mealSlots?.entries.where((e) => e.value == t).firstOrNull?.key
            case final slot?)
          'meal_slot': slot,
        'start_date': dayForTime(start, t),
        'end_date': dayForTime(end, t),
      },
  ];
  if (s.reminders.length - previous.length + rows.length > 400) {
    message(
      c,
      tr('Too many reminder times'),
      tr('Remove unused reminders and try again.'),
    );
    return;
  }
  s.reminders.removeWhere((r) => r['medicine_id'] == m.id);
  s.reminders.addAll(rows);
  try {
    final allowed = await s.applyReminders();
    if (!allowed)
      throw StateError(
        'Enable medication notifications in your device settings.',
      );
    m.courseStart ??= dateKey(start);
    await s.commit();
    if (c.mounted)
      message(
        c,
        tr('Reminders scheduled'),
        tr(
          '${reminderDelivery(s)} Open Med.ai regularly to refresh long courses.',
        ),
      );
  } catch (e) {
    s.reminders.removeWhere((r) => r['medicine_id'] == m.id);
    s.reminders.addAll(previous);
    try {
      await s.applyReminders(prompt: false);
    } catch (_) {}
    if (c.mounted) message(c, tr('Could not schedule'), tr('$e'));
  }
}
