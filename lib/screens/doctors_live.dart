import '../localization.dart';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../design.dart';
import '../services/doctors_directory.dart';

const _secondary = Color(0xff52658f);

class DoctorsLive extends StatefulWidget {
  const DoctorsLive({super.key, this.initialDivision, this.initialSpecialty});
  final String? initialDivision, initialSpecialty;

  @override
  State<DoctorsLive> createState() => _DoctorsLiveState();
}

class _DoctorsLiveState extends State<DoctorsLive> {
  List<DoctorListing>? listings;
  String query = '';
  String? division, specialty;
  bool unavailable = false;
  bool refreshFailed = false;

  @override
  void initState() {
    super.initState();
    final area = widget.initialDivision;
    final field = widget.initialSpecialty;
    division = area == null || area.isEmpty ? null : area;
    specialty = field == null || field.isEmpty ? null : field;
    load();
  }

  Future<void> load() async {
    try {
      final rows = await DoctorsDirectory.bundled();
      if (!mounted) return;
      setState(() {
        listings = rows;
        unavailable = false;
        refreshFailed = false;
      });
    } catch (_) {
      if (mounted) setState(() => unavailable = true);
    }
    if (!DoctorsDirectory.hasRemote || !mounted) return;
    try {
      final rows = await DoctorsDirectory.remote();
      if (rows.isEmpty) throw StateError('Directory has no imported records.');
      if (!mounted) return;
      setState(() {
        listings = rows;
        unavailable = false;
        refreshFailed = false;
      });
    } catch (_) {
      if (mounted) setState(() => refreshFailed = true);
    }
  }

  Future<void> chooseSpecialty(List<String> choices) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (c) => FractionallySizedBox(
        heightFactor: .65,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Heading(tr('Specialties')),
            ListTile(
              title: Text(tr('All specialties')),
              onTap: () => Navigator.pop(c, ''),
            ),
            for (final name in choices)
              ListTile(
                title: Text(tr(name)),
                selected: name == specialty,
                onTap: () => Navigator.pop(c, name),
              ),
          ],
        ),
      ),
    );
    if (mounted && choice != null) {
      setState(() => specialty = choice.isEmpty ? null : choice);
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = listings ?? const <DoctorListing>[];
    final divisions =
        rows.map((d) => d.division).where((s) => s.isNotEmpty).toSet().toList()
          ..sort();
    final specialties = rows.expand((d) => d.specialties).toSet().toList()
      ..sort();
    final matches = rows
        .where((d) => d.matches(query, division, specialty))
        .toList();
    return AppFrame(
      back: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            tr('Find a doctor'),
            style: TextStyle(
              fontSize: 29,
              color: navy,
              fontWeight: FontWeight.w800,
            ),
          ),
          const _Detail('Explore specialists and clinic hours.'),
          gap(14),
          _DoctorCard(
            padding: 0,
            child: TextField(
              onChanged: (value) => setState(() => query = value),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                hintText: tr('Search by doctor, specialty or clinic'),
                prefixIcon: Icon(Icons.search, color: blue),
              ),
            ),
          ),
          gap(8),
          Row(
            children: [
              Expanded(child: Heading(tr('Specialties'))),
              TextButton(
                onPressed: () => chooseSpecialty(specialties),
                child: Text(tr('See all →')),
              ),
            ],
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _specialty(
                'Cardiology',
                Icons.favorite_border,
                const Color(0xff2541bf),
              ),
              const SizedBox(width: 8),
              _specialty(
                'Internal Medicine',
                Icons.add,
                const Color(0xff3451ca),
              ),
              const SizedBox(width: 8),
              _specialty(
                'Neurology',
                Icons.auto_awesome_outlined,
                const Color(0xff5041c2),
              ),
            ],
          ),
          if (specialty != null)
            Align(
              alignment: Alignment.centerLeft,
              child: InputChip(
                label: Text(tr(specialty!)),
                onDeleted: () => setState(() => specialty = null),
              ),
            ),
          gap(10),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                tr('Matching doctors'),
                style: TextStyle(
                  color: navy,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              PopupMenuButton<String>(
                tooltip: tr('Filter by division'),
                onSelected: (area) =>
                    setState(() => division = area.isEmpty ? null : area),
                itemBuilder: (_) => [
                  PopupMenuItem(value: '', child: Text(tr('All divisions'))),
                  for (final area in divisions)
                    PopupMenuItem(value: area, child: Text(tr(area))),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 12,
                    horizontal: 4,
                  ),
                  child: Text(
                    tr('${division ?? 'All divisions'} ▾'),
                    style: const TextStyle(color: blue),
                  ),
                ),
              ),
            ],
          ),
          if (refreshFailed && listings != null)
            const _Detail(
              'Live directory unavailable. Showing bundled listings.',
            ),
          if (listings == null && !unavailable)
            const Center(child: CircularProgressIndicator())
          else if (listings == null)
            _DoctorCard(
              child: TextButton(
                onPressed: load,
                child: Text(tr('Directory unavailable. Retry')),
              ),
            )
          else if (matches.isEmpty)
            const _DoctorCard(
              child: _Detail(
                'No matching doctors. Try a different search or filter.',
              ),
            )
          else ...[
            for (final doctor in matches)
              _DoctorCard(
                key: ValueKey(doctor.id),
                padding: 10,
                onTap: () => go(context, 'doctor-profile', arguments: doctor),
                child: Row(
                  children: [
                    _Portrait(doctor, width: 64, height: 64),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tr(doctor.name),
                            style: const TextStyle(
                              color: navy,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          _Detail(
                            '${doctor.specialty} · ${doctor.hospital}',
                            maxLines: 2,
                          ),
                          Text(
                            tr(
                              doctor.hours.isEmpty
                                  ? 'Hours not listed'
                                  : doctor.hours,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xff087160),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const DecoratedBox(
                      decoration: BoxDecoration(
                        color: navy,
                        borderRadius: BorderRadius.all(Radius.circular(10)),
                      ),
                      child: Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(
                          Icons.arrow_forward,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _specialty(String label, IconData icon, Color color) {
    final selected = specialty == label;
    return Expanded(
      child: Semantics(
        selected: selected,
        child: Material(
          color: color,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => setState(() => specialty = selected ? null : label),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 5),
              child: Column(
                children: [
                  Icon(
                    selected ? Icons.check_circle_outline : icon,
                    color: Colors.white,
                  ),
                  gap(6),
                  Text(
                    tr(label),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class DoctorProfileLive extends StatelessWidget {
  const DoctorProfileLive({super.key, required this.doctor});
  final DoctorListing doctor;

  @override
  Widget build(BuildContext context) => AppFrame(
    title: tr('Doctor profile'),
    brand: false,
    back: true,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Portrait(doctor, height: 246, width: double.infinity),
        gap(12),
        Text(
          tr(doctor.name),
          style: const TextStyle(
            fontSize: 27,
            color: navy,
            fontWeight: FontWeight.w800,
          ),
        ),
        _Detail('${doctor.specialty} · ${doctor.location}'),
        gap(12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _tag(
              'Specialty',
              doctor.specialty,
              const Color(0xffeef0ff),
              const Color(0xff4335a4),
            ),
            _tag(
              'Chamber',
              doctor.hospital,
              const Color(0xffeaf4ff),
              const Color(0xff18518f),
            ),
            _tag(
              'Location',
              doctor.location,
              const Color(0xffe6f8f3),
              const Color(0xff096453),
            ),
          ],
        ),
        gap(12),
        _chamber(doctor),
        _section('About the doctor', [
          doctor.field('designation'),
          doctor.field('qualifications'),
          doctor.field('special_interests'),
        ]),
        _section(
          'Listing source',
          [
            if (doctor.field('last_verified').isNotEmpty)
              'Source last checked: ${doctor.field('last_verified')}',
            if (doctor.field('bmdc_registration').isNotEmpty)
              'BMDC registration listed: ${doctor.field('bmdc_registration')}'
            else
              'BMDC registration not listed.',
          ],
          action: doctor.url('source_url') == null
              ? null
              : TextButton(
                  onPressed: () => _open(context, doctor.url('source_url')!),
                  child: Text(tr('Open listing source')),
                ),
        ),
        _primary(
          'View appointment information',
          () => go(context, 'doctor-appointment', arguments: doctor),
        ),
      ],
    ),
  );
}

class DoctorAppointmentLive extends StatelessWidget {
  const DoctorAppointmentLive({super.key, required this.doctor});
  final DoctorListing doctor;

  @override
  Widget build(BuildContext context) => AppFrame(
    title: tr('Appointment'),
    brand: false,
    back: true,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Portrait(doctor, height: 170, width: double.infinity),
        gap(14),
        _section(doctor.name, ['${doctor.specialty} · ${doctor.hospital}']),
        Heading(tr('Clinic schedule')),
        _chamber(doctor),
        _section('Confirm with the clinic', [
          'This directory does not show live availability or reserve appointments. Contact the clinic to confirm a date and time.',
          if (doctor.phone == null && doctor.url('appointment_url') == null)
            'No appointment contact is listed for this chamber.',
        ]),
        if (doctor.phone != null)
          _primary(
            'Call clinic · ${doctor.field('appointment_hotline')}',
            () => _open(context, doctor.phone!),
          ),
        if (doctor.url('appointment_url') case final url?)
          TextButton(
            onPressed: () => _open(context, url),
            child: Text(tr('Open clinic appointment page')),
          ),
        if (doctor.url('source_url') case final url?)
          TextButton(
            onPressed: () => _open(context, url),
            child: Text(tr('View clinic listing')),
          ),
      ],
    ),
  );
}

Widget _primary(String label, VoidCallback action) => FilledButton(
  style: FilledButton.styleFrom(
    backgroundColor: blue,
    foregroundColor: Colors.white,
    minimumSize: const Size.fromHeight(46),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
  ),
  onPressed: action,
  child: Text(tr(label), textAlign: TextAlign.center),
);

const _cardShadow = [
  BoxShadow(color: Color(0x14183469), blurRadius: 18, offset: Offset(0, 6)),
  BoxShadow(color: Color(0x0c183469), blurRadius: 5, offset: Offset(0, 2)),
];

class _DoctorCard extends StatelessWidget {
  const _DoctorCard({
    super.key,
    required this.child,
    this.padding = 14,
    this.onTap,
  });
  final Widget child;
  final double padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    const radius = BorderRadius.all(Radius.circular(16));
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          borderRadius: radius,
          boxShadow: _cardShadow,
        ),
        child: Material(
          color: Colors.white,
          borderRadius: radius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(padding: EdgeInsets.all(padding), child: child),
          ),
        ),
      ),
    );
  }
}

Widget _tag(String label, String value, Color fill, Color foreground) =>
    Container(
      constraints: const BoxConstraints(maxWidth: 320),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(12),
        boxShadow: _cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr(label),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: foreground,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            tr(value),
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: foreground,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );

Widget _chamber(DoctorListing doctor) => _section('Chamber & hours', [
  doctor.hospital,
  doctor.field('hospital_address'),
  doctor.hours.isEmpty
      ? 'Hours not listed. Call the clinic to confirm.'
      : doctor.hours,
  if (doctor.field('consultation_fee_bdt').isNotEmpty)
    'Listed consultation fee: ৳${doctor.field('consultation_fee_bdt')}',
]);

Widget _section(String title, List<String> lines, {Widget? action}) =>
    _DoctorCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            tr(title),
            style: const TextStyle(color: navy, fontWeight: FontWeight.w800),
          ),
          for (final line in lines.where((s) => s.isNotEmpty)) ...[
            gap(4),
            _Detail(line),
          ],
          if (action != null)
            Align(alignment: Alignment.centerLeft, child: action),
        ],
      ),
    );

class _Detail extends StatelessWidget {
  const _Detail(this.text, {this.maxLines});
  final String text;
  final int? maxLines;
  @override
  Widget build(BuildContext context) => Text(
    tr(text),
    maxLines: maxLines,
    overflow: maxLines == null ? null : TextOverflow.ellipsis,
    style: const TextStyle(fontSize: 13, color: _secondary),
  );
}

class _Portrait extends StatelessWidget {
  const _Portrait(this.doctor, {required this.width, required this.height});
  final DoctorListing doctor;
  final double width, height;

  @override
  Widget build(BuildContext context) {
    final url = doctor.url('profile_image_url');
    const illustrations = ['1c241', 'a7274', '03013'];
    final illustration =
        illustrations[doctor.id.codeUnits.fold<int>(
              0,
              (sum, unit) => sum + unit,
            ) %
            illustrations.length];
    final fallback = Image.asset(
      'assets/doctor_illustration_$illustration.png',
      fit: BoxFit.cover,
      alignment: const Alignment(0, -.55),
      semanticLabel: 'Illustration, not a photo of this doctor',
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(height <= 64 ? 12 : 18),
      child: Container(
        width: width,
        height: height,
        color: const Color(0xffdfe9ff),
        child: url == null
            ? fallback
            : Image.network(
                url.toString(),
                fit: BoxFit.cover,
                alignment: const Alignment(0, -.55),
                errorBuilder: (_, _, _) => fallback,
                frameBuilder: (_, child, frame, synchronous) =>
                    synchronous || frame != null ? child : fallback,
              ),
      ),
    );
  }
}

Future<void> _open(BuildContext context, Uri uri) async {
  try {
    if (await launchUrl(uri, mode: LaunchMode.externalApplication)) return;
  } catch (_) {
    // The platform may have no app registered for this link.
  }
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          tr(
            uri.scheme == 'tel'
                ? 'Could not open the dialer. Clinic number: ${uri.path}'
                : 'Could not open the clinic link.',
          ),
        ),
      ),
    );
  }
}
