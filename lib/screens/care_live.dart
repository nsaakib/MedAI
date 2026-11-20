import '../localization.dart';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../design.dart';
import '../motion.dart';
import '../models.dart';
import 'workspace.dart';

class CareLive extends StatefulWidget {
  const CareLive({super.key});
  @override
  State<CareLive> createState() => _CareLiveState();
}

class _CareLiveState extends State<CareLive> {
  String area = '';
  @override
  Widget build(BuildContext c) => AppFrame(
    back: true,
    title: tr('Find Care Near You'),
    subtitle: tr('Explore pharmacies and clinics in Google Maps.'),
    child: Column(
      children: [
        rowTile(
          Icons.medical_services_outlined,
          tr('Find a doctor'),
          tr('Search doctors by specialty, clinic or division.'),
          () => go(c, 'doctors'),
        ),
        Tile(
          child: Column(
            children: [
              const Bubble(Icons.location_on_outlined, size: 55),
              gap(16),
              TextField(
                onChanged: (v) => area = v,
                decoration: InputDecoration(
                  labelText: tr('Area or city (optional)'),
                  hintText: tr('Dhanmondi, Dhaka'),
                ),
              ),
              gap(18),
              ActionButton(
                tr('Find Nearby Pharmacies'),
                icon: Icons.open_in_new,
                onTap: () => open(c, 'pharmacy'),
              ),
              gap(12),
              ActionButton(
                tr('Find Clinics and Hospitals'),
                icon: Icons.local_hospital_outlined,
                onTap: () => open(c, 'hospital'),
              ),
            ],
          ),
        ),
        small(
          tr(
            'Search opens in Google Maps. Contact a pharmacy directly to confirm medicine stock and current prices.',
          ),
        ),
        gap(18),
        rowTile(
          Icons.people_outline,
          tr('Request a Care Team Review'),
          tr('Share your saved records with the configured care team.'),
          () => go(c, 'handoff'),
        ),
      ],
    ),
  );
  Future<void> open(BuildContext c, String kind) async {
    final query = area.trim().isEmpty
        ? '$kind near me'
        : '$kind in ${area.trim()}';
    try {
      if (!await launchUrl(
            Uri.https('www.google.com', '/maps/search/', {
              'api': '1',
              'query': query,
            }),
            mode: LaunchMode.externalApplication,
          ) &&
          c.mounted)
        message(
          c,
          tr('Could not open Maps'),
          tr('Check that a browser or Google Maps is available.'),
        );
    } catch (e) {
      if (c.mounted) message(c, tr('Could not open Maps'), tr(e.toString()));
    }
  }
}

class ReviewRequestLive extends StatefulWidget {
  const ReviewRequestLive({super.key});
  @override
  State<ReviewRequestLive> createState() => _ReviewRequestLiveState();
}

class _ReviewRequestLiveState extends State<ReviewRequestLive> {
  final form = GlobalKey<FormState>();
  final selected = <String>{};
  String reason = '';
  bool consent = false, busy = false;
  @override
  Widget build(BuildContext c) {
    final s = Scope.of(c);
    return AppFrame(
      back: true,
      title: tr('Request a Care Review'),
      subtitle: tr(
        'A member of your configured care team will review your request.',
      ),
      child: Form(
        key: form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SyncStatus(),
            note(
              tr(
                'This queue is not an emergency service and may not be monitored continuously. Do not wait here for urgent help.',
              ),
            ),
            TextFormField(
              maxLines: 5,
              maxLength: 4000,
              decoration: InputDecoration(
                labelText: tr('What would you like reviewed?'),
              ),
              onSaved: (v) => reason = v!.trim(),
              validator: (v) => tr(v == null || v.trim().length < 5
                  ? 'Describe your request'
                  : null),
            ),
            Heading(tr('Choose Documents to Share')),
            for (final d in s.documents.where((d) => d['uploaded'] == true))
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  tr('${d['kind']} · ${(d['id'] as String).substring(0, 8)}'),
                  style: const TextStyle(fontSize: 12),
                ),
                value: selected.contains(d['id']),
                onChanged: (v) => setState(() {
                  if (v == true) {
                    selected.add(d['id']);
                  } else {
                    selected.remove(d['id']);
                  }
                }),
              ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: consent,
              onChanged: (v) => setState(() => consent = v ?? false),
              title: Text(
                tr(
                  'I agree to share my saved profile, medicines, measurements, dose logs and selected documents with clinicians in this Med.ai care team.',
                ),
                style: TextStyle(fontSize: 11, height: 1.5),
              ),
            ),
            gap(15),
            ActionButton(
              tr(busy ? 'Submitting…' : 'Submit Review Request'),
              icon: Icons.send_outlined,
              onTap: busy || !consent ? null : submit,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> submit() async {
    if (!form.currentState!.validate()) return;
    form.currentState!.save();
    setState(() => busy = true);
    try {
      await Scope.of(context).submitCase(reason, selected.toList());
      if (mounted) Navigator.pushReplacementNamed(context, '/cases');
    } catch (e) {
      if (mounted)
        message(context, tr('Request not submitted'), tr(e.toString()));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}

class CasesLive extends StatefulWidget {
  const CasesLive({super.key});
  @override
  State<CasesLive> createState() => _CasesLiveState();
}

class _CasesLiveState extends State<CasesLive> {
  Future<List<dynamic>>? cases;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    cases ??= load();
  }

  Future<List<dynamic>> load() async =>
      await Scope.of(context).api.request('GET', '/cases') as List<dynamic>;
  Future<void> withdraw(BuildContext c, String id) async {
    final state = Scope.of(c);
    final accepted = await showDialog<bool>(
      context: c,
      builder: (d) => AlertDialog(
        title: Text(tr('Withdraw sharing?')),
        content: Text(
          tr(
            'This stops future care-team access to this request. Images shared in another active request remain accessible. Copies already viewed or downloaded cannot be recalled.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: Text(tr('Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(d, true),
            child: Text(tr('Withdraw')),
          ),
        ],
      ),
    );
    if (accepted != true) return;
    try {
      await state.api.request('POST', '/cases/$id/withdraw');
      if (mounted) setState(() => cases = load());
    } catch (e) {
      if (c.mounted) message(c, tr('Could not withdraw'), tr(e.toString()));
    }
  }

  @override
  Widget build(BuildContext c) => AppFrame(
    back: true,
    title: tr('Care Team Updates'),
    subtitle: tr('Submitted requests and documented responses.'),
    child: Column(
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => setState(() => cases = load()),
            icon: const Icon(Icons.refresh, size: 18),
            label: Text(tr('Refresh')),
          ),
        ),
        FutureBuilder<List<dynamic>>(
          future: cases,
          builder: (c, s) {
            if (s.hasError)
              return note(
                tr('Could not load care-team updates. Connect and refresh.'),
                color: blue,
              );
            if (!s.hasData)
              return const Center(child: MedLoader(label: 'Loading…'));
            if (s.data!.isEmpty)
              return note(tr('No review requests yet.'), color: blue);
            return Column(
              children: [
                for (final item in s.data!)
                  Tile(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Pill(
                          tr(item['status']),
                          color: item['status'] == 'completed' ? mint : blue,
                        ),
                        gap(12),
                        Text(
                          tr(item['reason']),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        gap(9),
                        small(
                          tr(
                            'Submitted ${DateTime.fromMillisecondsSinceEpoch((item['created'] as int) * 1000).toLocal()}',
                          ),
                        ),
                        if (item['status'] != 'withdrawn')
                          TextButton(
                            onPressed: () => withdraw(c, item['id']),
                            child: Text(
                              tr('Withdraw sharing'),
                              style: TextStyle(fontSize: 11),
                            ),
                          ),
                        for (final note in item['notes'])
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Tile(
                              color: soft,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    tr(note['text']),
                                    style: const TextStyle(
                                      fontSize: 12,
                                      height: 1.6,
                                    ),
                                  ),
                                  gap(7),
                                  small(
                                    tr(
                                      '${note['status']} · ${DateTime.fromMillisecondsSinceEpoch((note['created'] as int) * 1000).toLocal()}',
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    ),
  );
}
