import 'medicine_schedule.dart';

String scheduledDoseKey(String reminderId, DateTime day) =>
    '$reminderId:${dateKey(day)}';

bool activeScheduledDose(Map<String, dynamic> row, DateTime day) {
  if (row['enabled'] != true) return false;
  final key = dateKey(day);
  final start = row['start_date'] as String?;
  final end = row['end_date'] as String?;
  return (start == null || key.compareTo(start) >= 0) &&
      (end == null || key.compareTo(end) <= 0);
}
