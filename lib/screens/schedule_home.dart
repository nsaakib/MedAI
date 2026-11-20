import '../localization.dart';

import 'package:flutter/material.dart';

import '../design.dart';
import '../models.dart';
import '../services/medicine_schedule.dart';
import '../services/dose_tracking.dart';
import 'medicine_setup.dart';
import 'medicines_live.dart';

List<Medicine> medicinesInSection(AppState s, int index) => [
  for (final m in s.medicines)
    if (index == 3 ? m.antibioticGroup : m.verified && _inTime(s, m, index)) m,
];

bool _inTime(AppState s, Medicine m, int index) {
  final day = s.notification.dayNow(s.timezone);
  final courseStart = DateTime.tryParse(m.courseStart ?? '');
  final span = courseStart == null ? null : courseDays(m.duration, courseStart);
  final saved = s.reminders
      .where((r) => r['medicine_id'] == m.id && r['enabled'] == true)
      .toList();
  if (saved.isNotEmpty) {
    return saved.any(
      (r) =>
          activeScheduledDose(r, day) &&
          (r['meal_slot'] ??
                  scheduleSection(
                    (r['hour'] as int) * 60 + (r['minute'] as int),
                  )) ==
              index,
    );
  }
  if (courseStart != null &&
      span != null &&
      (day.isBefore(courseStart) ||
          !day.isBefore(courseStart.add(Duration(days: span)))))
    return false;
  if (isPrn('${m.frequency} ${m.instruction} ${m.meal}')) return false;
  final slots = slotDoses(explicitDose(m.frequency).$2);
  return slots?.length == 3 && slots![index] > 0;
}

Widget _homeShadow({required Widget child, Color tint = blue}) => DecoratedBox(
  decoration: BoxDecoration(
    borderRadius: BorderRadius.circular(18),
    boxShadow: [
      BoxShadow(
        color: tint.withAlpha(34),
        blurRadius: 16,
        offset: const Offset(0, 5),
      ),
      const BoxShadow(
        color: Color(0x160c2058),
        blurRadius: 9,
        offset: Offset(0, 3),
      ),
    ],
  ),
  child: child,
);

class MedicineHomeSections extends StatelessWidget {
  const MedicineHomeSections({super.key});
  static const labels = ['Morning', 'Afternoon', 'Night', 'Antibiotics'];
  static const palettes = [
    [Color(0xffffecae), Color(0xffffb87e)],
    [Color(0xffc4f2f6), Color(0xff97c9ff)],
    [Color(0xff252d67), Color(0xff503d9b)],
    [Color(0xffefe0fe), Color(0xffd7bdff)],
  ];
  static const icons = [
    Icons.wb_sunny_outlined,
    Icons.wb_twilight,
    Icons.nightlight_round,
    Icons.medication_outlined,
  ];

  @override
  Widget build(BuildContext context) {
    final s = Scope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _homeShadow(
          child: Tile(
            color: soft,
            onTap: () => go(context, 'today'),
            child: Row(
              children: [
                const Bubble(Icons.medication_outlined, size: 46),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr('Your Medication Plan'),
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      small(
                        tr(
                          '${s.medicines.length} medicines · ${s.reminders.where((r) => r['enabled'] == true).length} reminder times',
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: blue),
              ],
            ),
          ),
        ),
        Tile(
          color: const Color(0xfff5effc),
          onTap: () => setupMeals(context, s),
          child: Row(
            children: [
              const Bubble(Icons.restaurant_outlined, size: 40),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr(
                        s.mealsConfigured
                            ? 'Edit meal times'
                            : 'Set up meal times',
                      ),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: navy,
                      ),
                    ),
                    if (s.mealsConfigured)
                      small(
                        tr(
                          s.mealMinutes
                              .map(
                                (t) => TimeOfDay(
                                  hour: t ~/ 60,
                                  minute: t % 60,
                                ).format(context),
                              )
                              .join(' · '),
                        ),
                      )
                    else
                      small(tr('Breakfast, lunch and dinner')),
                  ],
                ),
              ),
              const Icon(Icons.edit_outlined, color: blue),
            ],
          ),
        ),
        Row(
          children: [
            Expanded(
              child: _quick(
                context,
                'Add Medicine',
                Icons.add_circle_outline,
                'medicine',
                mint,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _quick(
                context,
                'Health History',
                Icons.history,
                'history',
                blue,
              ),
            ),
          ],
        ),
        gap(12),
        Heading(tr('Medicine schedule')),
        LayoutBuilder(
          builder: (c, box) {
            final one =
                box.maxWidth < 310 || MediaQuery.textScalerOf(c).scale(16) > 23;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (int i = 0; i < labels.length; i++)
                  SizedBox(
                    width: one ? box.maxWidth : (box.maxWidth - 10) / 2,
                    child: _card(c, i, medicinesInSection(s, i)),
                  ),
              ],
            );
          },
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => go(context, 'today'),
            icon: const Icon(Icons.list_alt),
            label: Text(tr('View All Medicines')),
          ),
        ),
        _homeShadow(
          tint: const Color(0xff7a79e8),
          child: Material(
            color: const Color(0xfff2efff),
            borderRadius: BorderRadius.circular(18),
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: () => go(context, 'doctors'),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    const Bubble(Icons.medical_services_outlined, size: 44),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tr('Doctors'),
                            style: TextStyle(
                              color: navy,
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                          small(
                            tr(
                              'Browse the doctor directory by specialty and location',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: blue),
                  ],
                ),
              ),
            ),
          ),
        ),
        gap(16),
        Heading(tr('Explore Med.ai')),
        LayoutBuilder(
          builder: (c, box) {
            const items = [
              (
                'Statistics',
                'See health trends',
                'health-dashboard',
                Icons.analytics_outlined,
                Color(0xffe5efff),
                Color(0xffbfd8ff),
              ),
              (
                'Prices & budget',
                'Plan your purchases',
                'prices',
                Icons.receipt_long_outlined,
                Color(0xffd9f7eb),
                Color(0xffaeeadd),
              ),
              (
                'Find care nearby',
                'Find doctors and pharmacies',
                'care',
                Icons.place_outlined,
                Color(0xffffeed5),
                Color(0xffffd4b7),
              ),
              (
                'Health references',
                'Explore health resources',
                'knowledge',
                Icons.menu_book_outlined,
                Color(0xffede8ff),
                Color(0xffd3c3ff),
              ),
              (
                'Care team updates',
                'Follow your requests',
                'cases',
                Icons.forum_outlined,
                Color(0xffe0f4ff),
                Color(0xffb5e5f5),
              ),
            ];
            final single =
                box.maxWidth < 310 || MediaQuery.textScalerOf(c).scale(16) > 23;
            return Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final (title, subtitle, route, icon, first, second)
                    in items)
                  SizedBox(
                    width: single ? box.maxWidth : (box.maxWidth - 10) / 2,
                    child: _homeShadow(
                      tint: second,
                      child: Material(
                        color: Colors.transparent,
                        borderRadius: BorderRadius.circular(18),
                        clipBehavior: Clip.antiAlias,
                        child: Ink(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [first, second],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                          child: InkWell(
                            onTap: () => go(c, route),
                            child: Padding(
                              padding: const EdgeInsets.all(13),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(icon, color: blue),
                                      const Spacer(),
                                      const Icon(
                                        Icons.arrow_forward_rounded,
                                        size: 16,
                                      ),
                                    ],
                                  ),
                                  gap(8),
                                  Text(
                                    tr(title),
                                    style: const TextStyle(
                                      color: navy,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  gap(4),
                                  small(tr(subtitle)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _quick(
    BuildContext c,
    String title,
    IconData icon,
    String route,
    Color color,
  ) => _homeShadow(
    tint: color,
    child: Tile(
      color: Color.alphaBlend(color.withAlpha(19), Colors.white),
      onTap: () => go(c, route),
      padding: 11,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Bubble(icon, color: color, size: 32),
          gap(6),
          Text(tr(title), style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    ),
  );

  Widget _card(BuildContext c, int i, List<Medicine> rows) {
    final ink = i == 2 ? Colors.white : navy;
    void open() => Navigator.of(c).push(
      MaterialPageRoute<void>(
        builder: (_) => MedicineListLive(sectionTitle: labels[i], section: i),
      ),
    );
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: palettes[i].last.withAlpha(72),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: palettes[i],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            border: Border.all(color: Colors.white.withAlpha(80)),
          ),
          child: InkWell(
            onTap: open,
            child: Stack(
              children: [
                Positioned(
                  right: -12,
                  top: -25,
                  child: Transform.rotate(
                    angle: 0.5,
                    child: Container(
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                        color: Colors.white.withAlpha(40),
                        borderRadius: BorderRadius.circular(i == 1 ? 22 : 60),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 8, 3),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(icons[i], color: ink),
                      gap(6),
                      Text(
                        tr(labels[i]),
                        style: TextStyle(
                          color: ink,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      gap(4),
                      Text(
                        tr(
                          rows.isEmpty
                              ? (i == 3 ? 'No entries' : 'Nothing scheduled')
                              : rows.take(2).map((m) => m.name).join(' · '),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: ink.withAlpha(228),
                          fontSize: 12,
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: IconButton(
                          tooltip: tr('Open ${labels[i]} medicines'),
                          onPressed: open,
                          icon: Icon(Icons.arrow_forward_rounded, color: ink),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
