// Pure calculations: an unknown or as-needed direction never creates alarms.
String rxText(String value) {
  const bengali = '০১২৩৪৫৬৭৮৯';
  for (var i = 0; i < 10; i++) {
    value = value.replaceAll(bengali[i], '$i');
  }
  return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
}

bool isPrn(String instructions) => RegExp(
  r'\b(?:prn|sos|as needed|when needed|if needed)\b|প্রয়োজনে|প্রয়োজনে|দরকার হলে',
).hasMatch(rxText(instructions));

List<int>? slotDoses(String frequency) {
  final text = rxText(frequency);
  if (!RegExp(r'^\d{1,2}(?:\s*[+–-]\s*\d{1,2}){2,3}$').hasMatch(text))
    return null;
  final doses = text.split(RegExp(r'\s*[+–-]\s*')).map(int.parse).toList();
  return doses.any((n) => n > 0) ? doses : null;
}

int? intervalHours(String frequency) {
  final match = RegExp(
    r'^(?:every\s*(\d{1,2})\s*(?:hours?|hrs?|h)|q\s*(\d{1,2})h)$',
  ).firstMatch(rxText(frequency));
  final n = match == null ? 0 : int.parse((match[1] ?? match[2])!);
  return n >= 4 && n <= 24 && 24 % n == 0 ? n : null;
}

int? doseCount(String frequency) {
  final slots = slotDoses(frequency);
  if (slots != null) return slots.where((x) => x > 0).length;
  final interval = intervalHours(frequency);
  if (interval != null) return 24 ~/ interval;
  final f = rxText(frequency);
  if (RegExp(r'^(?:once daily|one time a day|1 time a day|od|qd)$').hasMatch(f))
    return 1;
  if (RegExp(
    r'^(?:twice daily|two times (?:daily|a day)|2 times (?:daily|a day)|bid|bd)$',
  ).hasMatch(f))
    return 2;
  if (RegExp(
    r'^(?:three times (?:daily|a day)|3 times (?:daily|a day)|tid|tds)$',
  ).hasMatch(f))
    return 3;
  if (RegExp(
    r'^(?:four times (?:daily|a day)|4 times (?:daily|a day)|qid|qds)$',
  ).hasMatch(f))
    return 4;
  return null;
}

int? courseDays(String duration, DateTime starting) {
  final m = RegExp(
    r'^(\d{1,4})\s*(days?|d|weeks?|wks?|months?|দিন|সপ্তাহ|মাস)$',
  ).firstMatch(rxText(duration));
  if (m == null) return null;
  final n = int.parse(m[1]!);
  if (n < 1 || n > 730) return null;
  final unit = m[2]!;
  if (unit.startsWith('month') || unit == 'মাস') {
    if (n > 24) return null;
    final endOfMonth = DateTime.utc(starting.year, starting.month + n + 1, 0);
    final last = starting.day < endOfMonth.day ? starting.day : endOfMonth.day;
    return DateTime.utc(starting.year, starting.month + n, last)
        .difference(DateTime.utc(starting.year, starting.month, starting.day))
        .inDays;
  }
  final days = (unit.startsWith('w') || unit == 'সপ্তাহ') ? n * 7 : n;
  return days <= 730 ? days : null;
}

bool countedForm(String form) =>
    RegExp(r'^(?:tab\.?|tablet|tablets|cap\.?|capsule|capsules)$')
        .hasMatch(rxText(form));

// Frequency is not a dose: only use an explicit unit count.
(int?, String) explicitDose(String frequency) {
  final normalized = rxText(frequency);
  final match = RegExp(
    r'^(?:take )?(\d{1,2})\s+(?:tablets?|capsules?|units?)\s+(.+)$',
  ).firstMatch(normalized);
  if (match == null) return (null, normalized);
  final amount = int.parse(match[1]!);
  if (amount < 1 || doseCount(match[2]!) == null) return (null, normalized);
  return (amount, match[2]!);
}

int? dailyUnits(String frequency, int? confirmedDose) {
  final slots = slotDoses(frequency);
  if (slots != null) return slots.fold<int>(0, (sum, x) => sum + x);
  final (writtenDose, timing) = explicitDose(frequency);
  if (writtenDose != null &&
      confirmedDose != null &&
      writtenDose != confirmedDose)
    return null;
  final units = writtenDose ?? confirmedDose;
  final count = doseCount(timing);
  return units == null || units < 1 || units > 99 || count == null
      ? null
      : units * count;
}

int? mealDirection(String meal) {
  final s = rxText(meal);
  if (s.isEmpty ||
      RegExp(r'^(?:with (?:food|meals?)|সাথে|খাবারের সাথে|no preference)$')
          .hasMatch(s))
    return 0;
  final before = RegExp(
    r'\bbefore (?:food|meal|meals)\b|khabar age|খাবার আগে|খাওয়ার আগে|খাবারের আগে',
  ).hasMatch(s);
  final after = RegExp(
    r'\bafter (?:food|meal|meals)\b|khabar pore|খাবার পরে|খাওয়ার পরে|খাবারের পরে',
  ).hasMatch(s);
  if (before == after) return null;
  return before ? -1 : 1;
}

int? explicitMealOffset(String meal) {
  final match = RegExp(r'\b(\d{1,3})\s*(minutes?|mins?|min|hours?|hrs?|hr)\b')
      .firstMatch(rxText(meal));
  if (match == null) return null;
  final n = int.parse(match[1]!) * (match[2]!.startsWith('h') ? 60 : 1);
  return n > 0 && n <= 180 ? n : null;
}

Map<int, int>? mealSlotTimes(
  String frequency,
  String meal,
  List<int> meals, {
  int? before,
  int? after,
}) {
  final (_, timing) = explicitDose(frequency);
  final counts = slotDoses(timing);
  final count = doseCount(timing);
  final direction = mealDirection(meal);
  if (meals.length != 3 ||
      isPrn('$frequency $meal') ||
      intervalHours(timing) != null ||
      counts?.length == 4 ||
      count == null ||
      count == 4 ||
      direction == null)
    return null;
  final offset = direction == 0
      ? 0
      : explicitMealOffset(meal) ?? (direction < 0 ? before : after);
  if (offset == null) return null;
  final slots = counts != null
      ? [
          for (var i = 0; i < 3; i++)
            if (counts[i] > 0) i,
        ]
      : count == 2
      ? [0, 2]
      : count == 3
      ? [0, 1, 2]
      : <int>[];
  final result = {
    for (final slot in slots) slot: meals[slot] + direction * offset,
  };
  if (result.isEmpty || result.values.any((t) => t < 0 || t >= 1440))
    return null;
  return result;
}

List<int>? proposedTimes(
  String frequency,
  String meal,
  List<int> meals, {
  int? before,
  int? after,
  int? first,
  bool evenly = false,
}) {
  final (_, timing) = explicitDose(frequency);
  if (mealDirection(meal) == null || isPrn('$frequency $meal')) return null;
  final count = doseCount(timing);
  if (count == null) return null;
  final interval = intervalHours(timing);
  if (interval != null || count == 4) {
    if (first == null ||
        meal.trim().isNotEmpty ||
        (interval == null && !evenly))
      return null;
    return [
      for (var i = 0; i < count; i++) (first + i * (interval ?? 6) * 60) % 1440,
    ]..sort();
  }
  if (slotDoses(timing)?.length == 4) return null;
  if (count == 1 && slotDoses(timing) == null) {
    return first == null || meal.trim().isNotEmpty ? null : [first];
  }
  return mealSlotTimes(
    frequency,
    meal,
    meals,
    before: before,
    after: after,
  )?.values.toList();
}

bool isParacetamol(String name, String form) =>
    RegExp(r'^(?:paracetamol|acetaminophen|napa|ace)(?:\s+\d+(?:\s*mg)?)?$')
        .hasMatch(rxText(name)) ||
    RegExp(r'^(?:paracetamol|acetaminophen)\b').hasMatch(rxText(name));

int scheduleSection(int minute) => minute >= 300 && minute < 720
    ? 0
    : minute < 1080 && minute >= 720
    ? 1
    : 2;
String dateKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
