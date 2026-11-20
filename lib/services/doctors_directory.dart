import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

class DoctorListing {
  DoctorListing(Map<String, dynamic> fields) : _fields = Map.unmodifiable(fields);
  final Map<String, dynamic> _fields;
  String field(String key) => (_fields[key]?.toString() ?? '').trim();
  String get id => '${field('doctor_id')}:${field('hospital_id')}';
  String get name => field('full_name');
  String get hospital => field('hospital_name');
  String get division => field('division');
  String get district => field('district');
  String get hours => field('visiting_hours');
  String get location => [district, if (district != division) division]
      .where((part) => part.isNotEmpty)
      .join(', ');
  List<String> get specialties => field('specialties').split('|')
      .map((part) => part.trim()).where((part) => part.isNotEmpty).toList();
  String get specialty => specialties.join(' · ');
  Uri? url(String key) {
    final uri = Uri.tryParse(field(key));
    return uri?.scheme == 'https' && uri!.host.isNotEmpty ? uri : null;
  }
  Uri? get phone {
    final digits = field('appointment_hotline').replaceAll(RegExp(r'[ ()-]'), '');
    return RegExp(r'^\+?\d{4,15}$').hasMatch(digits)
        ? Uri(scheme: 'tel', path: digits)
        : null;
  }
  bool matchesSpecialty(String selected) {
    const aliases = <String, Set<String>>{
      "internal medicine": {"internal medicine", "medicine"},
      "cardiology": {"cardiology", "interventional cardiology"},
      "neurology": {"neuro medicine", "neurology"},
      "orthopedics": {"orthopaedic surgery", "orthopaedics", "orthopedic surgery", "orthopedics"},
      "pulmonology": {"chest diseases", "pulmonology", "respiratory medicine"},
      "gastroenterology": {"gastroenterology", "gastrointestinal & liver diseases"},
      "dermatology": {"dermatology & venereology"},
      "ent": {"ent"},
      "pediatrics": {"newborn & child medicine", "pediatrics"},
      "endocrinology": {"endocrinology"},
      "nephrology": {"kidney diseases", "nephrology"},
      "urology": {"urology"},
      "gynecology": {"gynaecology & obstetrics", "obstetrics & gynecology"},
    };
    final normalized = selected.trim().toLowerCase();
    final options = aliases[normalized] ?? {normalized};
    return specialties.any((name) => options.contains(name.trim().toLowerCase()));
  }

  bool matches(String query, String? area, String? selectedSpecialty) =>
      (area == null || division == area) &&
      (selectedSpecialty == null || matchesSpecialty(selectedSpecialty)) &&
      query.trim().toLowerCase().split(RegExp(r'\s+')).every((word) =>
        [name, hospital, district, division, specialty].join(' ').toLowerCase().contains(word));
}

class DoctorsDirectory {
  static const _project = String.fromEnvironment('SUPABASE_URL');
  static const _key = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY');
  static bool get hasRemote => _project.isNotEmpty && _key.isNotEmpty;

  static List<DoctorListing> decode(String raw) {
    final rows = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    return rows.where((row) => row['hospital_id'] != null)
        .map(DoctorListing.new).toList()
        ..sort((a, b) {
          final result = a.name.toLowerCase().compareTo(b.name.toLowerCase());
          return result != 0 ? result : a.id.compareTo(b.id);
        });
  }

  static Future<List<DoctorListing>> bundled() async =>
      decode(await rootBundle.loadString('assets/doctors_directory.json'));

  static Future<List<DoctorListing>> remote() async {
    final project = Uri.parse(_project);
    if (project.scheme != 'https' || !project.host.endsWith('.supabase.co') ||
        !_key.startsWith('sb_publishable_')) {
      throw const FormatException('Use a Supabase project URL and publishable key.');
    }
    const fields = 'doctor_id,full_name,qualifications,designation,special_interests,'
        'bmdc_registration,profile_image_url,source_url,last_verified,is_verified,'
        'hospital_id,hospital_name,hospital_address,district,division,'
        'appointment_hotline,visiting_hours,consultation_fee_bdt,appointment_url,specialties';
    final client = http.Client();
    try {
      const pageSize = 100;
      final result = <DoctorListing>[];
      for (var page = 0; page < 50; page++) {
        final uri = project.replace(path: '/rest/v1/doctor_directory', queryParameters: {
          'select': fields,
          'hospital_id': 'not.is.null',
          'order': 'full_name.asc,doctor_id.asc,hospital_id.asc',
          'limit': '$pageSize',
          'offset': '${page * pageSize}',
        });
        final response = await client.get(uri, headers: {'apikey': _key})
            .timeout(const Duration(seconds: 8));
        if (response.statusCode != 200 && response.statusCode != 206) {
          throw StateError('Doctor directory returned HTTP ${response.statusCode}.');
        }
        final records = decode(utf8.decode(response.bodyBytes));
        result.addAll(records);
        if (records.length < pageSize) return result;
      }
      throw StateError('Directory is larger than the supported page count.');
    } finally {
      client.close();
    }
  }
}
