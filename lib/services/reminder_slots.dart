/// Prefer the recurring row for duplicate same-medicine slots; its daily
/// notification also covers any overlapping dated occurrence.
List<T> uniqueReminderSlots<T>(
  Iterable<T> items, {
  required String Function(T) clockKey,
  required String Function(T) calendarDay,
  required bool Function(T) isRecurring,
}) {
  final rows = items.toList();
  final recurring = <String, T>{};
  for (final item in rows.where(isRecurring)) {
    recurring.putIfAbsent(clockKey(item), () => item);
  }
  final dated = <(String, String), T>{};
  for (final item in rows.where((item) => !isRecurring(item))) {
    final key = clockKey(item);
    if (recurring.containsKey(key)) continue;
    dated.putIfAbsent((key, calendarDay(item)), () => item);
  }
  return [...recurring.values, ...dated.values];
}
