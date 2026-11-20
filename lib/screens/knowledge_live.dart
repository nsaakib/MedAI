import '../localization.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../design.dart';
import '../motion.dart';
import '../models.dart';
import '../services/knowledge.dart';

String referenceDate(dynamic seconds) => seconds is int
    ? DateTime.fromMillisecondsSinceEpoch(seconds * 1000)
          .toLocal()
          .toString()
          .split('.')
          .first
    : 'Not available';

class KnowledgeLive extends StatefulWidget {
  const KnowledgeLive({super.key});
  @override
  State<KnowledgeLive> createState() => _KnowledgeLiveState();
}

class _KnowledgeLiveState extends State<KnowledgeLive> {
  Timer? expiryTimer;
  @override
  void initState() {
    super.initState();
    expiryTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  final input = TextEditingController();
  int mode = 0;
  String language = 'all';
  bool busy = false;
  String? error;
  String status = 'Search sources reviewed by your care team.';
  List<Map<String, dynamic>> results = [];
  @override
  void dispose() {
    expiryTimer?.cancel();
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    final s = Scope.of(c);
    final valid = ReferenceSearch.packFresh(s.knowledgePack, DateTime.now());
    return AppFrame(
      back: true,
      title: tr('Reviewed Health References'),
      subtitle: tr('Exact source passages with visible citations.'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Segments(
            labels: const ['Online library', 'Offline copy'],
            value: mode,
            onChanged: busy
                ? (_) {}
                : (v) => setState(() {
                    mode = v;
                    results = [];
                    error = null;
                    status = v == 0
                        ? 'Search current approved sources.'
                        : 'Offline source status was last checked at download.';
                  }),
          ),
          if (mode == 1)
            note(
              tr(
                s.knowledgePack == null
                    ? 'No offline copy is saved. Download while connected.'
                    : 'Offline copy · last checked ${referenceDate(s.knowledgePack!['generated_at'])}\n${valid ? 'Reading available until' : 'Copy expired at'} ${referenceDate(s.knowledgePack!['offline_until'])}. Withdrawals cannot be rechecked while offline.',
              ),
              color: valid ? blue : Colors.orange,
            ),
          TextField(
            controller: input,
            maxLength: 300,
            decoration: InputDecoration(
              labelText: tr('Search words'),
              hintText: tr('Up to 20 words in the source language'),
              prefixIcon: Icon(Icons.search, size: 18),
            ),
            onSubmitted: (_) => busy ? null : search(),
          ),
          gap(8),
          DropdownButtonFormField<String>(
            initialValue: language,
            isExpanded: true,
            decoration: InputDecoration(labelText: tr('Source language')),
            items: [
              DropdownMenuItem(value: 'all', child: Text(tr('All languages'))),
              DropdownMenuItem(value: 'en', child: Text(tr('English'))),
              DropdownMenuItem(value: 'bn', child: Text(tr('Bengali'))),
            ],
            onChanged: busy ? null : (v) => setState(() => language = v!),
          ),
          gap(15),
          ActionButton(
            tr(busy ? 'Working…' : 'Search References'),
            icon: Icons.menu_book_outlined,
            onTap: busy || mode == 1 && !valid ? null : search,
          ),
          gap(12),
          if (error != null) note(tr(error!), color: Colors.orange),
          small(tr(status)),
          gap(12),
          if (mode == 0 || valid)
            for (final hit in results)
              Tile(
                onTap: () => Navigator.push(
                  c,
                  MaterialPageRoute<void>(
                    builder: (_) => ReferenceDetail(
                      id: hit['reference_id'],
                      offline: mode == 1,
                    ),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr(hit['citation']['title']),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    gap(8),
                    Wrap(
                      spacing: 7,
                      runSpacing: 6,
                      children: [
                        Pill(tr(hit['citation']['publisher'])),
                        Pill(
                          tr(hit['citation']['source_version']),
                          color: purple,
                        ),
                        if (mode == 1)
                          Pill(tr('Offline copy'), color: Colors.orange),
                      ],
                    ),
                    gap(12),
                    SelectableText(
                      hit['excerpt'],
                      style: const TextStyle(fontSize: 12, height: 1.7),
                    ),
                    gap(12),
                    small(
                      tr(
                        '${hit['section']} · ${hit['citation']['audience']}\n${hit['citation']['jurisdiction']}\nReview due ${referenceDate(hit['citation']['review_due'])}',
                      ),
                    ),
                    gap(10),
                    Text(
                      tr('Read source details ›'),
                      style: TextStyle(color: blue, fontSize: 11),
                    ),
                  ],
                ),
              ),
          Heading(tr('Offline Reading')),
          small(
            tr(
              'Download the approved library to encrypted device storage for up to 24 hours. Individual source review dates may expire sooner.',
            ),
          ),
          gap(10),
          ActionButton(
            tr('Refresh Offline Copy'),
            icon: Icons.download_outlined,
            onTap: busy ? null : download,
          ),
          if (s.knowledgePack != null)
            TextButton(
              onPressed: busy
                  ? null
                  : () async {
                      try {
                        await s.removeKnowledgePack();
                        if (mounted) setState(() => results = []);
                      } catch (e) {
                        if (mounted) setState(() => error = '$e');
                      }
                    },
              child: Text(tr('Remove downloaded copy')),
            ),
          gap(15),
          note(
            tr(
              'Sources are approved by your configured care team. Retrieval does not verify clinical correctness, diagnose symptoms, or recommend treatment. Ask your care team when unsure.',
            ),
            color: blue,
          ),
          rowTile(
            Icons.people_outline,
            tr('Request Care Team Review'),
            tr('Share your concern and saved records.'),
            () => go(c, 'handoff'),
          ),
        ],
      ),
    );
  }

  Future<void> search() async {
    final s = Scope.of(context);
    setState(() {
      busy = true;
      error = null;
      results = [];
    });
    try {
      if (ReferenceSearch.tokens(input.text).length > 20)
        throw StateError('Use up to 20 distinct search words.');
      if (mode == 1) {
        if (!ReferenceSearch.packFresh(s.knowledgePack, DateTime.now()))
          throw StateError('Refresh your offline copy while connected.');
        final found = ReferenceSearch.offline(
          s.knowledgePack,
          input.text,
          language,
          DateTime.now(),
        );
        setState(() {
          results = found;
          status = found.isEmpty
              ? 'No matching source in the current offline copy.'
              : 'Exact passages from the downloaded copy.';
        });
      } else {
        final response = await s.api.request('POST', '/knowledge/search', {
          'query': input.text.trim(),
          'language': language,
          'limit': 5,
        });
        if (!mounted) return;
        setState(() {
          results = (response['results'] as List)
              .map((x) => Map<String, dynamic>.from(x))
              .toList();
          status = response['message'];
        });
      }
    } catch (e) {
      if (mounted)
        setState(
          () => error = mode == 0
              ? 'Could not search online: $e. Use Offline copy if you have a current download.'
              : e.toString(),
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> download() async {
    final s = Scope.of(context);
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await s.downloadKnowledgePack();
      if (mounted)
        setState(() {
          results = [];
          status =
              'Saved ${(s.knowledgePack!['items'] as List).length} approved sources for offline reading.';
        });
    } catch (e) {
      if (mounted)
        setState(
          () => error = 'Download failed. No new offline copy was saved: $e',
        );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}

class ReferenceDetail extends StatefulWidget {
  const ReferenceDetail({super.key, required this.id, required this.offline});
  final String id;
  final bool offline;
  @override
  State<ReferenceDetail> createState() => _ReferenceDetailState();
}

class _ReferenceDetailState extends State<ReferenceDetail> {
  Future<Map<String, dynamic>>? source;
  Timer? expiryTimer;
  @override
  void initState() {
    super.initState();
    expiryTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    expiryTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    source ??= load();
  }

  Future<Map<String, dynamic>> load() async {
    final s = Scope.of(context);
    if (!widget.offline)
      return Map<String, dynamic>.from(
        await s.api.request('GET', '/knowledge/${widget.id}'),
      );
    if (!ReferenceSearch.packFresh(s.knowledgePack, DateTime.now()))
      throw StateError('Offline copy expired. Connect and refresh.');
    final item = (s.knowledgePack!['items'] as List)
        .where((x) => x['id'] == widget.id)
        .firstOrNull;
    if (item == null ||
        item['review_due'] <= DateTime.now().millisecondsSinceEpoch ~/ 1000)
      throw StateError(
        'Reference is not available in the current offline copy.',
      );
    return Map<String, dynamic>.from(item);
  }

  @override
  Widget build(BuildContext c) => AppFrame(
    back: true,
    title: tr('Reference Details'),
    child: FutureBuilder<Map<String, dynamic>>(
      future: source,
      builder: (c, snapshot) {
        if (snapshot.hasError)
          return note(
            tr('This reference could not be opened: ${snapshot.error}'),
            color: Colors.orange,
          );
        if (!snapshot.hasData)
          return const Center(child: MedLoader(label: 'Loading…'));
        final d = snapshot.data!;
        if (widget.offline &&
            (!ReferenceSearch.packFresh(
                  Scope.of(c).knowledgePack,
                  DateTime.now(),
                ) ||
                d['review_due'] <=
                    DateTime.now().millisecondsSinceEpoch ~/ 1000))
          return note(
            tr(
              'This offline reference has expired. Connect and refresh the library.',
            ),
            color: Colors.orange,
          );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.offline)
              note(
                tr(
                  'Downloaded copy. Current approval or withdrawal status cannot be confirmed offline.',
                ),
                color: Colors.orange,
              ),
            Text(
              tr(d['title']),
              style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w700),
            ),
            gap(12),
            small(
              tr(
                'Publisher: ${d['publisher']}\nEdition: ${d['source_version']}\nLanguage: ${d['language']}\nAudience: ${d['audience']}\nJurisdiction: ${d['jurisdiction']}\nTeam approval: ${referenceDate(d['approved_at'])}\nReview due: ${referenceDate(d['review_due'])}',
              ),
            ),
            gap(18),
            if (d['content'] != null)
              SelectableText(
                d['content'],
                style: const TextStyle(fontSize: 13, height: 1.8),
              )
            else
              for (final p in d['passages'] as List)
                Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      small(tr(p['section'])),
                      gap(7),
                      SelectableText(
                        p['excerpt'],
                        style: const TextStyle(fontSize: 13, height: 1.8),
                      ),
                    ],
                  ),
                ),
            gap(15),
            ActionButton(
              tr('Open Original Source'),
              icon: Icons.open_in_new,
              onTap: () => open(c, d['source_url']),
            ),
            gap(15),
            small(tr('Source content SHA-256')),
            SelectableText(
              d['content_sha256'],
              style: const TextStyle(fontSize: 10, color: muted),
            ),
            gap(14),
            small(
              tr(
                'Approval status was checked when this source was opened, or at the displayed offline download time. Team review is not a diagnosis or an endorsement by the source publisher.',
              ),
            ),
          ],
        );
      },
    ),
  );
  Future<void> open(BuildContext c, String url) async {
    try {
      final uri = Uri.parse(url);
      if (uri.scheme != 'https') throw StateError('Invalid source URL');
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication))
        throw StateError('No browser available');
    } catch (e) {
      if (c.mounted) message(c, tr('Could not open source'), tr(e.toString()));
    }
  }
}
