import 'package:flutter_test/flutter_test.dart';
import 'package:med_ai/services/knowledge.dart';

void main() {
  Map<String, dynamic> pack(int stamp) => {
    'generated_at': stamp,
    'offline_until': stamp + 86400,
    'items': [
      {
        'id': 'source',
        'version': 2,
        'status': 'approved',
        'language': 'bn',
        'review_due': stamp + 172800,
        'title': 'নথি পর্যালোচনা',
        'topics': ['নথি'],
        'passages': [
          {
            'section': 'Passage 1',
            'start_offset': 0,
            'end_offset': 10,
            'excerpt': 'নথি পর্যালোচনা এবং তথ্য সংরক্ষণ।',
          },
        ],
      },
    ],
  };
  final now = DateTime.utc(2026, 1, 1, 12);
  final stamp = now.millisecondsSinceEpoch ~/ 1000;
  test('offline library preserves Bengali tokens and exact excerpts', () {
    final p = pack(stamp);
    final result = ReferenceSearch.offline(p, 'নথি পর্যালোচনা', 'bn', now);
    expect(result.single['reference_id'], 'source');
    expect(result.single['excerpt'], p['items'][0]['passages'][0]['excerpt']);
  });
  test('expired packs and expired sources are inaccessible', () {
    final p = pack(stamp);
    expect(
      ReferenceSearch.offline(p, 'নথি', 'bn', now.add(const Duration(days: 2))),
      isEmpty,
    );
    p['items'][0]['review_due'] = stamp - 1;
    expect(ReferenceSearch.offline(p, 'নথি', 'bn', now), isEmpty);
  });
  test('no matching evidence and wrong language return no content', () {
    final p = pack(stamp);
    expect(ReferenceSearch.offline(p, 'unmatched', 'all', now), isEmpty);
    expect(ReferenceSearch.offline(p, 'নথি', 'en', now), isEmpty);
    expect(ReferenceSearch.offline(p, '***', 'all', now), isEmpty);
  });
  test('clock rollback does not extend a download', () {
    expect(
      ReferenceSearch.packFresh(
        pack(stamp),
        now.subtract(const Duration(hours: 1)),
      ),
      isFalse,
    );
  });
}
