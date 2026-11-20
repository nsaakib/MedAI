import '../localization.dart';
import '../report_types.dart';

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show Uint8List;
import 'package:image_picker/image_picker.dart';

import '../design.dart';
import '../motion.dart';
import '../models.dart';
import 'workspace.dart';

class DocumentsLive extends StatefulWidget {
  const DocumentsLive({super.key, this.reportOnly = false});
  final bool reportOnly;
  @override
  State<DocumentsLive> createState() => _DocumentsLiveState();
}

class _DocumentsLiveState extends State<DocumentsLive> {
  bool busy = false;
  String sourceKind = 'Prescription';
  // medai: prescription autoscan
  Uint8List? image;
  String? savedReportId;
  String? openedReportId;
  @override
  Widget build(BuildContext c) {
    final s = Scope.of(c);
    final current = s.documents
        .where(
          (d) =>
              d['id'] ==
              (widget.reportOnly ? savedReportId : s.currentDocumentId),
        )
        .firstOrNull;
    // React to both immediate uploads and a queued upload completing later.
    // Never navigate during build or reopen a report after returning from review.
    if (!busy &&
        current != null &&
        current['kind'] == 'Lab Report' &&
        current['uploaded'] == true &&
        current['id'] == savedReportId &&
        openedReportId != savedReportId) {
      openedReportId = savedReportId;
      final report = Map<String, dynamic>.from(current);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || ModalRoute.of(context)?.isCurrent != true) {
          openedReportId = null;
          return;
        }
        final route = MaterialPageRoute<void>(
          builder: (_) => ReportReview(report: report),
        );
        if (widget.reportOnly) {
          Navigator.of(context).pushReplacement<void, void>(route);
        } else {
          Navigator.of(context).push<void>(route);
        }
      });
    }
    return AppFrame(
      back: true,
      title: tr(
        widget.reportOnly
            ? 'Upload report'
            : 'Scan prescription or upload a report',
      ),
      tab: widget.reportOnly ? 1 : 0,
      subtitle: tr(
        widget.reportOnly
            ? 'Med.ai automatically identifies the report type. If needed, the image is read by your configured Groq service.'
            : 'Take a clear photo. Prescription scanning starts automatically.',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SyncStatus(),
          if (!widget.reportOnly && sourceKind == 'Lab Report')
            note(
              tr(
                'Med.ai automatically identifies the report type. If needed, the image is read by your configured Groq service.',
              ),
              color: blue,
            ),
          if (!widget.reportOnly)
            Segments(
              labels: const ['Prescription', 'Lab Report'],
              value: sourceKind == 'Prescription' ? 0 : 1,
              onChanged: (v) {
                if (!busy)
                  setState(
                    () => sourceKind = v == 0 ? 'Prescription' : 'Lab Report',
                  );
              },
            ),
          if (widget.reportOnly || sourceKind == 'Lab Report')
            DropdownButtonFormField<String>(
              initialValue: s.docLanguage,
              decoration: InputDecoration(labelText: tr('OCR language')),
              items: [
                DropdownMenuItem(value: 'eng', child: Text(tr('English'))),
                DropdownMenuItem(value: 'ben', child: Text(tr('Bengali'))),
                DropdownMenuItem(
                  value: 'eng+ben',
                  child: Text(tr('Mixed English + Bengali')),
                ),
              ],
              onChanged: (v) => s.docLanguage = v!,
            ),
          gap(15),
          Row(
            children: [
              Expanded(
                child: rowTile(
                  Icons.camera_alt_outlined,
                  tr('Take Photo'),
                  tr('Use your camera'),
                  busy ? null : () => pick(ImageSource.camera),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: rowTile(
                  Icons.photo_outlined,
                  tr('Upload File'),
                  tr('Choose JPG or PNG'),
                  busy ? null : () => pick(ImageSource.gallery),
                ),
              ),
            ],
          ),
          if (image != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.memory(
                image!,
                height: 330,
                width: double.infinity,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              ),
            ),
            gap(14),
            ActionButton(
              tr(
                busy
                    ? 'Uploading and reading…'
                    : (widget.reportOnly || sourceKind == 'Lab Report'
                          ? 'Upload and review report'
                          : 'Save Document Securely'),
              ),
              icon: Icons.cloud_upload_outlined,
              onTap: busy ? null : save,
            ),
            gap(12),
          ],
          if (busy) ...[
            const LinearProgressIndicator(),
            gap(10),
            small(
              tr(
                sourceKind == 'Prescription' && !widget.reportOnly
                    ? 'Saving your prescription securely…'
                    : 'Uploading securely and checking the report. Review opens when the upload finishes.',
              ),
            ),
          ],
          if (current != null) ...[
            Pill(
              tr(
                current['uploaded'] == true
                    ? 'Uploaded securely'
                    : 'Queued on this device',
              ),
              color: current['uploaded'] == true ? mint : Colors.orange,
            ),
            if (current['kind'] == 'Lab Report') ...[
              if (current['uploaded'] != true)
                note(
                  tr(
                    'Saved on this device. Connect to the backend and use Sync now above. Review opens after upload completes.',
                  ),
                  color: blue,
                ),
              gap(12),
              Heading(
                tr(current['report_title'] as String? ?? 'Untitled report'),
              ),
              gap(12),
              if (current['uploaded'] == true)
                ActionButton(
                  tr('Review report details'),
                  onTap: () => openReport(c, current),
                ),
            ] else ...[
              Heading(tr('Recognized Text')),
              Tile(
                child: SelectableText(
                  (current['ocr_text'] as String? ?? '').trim().isEmpty
                      ? 'No text available. Enter medicine details manually from your source.'
                      : current['ocr_text'],
                  style: const TextStyle(fontSize: 12, height: 1.6),
                ),
              ),
              small(
                tr(
                  current['ocr_engine'] == 'tesseract'
                      ? 'OCR text needs careful review, especially handwriting and medicine names.'
                      : 'OCR is unavailable or produced no text. Your document is still saved.',
                ),
              ),
              gap(14),
              if (current['kind'] == 'Prescription') ...[
                ActionButton(
                  tr('Read / Review Prescription'),
                  icon: Icons.document_scanner_outlined,
                  onTap: busy
                      ? null
                      : () => go(c, 'ocr-review', arguments: current['id']),
                ),
                gap(12),
              ],
              ActionButton(
                tr('Enter Medicine from This Document'),
                icon: Icons.edit_outlined,
                onTap: () => go(
                  c,
                  'medicine',
                  arguments: {'source_document_id': current['id']},
                ),
              ),
            ],
          ],
          gap(15),
          small(
            tr(
              'The app encrypts your image and uploads it to your configured Med.ai server when connected. Your personal reports and questions stay on that server.',
            ),
          ),
        ],
      ),
    );
  }

  Future<void> pick(ImageSource source) async {
    setState(() => busy = true);
    try {
      final file = await ImagePicker().pickImage(
        source: source,
        maxWidth: 2200,
        maxHeight: 2200,
        imageQuality: 88,
      );
      if (file == null) return;
      final bytes = await file.readAsBytes();
      if (mounted)
        setState(() {
          image = bytes;
          savedReportId = null;
          openedReportId = null;
        });
      if (mounted && !widget.reportOnly && sourceKind == 'Prescription') {
        await save();
      }
    } catch (e) {
      if (mounted)
        message(
          context,
          tr('Could not access image'),
          tr('Check camera/photo permissions in your device settings.'),
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    final s = Scope.of(context);
    setState(() => busy = true);
    try {
      final prescription = !widget.reportOnly && sourceKind == 'Prescription';
      final id = await s.queueDocument(
        image!,
        kind: prescription ? 'Prescription' : 'Lab Report',
        language: prescription ? 'eng+ben' : null,
      );
      if (mounted)
        setState(() {
          savedReportId = id;
          image = null;
        });
      if (mounted &&
          prescription &&
          ModalRoute.of(context)?.isCurrent == true) {
        go(context, 'ocr-review', arguments: id);
      }
    } catch (e) {
      if (mounted)
        message(context, tr('Could not save document'), tr(e.toString()));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}

class RecordsLive extends StatelessWidget {
  const RecordsLive({super.key, this.history = false});
  final bool history;
  Future<void> cancelQueued(BuildContext c, String id) async {
    final s = Scope.of(c);
    final accepted = await showDialog<bool>(
      context: c,
      builder: (d) => AlertDialog(
        title: Text(tr('Remove queued document?')),
        content: Text(
          tr(
            'This removes the local queued image and its links from entered medicines. Your medicine entries are kept.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: Text(tr('Keep')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(d, true),
            child: Text(tr('Remove')),
          ),
        ],
      ),
    );
    if (accepted != true || s.syncing) return;
    s.uploads.removeWhere((u) => u['id'] == id);
    s.documents.removeWhere((d) => d['id'] == id);
    for (final m in s.medicines) {
      if (m.sourceDocumentId == id) m.sourceDocumentId = null;
    }
    if (s.currentDocumentId == id) {
      s.currentDocumentId = null;
      s.document = null;
    }
    try {
      await s.commit();
    } catch (e) {
      if (c.mounted) message(c, tr('Could not save'), tr(e.toString()));
    }
  }

  @override
  Widget build(BuildContext c) {
    if (!history) return const ReportsLibrary();
    final s = Scope.of(c);
    return AppFrame(
      title: tr(history ? 'Your Health History' : 'Reports and History'),
      subtitle: tr('Your stored documents and recorded care activity.'),
      tab: history ? 3 : 1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SyncStatus(),
          ActionButton(
            tr('Add Document'),
            icon: Icons.add,
            onTap: () => go(c, 'add'),
          ),
          gap(18),
          Heading(tr('Medical Documents')),
          if (s.documents.isEmpty)
            note(tr('Your uploaded documents will appear here.'), color: blue),
          for (final d in s.documents)
            rowTile(
              Icons.description_outlined,
              tr(d['kind'] ?? 'Document'),
              tr(
                '${DateTime.fromMillisecondsSinceEpoch((d['created'] as int) * 1000).toLocal()}\n${d['uploaded'] == true ? 'Stored on server' : 'Queued for upload'}',
              ),
              () => Navigator.push(
                c,
                MaterialPageRoute<void>(
                  builder: (_) => DocumentViewer(id: d['id']),
                ),
              ),
              trailing: d['uploaded'] == true
                  ? null
                  : IconButton(
                      tooltip: tr('Cancel queued upload'),
                      onPressed: s.syncing
                          ? null
                          : () => cancelQueued(c, d['id']),
                      icon: const Icon(Icons.close, size: 18, color: muted),
                    ),
            ),
          Heading(tr('Medication Activity')),
          for (final d in s.doses.reversed.take(30))
            rowTile(
              Icons.check_circle_outline,
              tr(
                s.medicines
                        .where((m) => m.id == d['medicine_id'])
                        .firstOrNull
                        ?.name ??
                    'Medicine',
              ),
              tr('Dose logged · ${d['logged_at']}'),
              null,
              color: mint,
            ),
          if (s.doses.isEmpty) small(tr('No doses recorded yet.')),
          gap(15),
          rowTile(
            Icons.people_outline,
            tr('Care Team Responses'),
            tr('View submitted review requests and notes.'),
            () => go(c, 'cases'),
          ),
        ],
      ),
    );
  }
}

class DocumentViewer extends StatefulWidget {
  const DocumentViewer({super.key, required this.id, this.tab = 0});
  final String id;
  final int tab;
  @override
  State<DocumentViewer> createState() => _DocumentViewerState();
}

class _DocumentViewerState extends State<DocumentViewer> {
  Future<Uint8List>? load;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    load ??= read();
  }

  Future<Uint8List> read() async {
    final s = Scope.of(context);
    final local = s.uploads.where((u) => u['id'] == widget.id).firstOrNull;
    if (local != null) return base64Decode(local['bytes']);
    return Uint8List.fromList(await s.api.image(widget.id));
  }

  @override
  Widget build(BuildContext c) => AppFrame(
    back: true,
    title: tr('Source Document'),
    tab: widget.tab,
    child: FutureBuilder<Uint8List>(
      future: load,
      builder: (c, snap) => snap.hasData
          ? InteractiveViewer(
              minScale: 1,
              maxScale: 5,
              child: Image.memory(
                snap.data!,
                width: double.infinity,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              ),
            )
          : snap.hasError
          ? note(
              tr(
                'Could not load this image. Connect to the server and try again.',
              ),
              color: blue,
            )
          : const Center(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: MedLoader(label: 'Loading…'),
              ),
            ),
    ),
  );
}

String reportDay(Map<String, dynamic> report) =>
    report['report_date'] as String? ??
    DateTime.fromMillisecondsSinceEpoch(
      (report['created'] as int) * 1000,
    ).toLocal().toIso8601String().substring(0, 10);

String reportTitle(Map<String, dynamic> report) =>
    report['report_title'] as String? ?? 'Untitled report';

Future<void> openReport(BuildContext context, Map<String, dynamic> report) =>
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => report['uploaded'] == true
            ? ReportReview(report: report)
            : DocumentViewer(id: report['id'] as String, tab: 1),
      ),
    );

class ReportsLibrary extends StatefulWidget {
  const ReportsLibrary({super.key});

  @override
  State<ReportsLibrary> createState() => _ReportsLibraryState();
}

class _ReportsLibraryState extends State<ReportsLibrary> {
  bool byDoctor = false;
  String query = '';

  @override
  Widget build(BuildContext context) {
    final state = Scope.of(context);
    final reports =
        state.documents
            .where((d) => d['kind'] == 'Lab Report')
            .where(
              (d) =>
                  [
                    reportTitle(d),
                    d['test_name'],
                    d['requested_by'],
                    reportDay(d),
                  ].any(
                    (value) =>
                        value is String && value.toLowerCase().contains(query),
                  ),
            )
            .toList()
          ..sort((a, b) => reportDay(b).compareTo(reportDay(a)));
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final d in reports) {
      final key = byDoctor
          ? (d['requested_by'] as String? ?? '').trim().toLowerCase()
          : reportDay(d).substring(0, 7);
      (groups[key] ??= []).add(d);
    }
    final keys = groups.keys.toList();
    if (byDoctor && keys.remove('')) keys.add('');
    return AppFrame(
      title: tr('Your reports'),
      subtitle: tr('Find reports by test name, date, or doctor.'),
      tab: 1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SyncStatus(),
          Segments(
            labels: const ['Recent', 'By doctor'],
            value: byDoctor ? 1 : 0,
            onChanged: (value) => setState(() => byDoctor = value == 1),
          ),
          TextField(
            decoration: InputDecoration(
              prefixIcon: Icon(Icons.search),
              labelText: tr('Search reports'),
            ),
            onChanged: (value) =>
                setState(() => query = value.trim().toLowerCase()),
          ),
          gap(14),
          if (reports.isEmpty)
            note(
              tr(
                query.isEmpty
                    ? 'Upload a report to get started.'
                    : 'No reports match your search.',
              ),
              color: blue,
            ),
          for (final key in keys) ...[
            Heading(
              tr(
                byDoctor
                    ? (key.isEmpty
                          ? 'No doctor listed'
                          : (groups[key]!.first['requested_by'] as String)
                                .trim())
                    : MaterialLocalizations.of(
                        context,
                      ).formatMonthYear(DateTime.parse(key + '-01')),
              ),
            ),
            for (final d in groups[key]!)
              rowTile(
                Icons.description_outlined,
                tr(reportTitle(d)),
                tr(
                  [
                    d['test_name'] ??
                        (d['uploaded'] == true
                            ? 'Report type not identified'
                            : 'Queued for upload'),
                    (d['report_date'] == null ? 'Uploaded ' : '') +
                        reportDay(d),
                    if (!byDoctor && d['requested_by'] != null)
                      'Requested by ' + (d['requested_by'] as String),
                    if (d['uploaded'] == true && d['report_reviewed'] != true)
                      'Review details',
                  ].join('\n'),
                ),
                () => openReport(context, d),
              ),
          ],
          gap(12),
          ActionButton(
            tr('Upload report'),
            icon: Icons.add,
            onTap: () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) => const DocumentsLive(reportOnly: true),
              ),
            ),
          ),
          gap(12),

          TextButton(
            onPressed: () => go(context, 'history'),
            child: Text(tr('View all medical documents')),
          ),
        ],
      ),
    );
  }
}

class ReportReview extends StatefulWidget {
  const ReportReview({super.key, required this.report});
  final Map<String, dynamic> report;

  @override
  State<ReportReview> createState() => _ReportReviewState();
}

class _ReportReviewState extends State<ReportReview> {
  static const types = reportTypeLabels;
  late final TextEditingController doctor;
  String type = '';
  DateTime? day;
  bool saving = false;
  bool identifying = false;
  bool started = false;
  bool edited = false;
  String? detectionError;
  late Map<String, dynamic> report;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!started) {
      started = true;
      final state = Scope.of(context);
      if (state.signedIn &&
          report['report_reviewed'] != true &&
          (report['report_detection_version'] != 1 ||
              report['report_detection_status'] != 'identified')) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) identify();
        });
      }
    }
  }

  Future<void> identify() async {
    final state = Scope.of(context);
    setState(() {
      identifying = true;
      detectionError = null;
    });
    try {
      final result = await state.classifyReport(report['id'] as String);
      if (!mounted) return;
      setState(() {
        report = result;
        detectionError = result['report_read_error'] as String?;
        if (!edited) {
          type = types.containsKey(result['report_type'])
              ? result['report_type'] as String
              : '';
          doctor.text = result['requested_by'] as String? ?? '';
          day = DateTime.tryParse(result['report_date'] as String? ?? '');
        }
      });
    } catch (error) {
      if (mounted) setState(() => detectionError = error.toString());
    } finally {
      if (mounted) setState(() => identifying = false);
    }
  }

  @override
  void initState() {
    super.initState();
    final d = widget.report;
    report = Map<String, dynamic>.from(d);
    type = types.containsKey(d['report_type'])
        ? d['report_type'] as String
        : '';
    doctor = TextEditingController(text: d['requested_by'] as String? ?? '');
    day = DateTime.tryParse(d['report_date'] as String? ?? '');
  }

  @override
  void dispose() {
    doctor.dispose();
    super.dispose();
  }

  Future<void> chooseDate() async {
    final start = DateTime(1900);
    final end = DateTime(2100, 12, 31);
    final current = day;
    final chosen = await showDatePicker(
      context: context,
      initialDate:
          current != null && !current.isBefore(start) && !current.isAfter(end)
          ? current
          : DateTime.now(),
      firstDate: start,
      lastDate: end,
    );
    if (mounted && chosen != null) setState(() => day = chosen);
  }

  Future<void> save() async {
    final state = Scope.of(context);
    setState(() => saving = true);
    try {
      await state.updateReportDetails(widget.report['id'] as String, {
        'report_type': type.isEmpty ? null : type,
        'requested_by': doctor.text.trim(),
        'report_date': day?.toIso8601String().substring(0, 10),
      });
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted)
        message(
          context,
          tr('Could not save report details'),
          tr(error.toString()),
        );
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = Scope.of(context);
    return AppFrame(
      title: tr('Review report details'),
      back: true,
      tab: 1,
      subtitle: tr('Check the details against your original report.'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          rowTile(
            Icons.description_outlined,
            tr('Original report'),
            tr('View uploaded image'),
            () => Navigator.of(context).push<void>(
              MaterialPageRoute(
                builder: (_) =>
                    DocumentViewer(id: widget.report['id'] as String, tab: 1),
              ),
            ),
          ),
          if (!identifying &&
              (report['ocr_text'] as String? ?? '').trim().isEmpty)
            note(
              tr(
                'Your original report is saved, but no readable text was detected. Retry identification with a clearer image, or optionally correct the details below.',
              ),
              color: blue,
            ),
          if (!identifying && type == 'multiple' && report['test_name'] != null)
            note(report['test_name'].toString(), color: blue),
          if (identifying) ...[
            const LinearProgressIndicator(),
            note(tr('Identifying report type…'), color: blue),
          ] else if (detectionError != null) ...[
            note(
              tr(
                'Automatic identification could not finish. Your original report is saved.',
              ),
              color: blue,
            ),
            Text(detectionError!),
            TextButton(
              onPressed: identify,
              child: Text(tr('Retry identification')),
            ),
          ] else if (report['report_detection_status'] == 'identified' &&
              report['report_reviewed'] != true)
            note(
              '${tr('Automatically identified')}: ${tr(types[type] ?? 'Medical report')}',
              color: blue,
            )
          else if (report['report_detection_status'] == 'unrecognized' ||
              report['report_detection_status'] == 'read_failed') ...[
            note(
              tr(
                'Report type could not be identified confidently. You can keep it as a medical report or correct it below.',
              ),
              color: blue,
            ),
            TextButton(
              onPressed: identify,
              child: Text(tr('Retry identification')),
            ),
          ],
          if (report['report_reviewed'] != true)
            note(
              tr(
                'Check the suggested test and requesting doctor. You can correct the automatic label if needed.',
              ),
              color: blue,
            ),
          gap(12),
          Tile(
            child: DropdownButtonFormField<String>(
              isExpanded: true,
              key: ValueKey(type),
              initialValue: type,
              decoration: InputDecoration(labelText: tr('Report type')),
              items: types.entries
                  .map(
                    (e) => DropdownMenuItem(
                      value: e.key,
                      child: Text(tr(e.value), overflow: TextOverflow.ellipsis),
                    ),
                  )
                  .toList(),
              onChanged: saving || identifying
                  ? null
                  : (value) => setState(() {
                      type = value ?? '';
                      edited = true;
                    }),
            ),
          ),
          gap(14),
          Tile(
            child: TextField(
              controller: doctor,
              enabled: !saving && !identifying,
              maxLength: 100,
              decoration: InputDecoration(
                labelText: tr('Requested by'),
                hintText: tr('Add requesting doctor (optional)'),
              ),
            ),
          ),
          rowTile(
            Icons.calendar_today_outlined,
            tr('Report date'),
            tr(
              day == null
                  ? 'No date listed'
                  : MaterialLocalizations.of(context).formatMediumDate(day!),
            ),
            saving || identifying ? null : chooseDate,
            trailing: day == null
                ? null
                : IconButton(
                    tooltip: tr('Clear report date'),
                    onPressed: saving || identifying
                        ? null
                        : () => setState(() => day = null),
                    icon: const Icon(Icons.close),
                  ),
          ),
          gap(14),

          ActionButton(
            tr(saving ? 'Saving…' : 'Save report'),
            onTap: saving || identifying || state.syncing ? null : save,
          ),
        ],
      ),
    );
  }
}
