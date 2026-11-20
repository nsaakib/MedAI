/// Literal reference retrieval only. No answer synthesis or clinical inference.
class ReferenceSearch {
  static List<String> tokens(String text) => RegExp(
    r'[\p{L}\p{M}\p{N}]+',
    unicode: true,
  ).allMatches(text.toLowerCase()).map((m) => m.group(0)!).toSet().toList();
  static bool packFresh(Map<String, dynamic>? pack, DateTime now) {
    if (pack == null ||
        pack['generated_at'] is! int ||
        pack['offline_until'] is! int)
      return false;
    final stamp = now.toUtc().millisecondsSinceEpoch ~/ 1000;
    return stamp >= pack['generated_at'] - 300 && stamp < pack['offline_until'];
  }

  static List<Map<String, dynamic>> offline(
    Map<String, dynamic>? pack,
    String query,
    String language,
    DateTime now,
  ) {
    if (!packFresh(pack, now)) return [];
    final terms = tokens(query);
    if (terms.length > 20) return [];
    if (query.trim().isNotEmpty && terms.isEmpty) return [];
    final stamp = now.toUtc().millisecondsSinceEpoch ~/ 1000;
    final hits = <Map<String, dynamic>>[];
    for (final raw in pack!['items'] as List? ?? []) {
      final item = Map<String, dynamic>.from(raw);
      if (item['status'] != 'approved' ||
          item['review_due'] is! int ||
          item['review_due'] <= stamp)
        continue;
      if (language != 'all' && item['language'] != language) continue;
      for (final rawPassage in item['passages'] as List? ?? []) {
        final p = Map<String, dynamic>.from(rawPassage);
        // The term limit applies to queries, not source passages.
        final full = RegExp(r'[\p{L}\p{M}\p{N}]+', unicode: true)
            .allMatches(
              '${item['title']} ${(item['topics'] as List? ?? []).join(' ')} ${p['excerpt']}'
                  .toLowerCase(),
            )
            .map((m) => m.group(0)!)
            .toSet();
        if (terms.every(full.contains)) {
          hits.add({
            'reference_id': item['id'],
            'source_revision': item['version'],
            'section': p['section'],
            'start_offset': p['start_offset'],
            'end_offset': p['end_offset'],
            'excerpt': p['excerpt'],
            'citation': {
              for (final key in [
                'title',
                'publisher',
                'source_url',
                'source_version',
                'language',
                'audience',
                'jurisdiction',
                'content_sha256',
                'approved_at',
                'review_due',
                'reviewer_id',
              ])
                key: item[key],
            },
          });
          break;
        }
      }
      if (hits.length >= 10) break;
    }
    return hits;
  }
}
