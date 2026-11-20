import '../localization.dart';

import 'package:flutter/material.dart';

import 'dart:convert';

import 'package:flutter/services.dart';

import '../design.dart';
import 'sos_live.dart';
import 'health_dashboard.dart';
import '../models.dart';
import 'schedule_home.dart';

class SyncStatus extends StatelessWidget {
  const SyncStatus({super.key});
  @override
  Widget build(BuildContext c) {
    final s = Scope.of(c);
    return Tile(
      color: s.conflict ? const Color(0xFFFFF7E8) : soft,
      padding: 12,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                s.syncing
                    ? Icons.sync
                    : s.pendingEvent != null || s.uploads.isNotEmpty
                    ? Icons.cloud_upload_outlined
                    : Icons.cloud_done_outlined,
                color: blue,
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: small(
                  tr(
                    s.conflict
                        ? 'Sync conflict needs your review'
                        : s.syncing
                        ? 'Syncing securely…'
                        : s.error ??
                              (s.pendingEvent != null || s.uploads.isNotEmpty
                                  ? 'Changes saved locally · waiting to sync'
                                  : 'All changes synced'),
                  ),
                ),
              ),
              IconButton(
                tooltip: tr('Sync now'),
                onPressed: s.syncing ? null : () => s.sync(),
                icon: const Icon(Icons.refresh, color: blue, size: 19),
              ),
            ],
          ),
          if (s.needsSignIn)
            TextButton(
              onPressed: () => go(c, 'login'),
              child: Text(tr('Sign in again')),
            ),
          if (s.conflict)
            TextButton(
              onPressed: () => showDialog<void>(
                context: c,
                builder: (d) => AlertDialog(
                  title: Text(tr('Reload the server record?')),
                  content: Text(
                    tr(
                      'This replaces unsynced profile, medicine and measurement edits on this device with the server version. Copy any changes you need before continuing. Uploaded documents are kept.',
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(d),
                      child: Text(tr('Keep local data')),
                    ),
                    TextButton(
                      onPressed: () async {
                        Navigator.pop(d);
                        try {
                          await s.reloadServer();
                        } catch (e) {
                          if (c.mounted)
                            message(
                              c,
                              tr('Could not reload'),
                              tr(e.toString()),
                            );
                        }
                      },
                      child: Text(tr('Reload server record')),
                    ),
                  ],
                ),
              ),
              child: Text(tr('Resolve conflict')),
            ),
        ],
      ),
    );
  }
}

class HomeLive extends StatelessWidget {
  const HomeLive({super.key});

  @override
  Widget build(BuildContext c) {
    final s = Scope.of(c);
    return AppFrame(
      title: tr(s.name.isEmpty ? 'Your Health' : 'Hello, ${s.name}'),
      subtitle: tr('Your medication plan and daily schedule.'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (s.syncing ||
              s.conflict ||
              s.error != null ||
              s.pendingEvent != null)
            const SyncStatus(),

          const MedicineHomeSections(),
          // Ambulance service is the final Home section.
          const EmergencySosEntry(),
        ],
      ),
    );
  }
}

class ProfileLive extends StatefulWidget {
  const ProfileLive({super.key});
  @override
  State<ProfileLive> createState() => _ProfileLiveState();
}

class _ProfileLiveState extends State<ProfileLive> {
  final form = GlobalKey<FormState>();
  bool busy = false;
  String? name, phone, allergies;
  @override
  Widget build(BuildContext c) {
    final s = Scope.of(c);
    return AppFrame(
      title: tr('Your Profile'),
      subtitle: tr('Keep your care information up to date.'),
      tab: 4,
      child: Form(
        key: form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SyncStatus(),
            Tile(
              outlined: false,
              child: DropdownButtonFormField<String>(
                initialValue: UiLanguage.locale.value.languageCode,
                key: ValueKey(UiLanguage.locale.value.languageCode),
                decoration: InputDecoration(labelText: tr('App language')),
                items: [
                  DropdownMenuItem(value: 'en', child: Text(tr('English'))),
                  DropdownMenuItem(value: 'bn', child: Text(tr('বাংলা'))),
                ],
                onChanged: (code) async {
                  if (code == null) return;
                  try {
                    await s.setLanguage(code);
                  } catch (_) {
                    if (c.mounted)
                      message(
                        c,
                        tr('Could not save'),
                        tr('Check available storage and try again.'),
                      );
                  }
                },
              ),
            ),
            Tile(
              child: Column(
                children: [
                  const Bubble(Icons.person_outline, size: 60),
                  gap(18),
                  TextFormField(
                    initialValue: s.name,
                    decoration: InputDecoration(labelText: tr('Full name')),
                    onSaved: (v) => name = v,
                    validator: (v) =>
                        tr(v == null || v.trim().isEmpty ? 'Required' : null),
                  ),
                  gap(12),
                  TextFormField(
                    initialValue: s.phone,
                    decoration: InputDecoration(labelText: tr('Phone')),
                    onSaved: (v) => phone = v,
                  ),
                  gap(12),
                  TextFormField(
                    initialValue: s.allergies,
                    decoration: InputDecoration(
                      labelText: tr(
                        'Known allergies (leave blank if not recorded)',
                      ),
                    ),
                    onSaved: (v) => allergies = v,
                    maxLines: 3,
                  ),
                  gap(12),
                  small(tr(s.email)),
                ],
              ),
            ),
            ActionButton(
              tr('Save Profile'),
              onTap: busy
                  ? null
                  : () async {
                      if (!form.currentState!.validate()) return;
                      form.currentState!.save();
                      setState(() => busy = true);
                      s.name = name!.trim();
                      s.phone = phone ?? '';
                      s.allergies = allergies ?? '';
                      try {
                        await s.commit();
                        if (c.mounted)
                          message(
                            c,
                            tr('Profile saved'),
                            tr(
                              'Saved encrypted on this device and queued for sync.',
                            ),
                          );
                      } catch (e) {
                        if (c.mounted)
                          message(c, tr('Could not save'), tr(e.toString()));
                      } finally {
                        if (mounted) setState(() => busy = false);
                      }
                    },
            ),
            gap(14),
            rowTile(
              Icons.folder_shared_outlined,
              tr('Personal details and documents'),
              tr('Emergency contact, blood group and private uploads.'),
              () => go(c, 'private-profile'),
            ),
            rowTile(
              Icons.people_outline,
              tr('Care Team Requests'),
              tr('Review your submitted cases and responses.'),
              () => go(c, 'cases'),
            ),
            rowTile(
              Icons.download_outlined,
              tr('Export Local Record'),
              tr('Copy a JSON export to your clipboard.'),
              () async {
                await Clipboard.setData(
                  ClipboardData(text: jsonEncode(s.snapshot)),
                );
                if (c.mounted)
                  message(
                    c,
                    tr('Copied'),
                    tr(
                      'Your record was copied to the device clipboard. Paste it only into a location you trust.',
                    ),
                  );
              },
            ),
            gap(15),
            TextButton(
              onPressed: () => showDialog<void>(
                context: c,
                builder: (d) => AlertDialog(
                  title: Text(tr('Sign out?')),
                  content: Text(
                    tr(
                      s.pendingEvent != null || s.uploads.isNotEmpty
                          ? 'Some changes have not synced. They stay encrypted on this device and can sync when you sign in again.'
                          : 'Your encrypted local record is retained for your next sign-in.',
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(d),
                      child: Text(tr('Cancel')),
                    ),
                    TextButton(
                      onPressed: () async {
                        Navigator.pop(d);
                        try {
                          await s.logout();
                          if (c.mounted)
                            Navigator.of(
                              c,
                            ).pushNamedAndRemoveUntil('/welcome', (_) => false);
                        } catch (e) {
                          if (c.mounted)
                            message(
                              c,
                              tr('Could not sign out'),
                              tr(e.toString()),
                            );
                        }
                      },
                      child: Text(tr('Sign out')),
                    ),
                  ],
                ),
              ),
              child: Text(tr('Sign out')),
            ),
          ],
        ),
      ),
    );
  }
}

class ServiceStatusLive extends StatelessWidget {
  const ServiceStatusLive({super.key});
  @override
  Widget build(BuildContext c) => AppFrame(
    back: true,
    title: tr('Connected Services'),
    subtitle: tr('Available care features'),
    child: Column(
      children: [
        rowTile(
          Icons.description_outlined,
          tr('Document review'),
          tr('Capture an image and enter verified medicine details.'),
          () => go(c, 'add'),
        ),
        rowTile(
          Icons.monitor_heart_outlined,
          tr('Health measurements'),
          tr('Record readings from your own measurement devices.'),
          () => go(c, 'health'),
        ),
        rowTile(
          Icons.people_outline,
          tr('Request a clinician review'),
          tr('Share selected records with your care team.'),
          () => go(c, 'handoff'),
        ),
        note(
          tr(
            'Use AI Chat to find relevant doctors or ask about your saved records. This app does not diagnose or monitor emergencies.',
          ),
          color: blue,
        ),
      ],
    ),
  );
}
