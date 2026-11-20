import '../localization.dart';

import 'package:flutter/material.dart';

import '../design.dart';
import '../models.dart';
import '../motion.dart';
import '../services/api.dart';
import 'documents_live.dart';

class ExtractionLive extends StatefulWidget {
  const ExtractionLive({super.key, required this.documentId});
  final String documentId;
  @override
  State<ExtractionLive> createState() => _ExtractionLiveState();
}

class _ExtractionLiveState extends State<ExtractionLive> {
  bool started = false, busy = true;
  String? error;
  String stage = 'Uploading prescription…';
  Map<String, dynamic>? result;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!started) {
      started = true;
      Future.microtask(extract);
    }
  }

  Future<void> extract() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final s = Scope.of(context);
      final owner = s.userId, token = s.api.token;
      setState(() => stage = 'Uploading prescription…');
      await s.ensureDocumentUploaded(widget.documentId);
      if (!mounted) return;
      if (owner != s.userId || token != s.api.token) {
        throw ApiError(0, 'Your account changed. Open the prescription again.');
      }
      setState(() => stage = 'Reading your prescription…');
      final data = await s.api.request(
        'POST',
        '/documents/${widget.documentId}/extract',
      );
      if (mounted && owner == s.userId && token == s.api.token) {
        setState(() => result = Map<String, dynamic>.from(data));
      }
    } catch (e) {
      if (mounted)
        setState(
          () => error = e is ApiError
              ? e.message
              : e is StateError
              ? e.message.toString()
              : 'The prescription could not be processed. Check the connection and retry.',
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext c) => AppFrame(
    back: true,
    title: tr('Medicines found'),
    subtitle: tr('Check each field against the original image before saving.'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        rowTile(
          Icons.image_outlined,
          tr('View Original Prescription'),
          tr('Compare names, strengths and instructions.'),
          () => Navigator.push(
            c,
            MaterialPageRoute(
              builder: (_) => DocumentViewer(id: widget.documentId),
            ),
          ),
        ),
        if (busy)
          Padding(
            padding: EdgeInsets.all(25),
            child: Center(child: MedLoader(label: tr(stage))),
          ),
        if (error != null) ...[
          note(tr(error!)),
          TextButton(
            onPressed: busy ? null : extract,
            child: Text(tr('Retry extraction')),
          ),
        ],
        if (result != null) ...[
          if (result!['status'] == 'not_configured')
            note(tr(result!['message']), color: blue),
          if (result!['status'] == 'no_readable_medicines')
            note(
              tr(
                'No readable medicines were returned. Use the image to enter details manually.',
              ),
            ),
          for (final raw in result!['candidates'] as List? ?? [])
            Builder(
              builder: (context) {
                final candidate = Map<String, dynamic>.from(raw);
                return Tile(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tr(
                          candidate['name'].toString().isEmpty
                              ? 'Unreadable name'
                              : candidate['name'],
                        ),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      gap(8),
                      for (final entry in {
                        'Strength': 'strength',
                        'Dosage form': 'form',
                        'Frequency': 'frequency',
                        'Meal timing': 'meal',
                        'Duration': 'duration',
                        'Route': 'route',
                        'Special instructions': 'instruction',
                      }.entries)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 5),
                          child: Text(
                            tr(
                              '${entry.key}: ${candidate[entry.value].toString().isEmpty ? 'Not extracted' : candidate[entry.value]}',
                            ),
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      if ((candidate['evidence'] as String? ?? '').isNotEmpty)
                        small(tr('Source text: ${candidate['evidence']}')),
                      gap(10),
                      Pill(tr('Needs your review'), color: Colors.orange),
                      TextButton(
                        onPressed: () => go(
                          c,
                          'medicine',
                          arguments: {
                            ...candidate,
                            'source_document_id': widget.documentId,
                          },
                        ),
                        child: Text(tr('Review, edit and save medicine →')),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
        gap(12),
        ActionButton(
          tr('Enter manually'),
          icon: Icons.edit_outlined,
          onTap: () => go(
            c,
            'medicine',
            arguments: {'source_document_id': widget.documentId},
          ),
        ),
        gap(12),
        TextButton(
          onPressed: () => go(c, 'today'),
          child: Text(tr('Open medicine list →')),
        ),
      ],
    ),
  );
}
