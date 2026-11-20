import '../localization.dart';

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models.dart';

class OcrPilotScanPage extends StatefulWidget {
  const OcrPilotScanPage({super.key});
  @override
  State<OcrPilotScanPage> createState() => _OcrPilotScanPageState();
}

class _OcrPilotScanPageState extends State<OcrPilotScanPage> {
  static const fields = {
    'medicine': 'Medicine',
    'strength': 'Strength',
    'dosage_form': 'Dosage form',
    'frequency': 'Frequency',
    'meal': 'Meal timing',
    'duration': 'Duration',
    'route': 'Route',
    'special_instruction': 'Special instruction',
  };
  Uint8List? image;
  String mode = 'crop', field = 'frequency', message = '';
  bool busy = false;
  List<Map<String, dynamic>> results = [];
  int revision = 0;

  void clearResults() {
    results = [];
    message = '';
    revision++;
  }

  Future<void> pick(ImageSource source) async {
    try {
      final photo = await ImagePicker().pickImage(
        source: source,
        maxWidth: 2400,
        maxHeight: 2400,
        imageQuality: 90,
      );
      if (photo == null || !mounted) return;
      final bytes = await photo.readAsBytes();
      if (!mounted) return;
      if (bytes.length > 6000000) {
        setState(() => message = 'Choose a smaller image (up to 6 MB).');
        return;
      }
      setState(() {
        image = bytes;
        clearResults();
      });
    } catch (e) {
      if (mounted) setState(() => message = 'Could not open the image: $e');
    }
  }

  Future<void> scan() async {
    final photo = image;
    if (photo == null || busy) return;
    final api = Scope.of(context).api;
    setState(() {
      busy = true;
      clearResults();
    });
    try {
      final response = await api.request('POST', '/ocr-pilot/scan', {
        'image_base64': base64Encode(photo),
        'mode': mode,
        'field': field,
      });
      final rows = (response['fields'] as List)
          .map((x) => Map<String, dynamic>.from(x as Map))
          .toList();
      if (!mounted) return;
      setState(() {
        results = rows;
        message = rows.isEmpty
            ? 'No fields found. Try a clear crop of one field.'
            : 'Backend: ${response['elapsed_ms']} ms';
      });
    } catch (e) {
      if (mounted) setState(() => message = 'Scan failed: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(tr('Prescription OCR test'))),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          tr('Routed OCR pilot'),
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        Text(
          tr(
            'Compare each draft with the image. Edits here are for testing only.',
          ),
        ),
        DropdownButton<String>(
          value: mode,
          isExpanded: true,
          onChanged: busy
              ? null
              : (v) => setState(() {
                  mode = v!;
                  clearResults();
                }),
          items: [
            DropdownMenuItem(
              value: 'crop',
              child: Text(tr('One field (already cropped)')),
            ),
            DropdownMenuItem(
              value: 'page',
              child: Text(tr('Full prescription')),
            ),
          ],
        ),
        if (mode == 'crop') ...[
          DropdownButton<String>(
            value: field,
            isExpanded: true,
            onChanged: busy
                ? null
                : (v) => setState(() {
                    field = v!;
                    clearResults();
                  }),
            items: fields.entries
                .map(
                  (e) =>
                      DropdownMenuItem(value: e.key, child: Text(tr(e.value))),
                )
                .toList(),
          ),
          Text(
            tr(
              'Choose a photo containing only the selected field. Try frequency or duration first.',
            ),
          ),
        ],
        Wrap(
          spacing: 10,
          children: [
            OutlinedButton.icon(
              onPressed: busy ? null : () => pick(ImageSource.gallery),
              icon: const Icon(Icons.image_outlined),
              label: Text(tr('Gallery')),
            ),
            OutlinedButton.icon(
              onPressed: busy ? null : () => pick(ImageSource.camera),
              icon: const Icon(Icons.photo_camera_outlined),
              label: Text(tr('Camera')),
            ),
          ],
        ),
        if (image != null)
          Image.memory(image!, height: 220, fit: BoxFit.contain),
        FilledButton(
          onPressed: busy || image == null ? null : scan,
          child: Text(tr(busy ? 'Reading…' : 'Run OCR')),
        ),
        if (message.isNotEmpty) Text(tr(message)),
        for (var i = 0; i < results.length; i++)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: TextFormField(
              key: ValueKey('$revision-$i'),
              initialValue: results[i]['text'] as String? ?? '',
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: tr(fields[results[i]['field']] ?? 'Field'),
                helperText: tr(
                  results[i]['status'] == 'draft'
                      ? "${results[i]['recognizer']} draft · verify against the image"
                      : (results[i]['note'] as String? ?? 'Enter manually'),
                ),
                helperMaxLines: 3,
              ),
            ),
          ),
      ],
    ),
  );
}
