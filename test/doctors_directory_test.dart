import 'package:flutter_test/flutter_test.dart';

import '../lib/services/doctors_directory.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('bundled directory covers three divisions with usable chamber links', () async {
    final rows = await DoctorsDirectory.bundled();
    expect(rows.map((r) => r.id).toSet().length, 51);
    expect(rows.where((r) => r.division == 'Dhaka').length, 31);
    expect(rows.where((r) => r.division == 'Rajshahi').length, 10);
    expect(rows.where((r) => r.division == 'Barishal').length, 10);
    expect(rows.every((r) => r.phone?.scheme == 'tel'), isTrue);
    expect(rows.every((r) => r.hours.isEmpty), isTrue);
  });

  test('search combines name, clinic, division and specialty filters', () async {
    final row = (await DoctorsDirectory.bundled()).first;
    final terms = '${row.name.split(' ').last} ${row.hospital.split(' ').first}';
    expect(row.matches(terms.toUpperCase(), row.division, row.specialties.first), isTrue);
    expect(row.matches(terms, 'another division', null), isFalse);
    expect(row.matches(terms, null, 'another specialty'), isFalse);
  });
}
