import '../localization.dart';

import 'package:flutter/material.dart';

import '../design.dart';
import '../models.dart';
import 'workspace.dart';

class HealthLive extends StatefulWidget {
  const HealthLive({super.key});
  @override
  State<HealthLive> createState() => _HealthLiveState();
}

class _HealthLiveState extends State<HealthLive> {
  String kind = 'heart_rate';
  static const labels = {
    'heart_rate': 'Heart rate',
    'systolic_bp': 'Systolic blood pressure',
    'diastolic_bp': 'Diastolic blood pressure',
    'glucose': 'Glucose',
    'weight': 'Weight',
  };
  static const units = {
    'heart_rate': 'bpm',
    'systolic_bp': 'mmHg',
    'diastolic_bp': 'mmHg',
    'glucose': 'mg/dL',
    'weight': 'kg',
  };
  @override
  Widget build(BuildContext c) {
    final s = Scope.of(c);
    final readings = s.vitals.where((v) => v['kind'] == kind).toList()
      ..sort(
        (a, b) => (a['measured_at'] as String).compareTo(b['measured_at']),
      );
    return AppFrame(
      back: true,
      title: tr('My Health Overview'),
      subtitle: tr('Measurements you enter from your own devices.'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SyncStatus(),
          DropdownButtonFormField<String>(
            initialValue: kind,
            items: [
              for (final e in labels.entries)
                DropdownMenuItem(value: e.key, child: Text(tr(e.value))),
            ],
            onChanged: (v) => setState(() => kind = v!),
            decoration: InputDecoration(labelText: tr('Measurement type')),
          ),
          gap(18),
          Tile(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr(labels[kind]!),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                gap(13),
                Text(
                  tr(
                    readings.isEmpty
                        ? 'No readings yet'
                        : '${readings.last['value']} ${readings.last['unit']}',
                  ),
                  style: const TextStyle(
                    fontSize: 29,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                gap(10),
                small(
                  tr(
                    readings.isEmpty
                        ? 'Add your first measurement below.'
                        : 'Last recorded ${readings.last['measured_at']}',
                  ),
                ),
                if (readings.length >= 2) ...[
                  gap(20),
                  SizedBox(
                    height: 160,
                    child: CustomPaint(
                      painter: ReadingChart(
                        readings
                            .map((v) => (v['value'] as num).toDouble())
                            .toList(),
                      ),
                      size: const Size(double.infinity, 160),
                    ),
                  ),
                  small(
                    tr(
                      'Trend shows only your entered measurements, spaced by entry order.',
                    ),
                  ),
                ],
              ],
            ),
          ),
          ActionButton(
            tr('Add Manual Reading'),
            icon: Icons.add,
            onTap: () => add(c),
          ),
          gap(14),
          Heading(tr('Recorded Measurements')),
          for (final v in readings.reversed.take(30))
            Tile(
              child: Row(
                children: [
                  const Bubble(Icons.monitor_heart_outlined),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr('${v['value']} ${v['unit']}'),
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        small(tr(v['measured_at'])),
                      ],
                    ),
                  ),
                  Pill(tr('Manual')),
                ],
              ),
            ),
          gap(14),
          rowTile(
            Icons.people_outline,
            tr('Ask Your Care Team'),
            tr('Share your readings in a review request.'),
            () => go(c, 'handoff'),
          ),
          small(
            tr(
              'These records do not provide automated diagnosis or emergency monitoring.',
            ),
          ),
        ],
      ),
    );
  }

  void add(BuildContext c) {
    final s = Scope.of(c);
    final form = GlobalKey<FormState>();
    String value = '';
    showDialog<void>(
      context: c,
      builder: (d) => AlertDialog(
        title: Text(tr('Add ${labels[kind]}')),
        content: Form(
          key: form,
          child: TextFormField(
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: tr('Value (${units[kind]})'),
            ),
            onSaved: (v) => value = v!,
            validator: (v) {
              final n = double.tryParse(v ?? '');
              return tr(
                n == null || !n.isFinite || n <= 0 || n > 10000
                    ? 'Enter a positive measurement up to 10000'
                    : null,
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d),
            child: Text(tr('Cancel')),
          ),
          TextButton(
            onPressed: () async {
              if (!form.currentState!.validate()) return;
              form.currentState!.save();
              s.vitals.add({
                'id': identifier(),
                'kind': kind,
                'value': double.parse(value),
                'unit': units[kind],
                'measured_at': DateTime.now().toUtc().toIso8601String(),
                'source': 'manual',
              });
              try {
                await s.commit();
                if (d.mounted) Navigator.pop(d);
              } catch (e) {
                if (d.mounted)
                  message(d, tr('Could not save'), tr(e.toString()));
              }
            },
            child: Text(tr('Save')),
          ),
        ],
      ),
    );
  }
}

class ReadingChart extends CustomPainter {
  ReadingChart(this.values);
  final List<double> values;
  @override
  void paint(Canvas c, Size s) {
    final max = values.reduce((a, b) => a > b ? a : b),
        min = values.reduce((a, b) => a < b ? a : b);
    final span = (max - min).abs() < 1 ? 1.0 : max - min;
    final p = Path();
    for (int i = 0; i < values.length; i++) {
      final x = 8 + i * (s.width - 16) / (values.length - 1);
      final y = 12 + (1 - (values[i] - min) / span) * (s.height - 24);
      if (i == 0) {
        p.moveTo(x, y);
      } else {
        p.lineTo(x, y);
      }
      c.drawCircle(Offset(x, y), 3, Paint()..color = blue);
    }
    c.drawPath(
      p,
      Paint()
        ..color = blue
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant ReadingChart oldDelegate) =>
      oldDelegate.values != values;
}
