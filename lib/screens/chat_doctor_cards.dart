import '../localization.dart';

import 'package:flutter/material.dart';

import '../design.dart';
import '../services/doctors_directory.dart';

/// Use the same repository as Doctors. No symptom, report or profile data is
/// sent to the directory; its existing public lookup reads only doctor records.
class ChatDoctorCards extends StatefulWidget {
  const ChatDoctorCards({
    super.key,
    required this.turn,
    required this.fallback,
  });
  final Map<String, dynamic> turn;
  final List<Map<String, dynamic>> fallback;

  @override
  State<ChatDoctorCards> createState() => _ChatDoctorCardsState();
}

class _ChatDoctorCardsState extends State<ChatDoctorCards> {
  static Future<List<DoctorListing>?>? _remote;
  static DateTime? _loadedAt;

  late final Future<List<DoctorListing>?> _directory = _liveDirectory();

  static Future<List<DoctorListing>?> _liveDirectory() {
    if (!DoctorsDirectory.hasRemote) return Future.value(null);
    if (_loadedAt == null ||
        DateTime.now().difference(_loadedAt!) > const Duration(minutes: 5)) {
      _loadedAt = DateTime.now();
      _remote = DoctorsDirectory.remote()
          .timeout(const Duration(seconds: 9))
          .then<List<DoctorListing>?>((rows) => rows.isEmpty ? null : rows)
          .catchError((Object _) => null);
    }
    return _remote!;
  }

  static const aliases = [
    ['internal medicine', 'medicine', 'general medicine'],
    ['cardiology', 'interventional cardiology'],
    ['dermatology', 'dermatology & venereology'],
    ['neurology', 'neuro medicine'],
    [
      'orthopedics',
      'orthopaedics',
      'orthopedic surgery',
      'orthopaedic surgery',
    ],
    ['respiratory medicine', 'pulmonology', 'chest diseases'],
  ];

  String _name(String text) =>
      text.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

  List<DoctorListing> _matches(
    List<DoctorListing> rows,
    String specialty,
    String division,
  ) {
    final wanted = _name(specialty);
    final eligible = aliases.firstWhere(
      (g) => g.contains(wanted),
      orElse: () => [wanted],
    );
    final found = rows
        .where(
          (r) =>
              (division.isEmpty || _name(r.division) == _name(division)) &&
              r.specialties.any((s) => eligible.contains(_name(s))),
        )
        .toList();
    found.sort((a, b) {
      final primary =
          (b.field('is_verified') == 'true' ? 1 : 0) -
          (a.field('is_verified') == 'true' ? 1 : 0);
      return primary == 0 ? a.name.compareTo(b.name) : primary;
    });
    final ids = <String>{};
    return found.where((r) => ids.add(r.id)).take(5).toList();
  }

  Future<void> _profile(DoctorListing row, {required bool snapshot}) async {
    if (!snapshot) {
      go(context, 'doctor-profile', arguments: row);
      return;
    }
    try {
      final local = await DoctorsDirectory.bundled();
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
      for (final r in local) {
        if (r.id == row.id ||
            (r.field('doctor_id') == row.field('doctor_id') &&
                r.hospital == row.hospital)) {
          go(context, 'doctor-profile', arguments: r);
          return;
        }
      }
    } catch (_) {
      if (!mounted) return;
    }
    if (mounted && ModalRoute.of(context)?.isCurrent == true) {
      go(context, 'doctor-profile', arguments: row);
    }
  }

  @override
  Widget build(BuildContext context) {
    final specialty = widget.turn['specialty'] as String? ?? '';
    final division = widget.turn['division'] as String? ?? '';
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: FutureBuilder<List<DoctorListing>?>(
        future: _directory,
        builder: (c, state) {
          final fetching =
              DoctorsDirectory.hasRemote &&
              state.connectionState != ConnectionState.done;
          final useSnapshot = state.data == null || specialty.isEmpty;
          final doctors = useSnapshot
              ? widget.fallback.map(DoctorListing.new).toList()
              : _matches(state.data!, specialty, division);
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr('Matching doctors'),
                style: TextStyle(color: navy, fontWeight: FontWeight.w800),
              ),
              if (specialty.isNotEmpty)
                Text(
                  tr(
                    [specialty, if (division.isNotEmpty) division].join(' · '),
                  ),
                ),
              if (fetching && doctors.isEmpty)
                Text(tr('Checking the doctor directory…'))
              else if (doctors.isEmpty)
                Text(
                  tr(
                    'No listed doctors match this specialty and division. You can widen the search.',
                  ),
                ),
              for (final doctor in doctors)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: const Icon(
                    Icons.medical_services_outlined,
                    color: blue,
                  ),
                  title: Text(tr(doctor.name)),
                  subtitle: Text(
                    tr(
                      [
                        doctor.hospital,
                        doctor.division,
                      ].where((p) => p.isNotEmpty).join(' · '),
                    ),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _profile(doctor, snapshot: useSnapshot),
                ),
              if (doctors.isNotEmpty)
                Text(
                  tr(
                    'Directory listings do not confirm appointment availability.',
                  ),
                ),
              TextButton.icon(
                onPressed: () => go(
                  c,
                  'doctors',
                  arguments: {'specialty': specialty, 'division': division},
                ),
                icon: const Icon(Icons.search),
                label: Text(tr('Browse doctor directory')),
              ),
            ],
          );
        },
      ),
    );
  }
}
