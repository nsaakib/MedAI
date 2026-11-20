import '../localization.dart';

import 'package:flutter/material.dart';

import '../design.dart';
import '../models.dart';
import 'documents_live.dart';
import 'health_live.dart';

const _labels = {
  'systolic_bp': 'Systolic blood pressure',
  'diastolic_bp': 'Diastolic blood pressure',
  'glucose': 'Blood glucose',
  'heart_rate': 'Heart rate',
  'weight': 'Weight',
};

String healthLabel(String key) => _labels[key] ?? key.replaceAll('_', ' ');

class StudioSurface extends StatelessWidget {
  const StudioSurface({
    super.key,
    required this.child,
    this.radius = 20,
    this.padding = const EdgeInsets.all(15),
    this.color = Colors.white,
  });
  final Widget child;
  final double radius;
  final EdgeInsets padding;
  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(radius),
      boxShadow: const [
        BoxShadow(
          color: Color(0x17122d70),
          blurRadius: 18,
          offset: Offset(0, 5),
        ),
      ],
    ),
    child: Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(radius),
      child: Padding(padding: padding, child: child),
    ),
  );
}

class HealthDashboard extends StatefulWidget {
  const HealthDashboard({super.key});

  @override
  State<HealthDashboard> createState() => _HealthDashboardState();
}

class _HealthDashboardState extends State<HealthDashboard> {
  String? account, error;
  bool loaded = false, busy = false, loading = false;
  Map<String, dynamic>? stats;
  int generation = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = Scope.of(context);
    if (!loaded || account != state.userId) {
      final epoch = ++generation;
      loaded = true;
      account = state.userId;
      stats = null;
      error = null;
      busy = false;
      loading = false;
      if (account != null) refresh(state, epoch);
    }
  }

  List<Map<String, dynamic>> rows(dynamic value) => (value as List? ?? const [])
      .map((r) => Map<String, dynamic>.from(r as Map))
      .toList();

  Future<void> refresh(AppState state, int epoch) async {
    if (loading || account == null) return;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final data = await state.api.request('GET', '/statistics');
      if (mounted && generation == epoch)
        setState(() => stats = Map<String, dynamic>.from(data as Map));
    } catch (e) {
      if (mounted && generation == epoch) setState(() => error = e.toString());
    } finally {
      if (mounted && generation == epoch) setState(() => loading = false);
    }
  }

  Future<void> updateReport(
    AppState state,
    String id,
    String action, [
    Object? body,
  ]) async {
    if (busy || loading || account == null) return;
    final epoch = generation;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await state.api.request('POST', '/statistics/reports/$id/$action', body);
      if (mounted && generation == epoch) await refresh(state, epoch);
    } catch (e) {
      if (mounted && generation == epoch) setState(() => error = e.toString());
    } finally {
      if (mounted && generation == epoch) setState(() => busy = false);
    }
  }

  Future<void> addValue(AppState state, String id) async {
    final tests = rows(stats?['supported']);
    if (tests.isEmpty) return;
    final epoch = generation;
    var metric = tests.first;
    var unit = (metric['units'] as List).first as String;
    var value = '';
    final valueForm = GlobalKey<FormState>();
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, redraw) => AlertDialog(
          title: Text(tr('Enter value from report')),
          content: Form(
            key: valueForm,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    tr(
                      'Copy the exact number and unit from the original lab report.',
                    ),
                  ),
                  DropdownButton<String>(
                    value: metric['metric'] as String,
                    isExpanded: true,
                    items: [
                      for (final t in tests)
                        DropdownMenuItem(
                          value: t['metric'] as String,
                          child: Text(tr('${t['name']}')),
                        ),
                    ],
                    onChanged: (key) => redraw(() {
                      metric = tests.firstWhere((t) => t['metric'] == key);
                      unit = (metric['units'] as List).first as String;
                    }),
                  ),
                  DropdownButton<String>(
                    value: unit,
                    isExpanded: true,
                    items: [
                      for (final u in (metric['units'] as List).cast<String>())
                        DropdownMenuItem(value: u, child: Text(tr(u))),
                    ],
                    onChanged: (u) {
                      if (u != null) redraw(() => unit = u);
                    },
                  ),
                  TextFormField(
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: tr('Result value'),
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                    ),
                    onChanged: (v) => value = v.trim(),
                    validator: (_) {
                      final number = double.tryParse(value);
                      return tr(number == null || !number.isFinite || number < 0
                          ? 'Enter the result as a number.'
                          : null);
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: Text(tr('Cancel')),
            ),
            FilledButton(
              onPressed: () {
                if (valueForm.currentState?.validate() != true) return;
                Navigator.pop(c, {
                  'metric': metric['metric'],
                  'unit': unit,
                  'value': double.parse(value),
                });
              },
              child: Text(tr('Save value')),
            ),
          ],
        ),
      ),
    );
    if (mounted && generation == epoch && result != null)
      await updateReport(state, id, 'value', result);
  }

  @override
  Widget build(BuildContext context) {
    final state = Scope.of(context);
    final readings = state.vitals.where((r) => r['value'] is num).toList()
      ..sort((a, b) => '${a['measured_at']}'.compareTo('${b['measured_at']}'));
    final kinds = {..._labels.keys, ...readings.map((r) => '${r['kind']}')};
    final reports = state.documents
        .where((d) => d['kind'] == 'Lab Report')
        .toList();
    for (final report in rows(stats?['reports'])) {
      if (!reports.any((d) => d['id'] == report['document_id'])) {
        reports.add({
          ...report,
          'id': report['document_id'],
          'report_title': report['title'],
          'report_date': report['date'],
          'uploaded': true,
          'statistics_stub': true,
        });
      }
    }
    reports..sort(
      (a, b) => '${b['report_date'] ?? b['created']}'.compareTo(
        '${a['report_date'] ?? a['created']}',
      ),
    );
    return AppFrame(
      back: true,
      title: tr('Statistics'),
      subtitle: tr('Review your readings, trends and uploaded lab reports.'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StudioSurface(
            color: const Color(0xffeaf1ff),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.insights_outlined, color: blue),
                gap(8),
                Text(
                  tr('Your health at a glance'),
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold),
                ),
                gap(6),
                Text(
                  tr('${readings.length} readings · ${reports.length} reports'),
                ),
                if (state.error != null)
                  Text(
                    tr('Showing device records. Some items may not be synced.'),
                  ),
                TextButton(
                  onPressed: () => go(context, 'health'),
                  child: Text(tr('Manage readings')),
                ),
              ],
            ),
          ),
          Heading(tr('Measurements')),
          for (final kind in kinds) ...[
            _reading(kind, readings.where((r) => r['kind'] == kind).toList()),
            gap(12),
          ],
          Heading(tr('Lab report trends')),
          StudioSurface(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr(
                    'Only clearly recognized values with units are plotted. Verify them against the original report. Different units are charted separately.',
                  ),
                ),
                if (loading) const LinearProgressIndicator(),
                TextButton.icon(
                  onPressed: loading || busy
                      ? null
                      : () => refresh(state, generation),
                  icon: const Icon(Icons.refresh),
                  label: Text(tr('Refresh Statistics')),
                ),
              ],
            ),
          ),
          gap(12),
          if (!loading && rows(stats?['series']).isEmpty)
            StudioSurface(
              child: Text(
                tr(
                  'No chartable values from synced report text yet. Upload a clear lab report and refresh.',
                ),
              ),
            ),
          for (final series in rows(stats?['series'])) ...[
            _labSeries(series, reports),
            gap(12),
          ],
          if (busy) const LinearProgressIndicator(),
          if (error != null) ...[
            gap(10),
            StudioSurface(child: Text(tr(error!))),
          ],
          TextButton.icon(
            onPressed: () => go(context, 'ai-studio', arguments: true),
            icon: const Icon(Icons.auto_awesome_outlined),
            label: Text(tr('Discuss statistics in AI Chat')),
          ),
          gap(12),
          Heading(tr('Lab reports')),
          if (reports.isEmpty)
            StudioSurface(
              child: Text(tr('Uploaded lab reports will appear here.')),
            ),
          for (final report in reports) ...[
            _reportCard(state, report, rows(stats?['reports'])),
            gap(10),
          ],
          TextButton(
            onPressed: () => go(context, 'records'),
            child: Text(tr('Open Reports')),
          ),
        ],
      ),
    );
  }

  Widget _labSeries(
    Map<String, dynamic> series,
    List<Map<String, dynamic>> reports,
  ) {
    final points = rows(series['points']);
    final dated = points.where((p) => p['date'] != null).toList()
      ..sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));
    final sample = dated.reversed.take(12).toList().reversed.toList();
    return StudioSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr('${series['name']}'),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          small(tr('${series['unit']} · ${points.length} extracted values')),
          gap(8),
          if (sample.length >= 2) ...[
            SizedBox(
              width: double.infinity,
              height: 82,
              child: CustomPaint(
                painter: ReadingChart(
                  sample.map((p) => (p['value'] as num).toDouble()).toList(),
                ),
              ),
            ),
            small(tr('Recent dated reports, in sequence')),
          ] else
            small(
              tr('Two dated reports in the same unit are needed for a trend.'),
            ),
          for (final p in [
            ...dated.reversed,
            ...points.where((p) => p['date'] == null),
          ].take(12))
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(tr('${p['value']} ${series['unit']}')),
              subtitle: Text(
                tr(
                  '${p['date'] ?? 'Undated'} · ${p['title']} · ${p['origin'] ?? 'OCR'}',
                ),
              ),
              onTap: () => _openSource(p['document_id'], reports),
            ),
        ],
      ),
    );
  }

  void _openSource(dynamic id, List<Map<String, dynamic>> reports) {
    for (final report in reports) {
      if (report['id'] == id) {
        if (report['statistics_stub'] == true) {
          go(context, 'records');
        } else {
          openReport(context, report);
        }
        return;
      }
    }
    go(context, 'records');
  }

  Widget _reportCard(
    AppState state,
    Map<String, dynamic> report,
    List<Map<String, dynamic>> summaries,
  ) {
    final id = report['id'] as String;
    final matched = summaries.where((r) => r['document_id'] == id).toList();
    final info = matched.isEmpty ? null : matched.first;
    final count = rows(info?['extracted']).length;
    return StudioSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.description_outlined, color: blue),
            title: Text(tr('${report['report_title'] ?? 'Lab report'}')),
            subtitle: Text(
              tr(
                report['uploaded'] != true
                    ? 'Waiting to sync'
                    : info == null
                    ? 'Refresh to check results'
                    : count > 0
                    ? '$count chartable results'
                    : info['has_text'] != true
                    ? 'No OCR text yet'
                    : 'OCR did not find values with supported units',
              ),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openSource(id, [report]),
          ),
          if (report['uploaded'] == true && info != null)
            Wrap(
              children: [
                if (info['can_retry'] == true)
                  TextButton(
                    onPressed: busy || loading
                        ? null
                        : () => updateReport(state, id, 'ocr'),
                    child: Text(tr('Retry OCR')),
                  ),
                TextButton(
                  onPressed: busy || loading ? null : () => addValue(state, id),
                  child: Text(tr('Enter lab value')),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _reading(String kind, List<Map<String, dynamic>> rows) {
    final last = rows.isEmpty ? null : rows.last;
    final unit = last?['unit'];
    final series = rows.reversed
        .where((r) => r['unit'] == unit)
        .take(12)
        .toList()
        .reversed
        .toList();
    return StudioSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr(healthLabel(kind)),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          gap(7),
          if (last == null)
            Text(tr('No readings recorded'))
          else ...[
            Text(
              tr('${last['value']} ${unit ?? ''}'),
              style: const TextStyle(
                fontSize: 24,
                color: navy,
                fontWeight: FontWeight.w800,
              ),
            ),
            small(
              tr('Recorded ${last['measured_at']} · ${rows.length} readings'),
            ),
          ],
          if (series.length >= 2) ...[
            gap(8),
            SizedBox(
              width: double.infinity,
              height: 70,
              child: CustomPaint(
                painter: ReadingChart(
                  series.map((r) => (r['value'] as num).toDouble()).toList(),
                ),
              ),
            ),
            small(
              tr(
                'Most recent ${series.length} readings in the same unit, in date order.',
              ),
            ),
          ],
        ],
      ),
    );
  }
}
