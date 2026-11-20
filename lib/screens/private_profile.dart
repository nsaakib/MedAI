import '../localization.dart';

import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:pdfx/pdfx.dart';

import '../design.dart';
import '../models.dart';
import '../services/api.dart';

class PrivateProfile extends StatefulWidget {
  const PrivateProfile({super.key});

  @override
  State<PrivateProfile> createState() => _PrivateProfileState();
}

class _PrivateProfileState extends State<PrivateProfile> {
  static const fields = <String, String>{
    'birth_date': 'Birth date (YYYY-MM-DD)',
    'address': 'Address',
    'emergency_contact_name': 'Emergency contact name',
    'emergency_contact_phone': 'Emergency contact phone',
    'medical_notes': 'Medical notes',
  };
  final inputs = {for (final k in fields.keys) k: TextEditingController()};
  final form = GlobalKey<FormState>();
  var files = <Map<String, dynamic>>[];
  var blood = '', category = 'medical';
  String? owner, error;
  bool busy = false, ready = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final id = Scope.of(context).userId;
    if (owner == id) return;
    owner = id;
    for (final entry in inputs.values) {
      entry.clear();
    }
    files = [];
    blood = '';
    ready = busy = false;
    error = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && owner == id && id != null && id.isNotEmpty) run(load);
    });
  }

  @override
  void dispose() {
    for (final controller in inputs.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> run(Future<void> Function(Api api, String? id) task) async {
    if (busy) return;
    final a = Scope.of(context).api, id = owner;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await task(a, id);
    } catch (e) {
      if (mounted && id == owner) {
        setState(
          () => error = e is ApiError
              ? e.message
              : 'The action could not be completed. Please try again.',
        );
      }
    } finally {
      if (mounted && id == owner) setState(() => busy = false);
    }
  }

  Future<void> load(Api a, String? id, {bool keepFields = false}) async {
    final data =
        await a
                .request('GET', '/private-profile')
                .timeout(const Duration(seconds: 15))
            as Map;
    if (!mounted || id != owner) return;
    final details = data['details'] as Map;
    setState(() {
      if (!keepFields) {
        for (final entry in inputs.entries) {
          entry.value.text = details[entry.key]?.toString() ?? '';
        }
        blood = details['blood_group']?.toString() ?? '';
      }
      files = (data['files'] as List)
          .whereType<Map>()
          .map((r) => Map<String, dynamic>.from(r))
          .toList();
      ready = true;
    });
  }

  Future<void> save(Api a, String? id) async {
    if (!(form.currentState?.validate() ?? false)) return;
    await a
        .request('PUT', '/private-profile', {
          'blood_group': blood,
          for (final e in inputs.entries)
            e.key: e.key == 'birth_date' && e.value.text.trim().isEmpty
                ? null
                : e.value.text.trim(),
        })
        .timeout(const Duration(seconds: 15));
    if (mounted && id == owner) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(tr('Profile details saved.'))));
    }
  }

  Future<void> pick(Api a, String? id) async {
    final session = a.token;
    final file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'PDF and images',
          extensions: ['pdf', 'jpg', 'jpeg', 'png'],
          mimeTypes: ['application/pdf', 'image/jpeg', 'image/png'],
          uniformTypeIdentifiers: [
            'com.adobe.pdf',
            'public.jpeg',
            'public.png',
          ],
          webWildCards: ['application/pdf', 'image/jpeg', 'image/png'],
        ),
      ],
    );
    if (file == null || !mounted || id != owner || session != a.token) return;
    if (await file.length() > 8 * 1024 * 1024) {
      throw ApiError(413, 'Choose a document up to 8 MB.');
    }
    if (!mounted || id != owner || session != a.token) return;
    final bytes = await file.readAsBytes();
    if (!mounted || id != owner || session != a.token) return;
    final req = http.MultipartRequest(
      'POST',
      Uri.parse('${Api.baseUrl}/api/private-profile/files'),
    );
    req.headers['Authorization'] = 'Bearer $session';
    req.fields['category'] = category;
    req.files.add(
      http.MultipartFile.fromBytes('file', bytes, filename: file.name),
    );
    final res = await http.Response.fromStream(
      await a.client.send(req).timeout(const Duration(seconds: 30)),
    ).timeout(const Duration(seconds: 30));
    if (res.statusCode != 201) {
      final body = jsonDecode(res.body);
      final detail = body is Map ? body['detail'] : null;
      throw ApiError(
        res.statusCode,
        detail is String ? detail : 'Document was not saved.',
      );
    }
    if (mounted && id == owner && session == a.token) {
      final item = Map<String, dynamic>.from(jsonDecode(res.body) as Map);
      setState(() => files = [item, ...files]);
    }
  }

  Future<void> view(Api a, String? id, Map<String, dynamic> file) async {
    final r = await a.client
        .get(
          Uri.parse('${Api.baseUrl}/api/private-profile/files/${file['id']}'),
          headers: {'Authorization': 'Bearer ${a.token}'},
        )
        .timeout(const Duration(seconds: 30));
    if (r.statusCode != 200)
      throw ApiError(r.statusCode, 'Could not open the attachment.');
    if (!mounted || id != owner) return;
    if ((file['media_type'] as String).startsWith('image/')) {
      await showDialog<void>(
        context: context,
        builder: (d) => AlertDialog(
          title: Text(tr(file['name'] as String)),
          content: InteractiveViewer(child: Image.memory(r.bodyBytes)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(d),
              child: Text(tr('Close')),
            ),
          ],
        ),
      );
    } else {
      final pdf = PdfController(document: PdfDocument.openData(r.bodyBytes));
      try {
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => Scaffold(
              appBar: AppBar(title: Text(tr(file['name'] as String))),
              body: PdfView(controller: pdf),
            ),
          ),
        );
      } finally {
        pdf.dispose();
      }
    }
  }

  Future<void> remove(Api api, String? id, Map<String, dynamic> file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text(tr('Remove attachment?')),
        content: Text(tr(file['name'] as String)),
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
    if (confirmed != true || !mounted || id != owner) return;
    await api
        .request('DELETE', '/private-profile/files/${file['id']}')
        .timeout(const Duration(seconds: 15));
    if (mounted && id == owner)
      setState(
        () => files = files.where((r) => r['id'] != file['id']).toList(),
      );
  }

  @override
  Widget build(BuildContext context) {
    return AppFrame(
      back: true,
      title: tr('Personal details and documents'),
      subtitle: tr('Private to your Med.ai account.'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (busy) const LinearProgressIndicator(),
          if (error != null)
            Text(
              tr(error!),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          if (!ready && !busy)
            TextButton(
              onPressed: () => run(load),
              child: Text(tr('Load profile')),
            ),
          if (ready) ...[
            Tile(
              child: Form(
                key: form,
                child: Column(
                  children: [
                    for (final field in fields.entries) ...[
                      TextFormField(
                        controller: inputs[field.key],
                        enabled: !busy,
                        maxLength: field.key == 'medical_notes'
                            ? 1000
                            : field.key == 'address'
                            ? 240
                            : field.key == 'emergency_contact_phone'
                            ? 24
                            : field.key == 'birth_date'
                            ? 10
                            : 120,
                        maxLines: field.key == 'medical_notes' ? 3 : 1,
                        keyboardType: field.key == 'emergency_contact_phone'
                            ? TextInputType.phone
                            : TextInputType.text,
                        decoration: InputDecoration(labelText: tr(field.value)),
                      ),
                      gap(8),
                    ],
                    DropdownButtonFormField<String>(
                      initialValue: blood,
                      decoration: InputDecoration(
                        labelText: tr('Blood group (if known)'),
                      ),
                      items: [
                        for (final b in [
                          '',
                          'A+',
                          'A-',
                          'B+',
                          'B-',
                          'AB+',
                          'AB-',
                          'O+',
                          'O-',
                        ])
                          DropdownMenuItem(
                            value: b,
                            child: Text(tr(b.isEmpty ? 'Not recorded' : b)),
                          ),
                      ],
                      onChanged: busy
                          ? null
                          : (value) => setState(() => blood = value ?? ''),
                    ),
                  ],
                ),
              ),
            ),
            gap(10),
            ActionButton(
              tr('Save Details'),
              onTap: busy ? null : () => run(save),
            ),
            gap(20),
            Text(
              tr('Private documents'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(
              tr(
                'PDF, JPEG or PNG, up to 8 MB each. These files are not added to AI Chat.',
              ),
            ),
            gap(8),
            DropdownButtonFormField<String>(
              initialValue: category,
              decoration: InputDecoration(labelText: tr('Document category')),
              items: [
                DropdownMenuItem(value: 'medical', child: Text(tr('Medical'))),
                DropdownMenuItem(
                  value: 'identity',
                  child: Text(tr('Identity')),
                ),
                DropdownMenuItem(
                  value: 'insurance',
                  child: Text(tr('Insurance')),
                ),
                DropdownMenuItem(value: 'other', child: Text(tr('Other'))),
              ],
              onChanged: busy
                  ? null
                  : (value) => setState(() => category = value ?? 'medical'),
            ),
            gap(10),
            ActionButton(
              tr('Upload Document'),
              icon: Icons.upload_file,
              onTap: busy ? null : () => run(pick),
            ),
            for (final file in files)
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: Text(tr(file['name'] as String)),
                subtitle: Text(tr(file['category'] as String)),
                onTap: busy ? null : () => run((a, id) => view(a, id, file)),
                trailing: IconButton(
                  tooltip: tr('Remove attachment'),
                  icon: const Icon(Icons.delete_outline),
                  onPressed: busy
                      ? null
                      : () => run((a, id) => remove(a, id, file)),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
