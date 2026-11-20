import '../localization.dart';

import 'package:flutter/material.dart';

import '../design.dart';
import '../services/doctors_directory.dart';

/// Render directory records, not names generated in the assistant's prose.
class ChatDoctorList extends StatelessWidget {
  const ChatDoctorList({super.key, required this.turn});
  final Map<String, dynamic> turn;

  @override
  Widget build(BuildContext context) {
    final triage = turn['triage'];
    final status = triage is Map ? triage['level'] : turn['referral_status'];
    final rows = turn['doctors'];
    if ((status != null && status != 'routine' && status != 'clarify') ||
        rows is! List) {
      return const SizedBox.shrink();
    }
    final doctors = rows
        .whereType<Map>()
        .map((row) => DoctorListing(Map<String, dynamic>.from(row)))
        .where((d) => d.name.isNotEmpty && d.field('doctor_id').isNotEmpty)
        .toList();
    if (doctors.isEmpty) return const SizedBox.shrink();
    final bn = turn['language'] == 'bn';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tr(bn ? 'ডাক্তারদের তালিকা' : 'Matching doctors'),
          style: const TextStyle(fontWeight: FontWeight.w800, color: navy),
        ),
        for (final doctor in doctors)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.medical_services_outlined, color: blue),
            title: Text(tr(doctor.name)),
            subtitle: Text(
              tr(
                [
                  doctor.specialty,
                  doctor.hospital,
                  doctor.division,
                ].where((part) => part.isNotEmpty).join(' · '),
              ),
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => openDoctor(context, doctor),
          ),
        TextButton.icon(
          icon: const Icon(Icons.search),
          label: Text(tr(bn ? 'আরও ডাক্তার খুঁজুন' : 'Find matching doctors')),
          onPressed: () => go(
            context,
            'doctors',
            arguments: {
              'specialty': turn['specialty'] ?? '',
              'division': turn['division'] ?? '',
            },
          ),
        ),
      ],
    );
  }

  Future<void> openDoctor(BuildContext context, DoctorListing doctor) async {
    DoctorListing? profile;
    try {
      final local = await DoctorsDirectory.bundled();
      for (final entry in local) {
        if (entry.field('doctor_id') == doctor.field('doctor_id') &&
            entry.hospital == doctor.hospital) {
          profile = entry;
          break;
        }
      }
    } catch (_) {
      // The authenticated reply has a directory row usable as a fallback.
    }
    if (context.mounted && ModalRoute.of(context)?.isCurrent == true) {
      go(context, 'doctor-profile', arguments: profile ?? doctor);
    }
  }
}
