import 'package:flutter/material.dart';
import '../localization.dart';

/// Actual retrieved report text, separate from the generated explanation.
class ReportEvidence extends StatelessWidget {
  const ReportEvidence({
    super.key,
    required this.sources,
    required this.onOpen,
  });
  final List<Map<String, dynamic>> sources;
  final void Function(String id) onOpen;

  @override
  Widget build(BuildContext context) {
    if (sources.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        Text(
          tr('Report details used'),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        Text(
          tr(
            'Actual text retrieved from your uploaded report. Check recognition against the original.',
          ),
        ),
        for (var i = 0; i < sources.length; i++)
          ExpansionTile(
            key: ValueKey('report-evidence-${sources[i]['label']}'),
            initiallyExpanded: i == 0,
            tilePadding: EdgeInsets.zero,
            childrenPadding: const EdgeInsets.only(bottom: 12),
            title: Text(
              '[${sources[i]['label'] ?? 'Report'}] ${sources[i]['title'] ?? ''}',
            ),
            subtitle: Text(
              sources[i]['date']?.toString() ?? tr('Date not identified'),
            ),
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: SelectableText(
                  (sources[i]['excerpt'] ?? sources[i]['ocr_excerpt'] ?? '')
                      .toString(),
                  style: const TextStyle(fontSize: 13, height: 1.5),
                ),
              ),
              if (sources[i]['read_error'] is String)
                Text(sources[i]['read_error'] as String),
              if (sources[i]['document_id'] is String)
                TextButton.icon(
                  onPressed: () => onOpen(sources[i]['document_id'] as String),
                  icon: const Icon(Icons.description_outlined),
                  label: Text(tr('View original report')),
                ),
            ],
          ),
      ],
    );
  }
}
