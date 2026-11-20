import 'dart:convert';
import 'dart:io';
import '../lib/services/knowledge.dart';

void check(bool condition, String text) {
  if (!condition) throw StateError(text);
}

void main(List<String> args) {
  final now = DateTime.utc(2026, 1, 1, 12);
  final stamp = now.millisecondsSinceEpoch ~/ 1000;
  final pack = <String, dynamic>{
    'generated_at': stamp,
    'offline_until': stamp + 86400,
    'items': [
      {
        'id': 'en',
        'version': 2,
        'status': 'approved',
        'review_due': stamp + 100000,
        'language': 'en',
        'title': 'Document references',
        'topics': ['files'],
        'passages': [
          {
            'section': 'Passage 1',
            'start_offset': 0,
            'end_offset': 30,
            'excerpt':
                'A source passage about document upload and offline storage.',
          },
        ],
      },
      {
        'id': 'bn',
        'version': 2,
        'status': 'approved',
        'review_due': stamp + 100000,
        'language': 'bn',
        'title': 'নথি পর্যালোচনা',
        'topics': ['নথি'],
        'passages': [
          {
            'section': 'Passage 1',
            'start_offset': 0,
            'end_offset': 20,
            'excerpt': 'নথি পর্যালোচনা এবং তথ্য সংরক্ষণ পরীক্ষা করা হচ্ছে।',
          },
        ],
      },
    ],
  };
  check(
    ReferenceSearch.packFresh(pack, now),
    'Current pack should be readable',
  );
  check(
    !ReferenceSearch.packFresh(pack, now.add(const Duration(days: 2))),
    'Expired pack must be blocked',
  );
  check(
    !ReferenceSearch.packFresh(pack, now.subtract(const Duration(hours: 1))),
    'Clock rollback must not extend lifetime',
  );
  check(
    ReferenceSearch.offline(pack, 'upload', 'en', now).single['reference_id'] ==
        'en',
    'English retrieval failed',
  );
  check(
    ReferenceSearch.offline(
          pack,
          'নথি পর্যালোচনা',
          'bn',
          now,
        ).single['reference_id'] ==
        'bn',
    'Bengali combining marks failed',
  );
  check(
    ReferenceSearch.offline(pack, 'unmatchedphrase', 'all', now).isEmpty,
    'No evidence should abstain',
  );
  check(
    ReferenceSearch.offline(pack, '***', 'all', now).isEmpty,
    'Non-word query should not browse',
  );
  check(
    ReferenceSearch.offline(pack, 'upload', 'bn', now).isEmpty,
    'Language filter must apply',
  );
  (pack['items'] as List).first['review_due'] = stamp - 1;
  check(
    ReferenceSearch.offline(pack, 'upload', 'all', now).isEmpty,
    'Expired source must be hidden inside a current pack',
  );
  if (args.isNotEmpty) {
    final server = Map<String, dynamic>.from(
      jsonDecode(File(args.first).readAsStringSync()),
    );
    final generated = DateTime.fromMillisecondsSinceEpoch(
      server['generated_at'] * 1000,
      isUtc: true,
    );
    check(
      ReferenceSearch.offline(server, 'upload', 'en', generated).isNotEmpty,
      'Real backend pack is incompatible with the mobile reader',
    );
  }
  print(
    'Offline reference checks passed, including English/Bengali, expiry, empty evidence and backend-pack compatibility when supplied.',
  );
}
