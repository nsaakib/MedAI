import '../localization.dart';

import 'package:flutter/material.dart';

import '../models.dart';
import '../design.dart';

Future<void> showBrandChoices(
  BuildContext context,
  AppState state,
  Medicine medicine,
) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => FractionallySizedBox(
      heightFactor: .72,
      child: _BrandChoices(state: state, medicine: medicine),
    ),
  );
}

class _BrandChoices extends StatefulWidget {
  const _BrandChoices({required this.state, required this.medicine});
  final AppState state;
  final Medicine medicine;

  @override
  State<_BrandChoices> createState() => _BrandChoicesState();
}

class _BrandChoicesState extends State<_BrandChoices> {
  late Future<dynamic> data;
  var saving = false;
  String? owner, failure;

  String get path =>
      '/medicine-brands/${Uri.encodeComponent(widget.medicine.id)}';

  @override
  void initState() {
    super.initState();
    owner = widget.state.userId;
    data = widget.state.api.request('GET', path);
  }

  Future<void> choose(String? id, String label) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(
          tr(
            id == null
                ? 'Clear preferred brand?'
                : 'Save $label as a preference?',
          ),
        ),
        content: Text(
          tr(
            'The prescription will remain unchanged. Ask a pharmacist to verify the exact product before buying or switching brands.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(tr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(tr('Confirm')),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true || owner != widget.state.userId) return;
    setState(() {
      saving = true;
      failure = null;
    });
    try {
      await widget.state.api.request('PUT', path, {
        'alternative_id': id,
        'confirmed': true,
      });
      if (mounted && owner == widget.state.userId) {
        setState(() => data = widget.state.api.request('GET', path));
      }
    } catch (_) {
      if (mounted)
        setState(
          () => failure = 'The preference was not saved. Check your connection and the current prescription.',
        );
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: FutureBuilder<dynamic>(
      future: data,
      builder: (_, snapshot) {
        if (owner != widget.state.userId)
          return Center(child: Text(tr('Sign in again to view your records.')));
        final m = widget.medicine;
        final root = snapshot.data;
        final items = root is Map ? root['candidates'] as List? ?? [] : [];
        final selected = root is Map ? root['preferred_id'] : null;
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              tr('Brand alternatives'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 10),
            Text(tr('Prescribed: ${m.name} ${m.strength} · ${m.form}')),
            Text(
              tr(
                'Compare ingredient, strength, dosage form and release type. Product listings do not confirm stock. Ask a pharmacist before switching.',
              ),
            ),
            if (snapshot.connectionState != ConnectionState.done || saving)
              const LinearProgressIndicator(),
            if (snapshot.hasError) ...[
              Text(
                tr(
                  'Alternatives are unavailable. Sync the prescription and try again.',
                ),
              ),
              TextButton(
                onPressed: () => setState(
                  () => data = widget.state.api.request('GET', path),
                ),
                child: Text(tr('Try again')),
              ),
            ],
            if (!m.verified)
              Text(
                tr(
                  'Review and save this medicine before choosing alternatives.',
                ),
              ),
            if (snapshot.hasData && m.verified && items.isEmpty)
              Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  tr(
                    'This brand, strength or dosage form is not yet supported. Check the saved spelling and strength. We will not guess an alternative.',
                  ),
                ),
              ),
            if (failure != null) Text(tr(failure!)),
            for (final raw in items.whereType<Map>())
              Tile(
                outlined: false,
                child: ListTile(
                  leading: Icon(
                    selected == raw['id']
                        ? Icons.check_circle
                        : Icons.medication_outlined,
                  ),
                  title: Text(tr('${raw['name']} · ${raw['strength']}')),
                  subtitle: Text(
                    tr(
                      "${raw['manufacturer']}\n${raw['ingredients']} · ${raw['form_label'] ?? raw['form']} · ${raw['release']} release",
                    ),
                  ),
                  trailing: FilledButton.tonal(
                    style: medicineActionStyle,
                    onPressed: saving || selected == raw['id']
                        ? null
                        : () => choose(
                            raw['id'] as String,
                            raw['name'] as String,
                          ),
                    child: Text(
                      tr(selected == raw['id'] ? 'Preferred' : 'Select'),
                    ),
                  ),
                ),
              ),
            if (selected != null)
              TextButton(
                onPressed: saving ? null : () => choose(null, ''),
                child: Text(tr('Clear preferred brand')),
              ),
          ],
        );
      },
    ),
  );
}
