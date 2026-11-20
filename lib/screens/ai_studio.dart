import 'report_evidence.dart';
import '../localization.dart';
import 'chat_doctor_list.dart';

import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/material.dart';

import 'public_app_guide.dart';

import 'package:flutter/services.dart';

import '../design.dart';
import '../models.dart';
import 'health_dashboard.dart';
import 'documents_live.dart';

List<Map<String, dynamic>> _rows(Object? data) => (data as List? ?? const [])
    .map((e) => Map<String, dynamic>.from(e as Map))
    .toList();

class AiStudio extends StatefulWidget {
  const AiStudio({super.key, this.statistics = false});
  final bool statistics;

  @override
  State<AiStudio> createState() => _AiStudioState();
}

class _AiStudioState extends State<AiStudio> {
  final input = TextEditingController();
  final frame = GlobalKey<ScaffoldState>();
  final selected = <String>{};
  final staticChannel = const MethodChannel('medai/voice');
  List<Map<String, dynamic>> threads = [], turns = [];
  String thread = 'new', division = '', language = 'auto';
  String? account, error, pendingQuestion, lastRequest, lastSignature;
  bool statisticsMode = false;
  bool ready = false,
      loading = false,
      busy = false,
      voice = false,
      consent = false,
      useRecords = false;
  int version = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = Scope.of(context);
    if (!ready || account != state.userId) {
      ready = true;
      account = state.userId;
      version++;
      threads = [];
      statisticsMode = false;
      turns = [];
      thread = 'new';
      input.clear();
      selected.clear();
      error = null;
      pendingQuestion = lastRequest = lastSignature = null;
      consent = useRecords = busy = voice = loading = false;
      if (widget.statistics && account != null) prepareStatistics();
      if (account != null) refresh(state);
    }
  }

  bool active(int id) => mounted && id == version;

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  Future<void> refresh(AppState state, {bool showError = true}) async {
    final id = version;
    try {
      final response = await state.api.request('GET', '/assistant/threads');
      if (active(id)) setState(() => threads = _rows(response['threads']));
    } catch (e) {
      if (active(id) && showError) setState(() => error = e.toString());
    }
  }

  void newChat() {
    if (busy || voice) return;
    setState(() {
      version++;
      thread = 'new';
      statisticsMode = false;
      turns = [];
      input.clear();
      selected.clear();
      error = pendingQuestion = lastRequest = lastSignature = null;
      loading = false;
    });
  }

  Future<void> openChat(String id) async {
    if (busy || voice) return;
    final state = Scope.of(context);
    final epoch = ++version;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final data = await state.api.request('GET', '/assistant/threads/$id');
      if (!active(epoch)) return;
      setState(() {
        thread = id;
        turns = _rows(data['turns']);
        input.clear();
        selected.clear();
        lastRequest = lastSignature = null;
        statisticsMode = false;
      });
    } catch (e) {
      if (active(epoch)) setState(() => error = e.toString());
    } finally {
      if (active(epoch)) setState(() => loading = false);
    }
  }

  Future<void> removeChat(String id) async {
    final state = Scope.of(context);
    final epoch = version;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('Delete this conversation?')),
        content: Text(tr('Your health records will stay in Med.ai.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text(tr('Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(tr('Delete')),
          ),
        ],
      ),
    );
    if (ok != true || !active(epoch) || busy || voice || loading) return;
    setState(() => busy = true);
    try {
      await state.api.request('DELETE', '/assistant/threads/$id');
      if (!active(epoch)) return;
      setState(() {
        busy = false;
        threads.removeWhere((t) => t['id'] == id);
      });
      if (thread == id) newChat();
    } catch (e) {
      if (active(epoch)) setState(() => error = e.toString());
    } finally {
      if (active(epoch)) setState(() => busy = false);
    }
  }

  Future<bool> approve() async {
    if (consent) return true;
    return await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text(tr('Use Med.ai Assistant?')),
            content: Text(
              tr(
                'For report analysis, relevant report text and your question are sent to the configured AI provider. If text is missing, the report image may be read by Groq. With Ollama, processing stays on your server. Verify results against the original.',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: Text(tr('Cancel')),
              ),
              TextButton(
                onPressed: () => Navigator.pop(c, true),
                child: Text(tr('Allow and send')),
              ),
            ],
          ),
        ) ==
        true;
  }

  Future<void> send() async {
    final question = input.text.trim();
    if (question.isEmpty ||
        question.length > 2000 ||
        busy ||
        loading ||
        voice ||
        account == null)
      return;
    final state = Scope.of(context);
    final epoch = version;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (RegExp(
        r'report|lab result|blood test|cbc|hba1c|রিপোর্ট|রিপোর্ট|রিপোট|পরীক্ষার ফল',
        caseSensitive: false,
      ).hasMatch(question)) {
        setState(() => useRecords = true);
      }
      if (!await approve() || !active(epoch)) return;
      consent = true;
      final summarize = statisticsMode;
      final ids = useRecords && !summarize
          ? (selected.toList()..sort())
          : <String>[];
      final effectiveLanguage = language;
      final signature =
          '$thread|$effectiveLanguage|$division|$useRecords|$summarize|$ids|$question';
      if (signature != lastSignature) {
        lastSignature = signature;
        lastRequest = identifier();
      }
      setState(() => pendingQuestion = question);
      final response = await state.api
          .request('POST', '/assistant/threads/$thread', {
            'question': question,
            'request_id': lastRequest,
            'consent': true,
            'language': effectiveLanguage,
            'division': division,
            'use_records': useRecords,
            'document_ids': ids,
            'summarize_statistics': summarize,
          });
      if (!active(epoch)) return;
      setState(() {
        thread = response['id'] as String;
        turns = _rows(response['turns']);
        input.clear();
        lastRequest = lastSignature = null;
        statisticsMode = false;
      });
      await refresh(state, showError: false);
    } catch (e) {
      if (active(epoch)) setState(() => error = e.toString());
    } finally {
      if (active(epoch))
        setState(() {
          busy = false;
          pendingQuestion = null;
        });
    }
  }

  void prepareStatistics() {
    statisticsMode = true;
    useRecords = true;
    consent = false;
    if (input.text.trim().isEmpty) {
      input.text = 'Summarize my health statistics and uploaded lab reports.';
    }
  }

  Future<void> speech() async {
    if (busy || voice || loading) return;
    final epoch = version;
    setState(() => voice = true);
    try {
      final locale = await showModalBottomSheet<String>(
        context: context,
        builder: (c) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  tr(
                    'Google Voice (or your Android speech service) handles dictation and may process audio online. Review the transcript before sending.',
                  ),
                ),
              ),
              ListTile(
                title: Text(tr('বাংলা')),
                onTap: () => Navigator.pop(c, 'bn-BD'),
              ),
              ListTile(
                title: Text(tr('English')),
                onTap: () => Navigator.pop(c, 'en-US'),
              ),
            ],
          ),
        ),
      );
      if (!active(epoch) || locale == null) return;
      final text = await staticChannel.invokeMethod<String>('dictate', locale);
      if (!active(epoch) || text == null || text.trim().isEmpty) return;
      final combined = [
        input.text.trim(),
        text.trim(),
      ].where((s) => s.isNotEmpty).join(' ');
      input.text = String.fromCharCodes(combined.runes.take(2000));
      input.selection = TextSelection.collapsed(offset: input.text.length);
    } catch (_) {
      if (active(epoch))
        setState(
          () => error =
              'Voice input is unavailable. Try your keyboard microphone or type your message.',
        );
    } finally {
      if (active(epoch)) setState(() => voice = false);
    }
  }

  Future<void> options(AppState state) async {
    var enabled = useRecords;
    var area = division;
    var lang = language;
    final ids = {...selected};
    final picked = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (c) => StatefulBuilder(
        builder: (c, change) => FractionallySizedBox(
          heightFactor: .75,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Heading(tr('Chat context')),
              SwitchListTile(
                title: Text(tr('Use my health records')),
                subtitle: Text(
                  tr('Retrieve relevant synced readings and report text.'),
                ),
                value: enabled,
                onChanged: (v) => change(() => enabled = v),
              ),
              if (enabled) ...[
                Heading(tr('Optional report selection')),
                Text(
                  tr(
                    'Choose up to 3 reports, or leave blank to search your uploaded reports.',
                  ),
                ),
                for (final d in state.documents.where(
                  (d) => d['kind'] == 'Lab Report' && d['uploaded'] == true,
                ))
                  CheckboxListTile(
                    title: Text(tr('${d['report_title'] ?? 'Lab report'}')),
                    subtitle: Text(tr('${d['report_date'] ?? ''}')),
                    value: ids.contains(d['id']),
                    onChanged: ids.length == 3 && !ids.contains(d['id'])
                        ? null
                        : (v) => change(() {
                            final id = d['id'] as String;
                            if (v == true) {
                              ids.add(id);
                            } else {
                              ids.remove(id);
                            }
                          }),
                  ),
              ],
              Heading(tr('Doctor search location')),
              DropdownButton<String>(
                value: area,
                isExpanded: true,
                items: [
                  for (final item in ['', 'Dhaka', 'Rajshahi', 'Barishal'])
                    DropdownMenuItem(
                      value: item,
                      child: Text(
                        tr(item.isEmpty ? 'All listed divisions' : item),
                      ),
                    ),
                ],
                onChanged: (v) => change(() => area = v ?? ''),
              ),
              Heading(tr('Answer language')),
              DropdownButton<String>(
                value: lang,
                isExpanded: true,
                items: [
                  DropdownMenuItem(value: 'auto', child: Text(tr('Auto'))),
                  DropdownMenuItem(value: 'bn', child: Text(tr('বাংলা'))),
                  DropdownMenuItem(value: 'en', child: Text(tr('English'))),
                ],
                onChanged: (v) => change(() => lang = v ?? 'auto'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(c, true),
                child: Text(tr('Done')),
              ),
            ],
          ),
        ),
      ),
    );
    if (mounted && account == state.userId && picked == true) {
      setState(() {
        useRecords = enabled;
        if (!enabled) statisticsMode = false;
        division = area;
        language = lang;
        selected
          ..clear()
          ..addAll(ids);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = Scope.of(context);
    final blocked = busy || voice || loading;
    return Scaffold(
      key: frame,
      backgroundColor: const Color(0xfff7f9ff),
      drawer: Drawer(
        child: SafeArea(
          child: ListView(
            children: [
              ListTile(
                title: Text(
                  tr('Conversations'),
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.help_outline),
                title: Text(tr('App Guide')),
                onTap: () {
                  Navigator.pop(context);
                  showPublicAppGuide(context, state);
                },
              ),
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: Text(tr('New chat')),
                enabled: !blocked,
                onTap: () {
                  Navigator.pop(context);
                  newChat();
                },
              ),
              ListTile(
                leading: const Icon(Icons.refresh),
                title: Text(tr('Refresh history')),
                onTap: blocked ? null : () => refresh(state),
              ),
              for (final t in threads)
                ListTile(
                  selected: t['id'] == thread,
                  enabled: !blocked,
                  title: Text(
                    tr('${t['title']}'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: IconButton(
                    tooltip: tr('Delete conversation'),
                    icon: const Icon(Icons.delete_outline),
                    onPressed: blocked
                        ? null
                        : () => removeChat(t['id'] as String),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    openChat(t['id'] as String);
                  },
                ),
            ],
          ),
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Row(
              children: [
                IconButton(
                  tooltip: tr('Chat history'),
                  icon: const Icon(Icons.menu),
                  onPressed: () => frame.currentState?.openDrawer(),
                ),
                const Expanded(child: Center(child: Brand())),
                IconButton(
                  tooltip: tr('New chat'),
                  icon: const Icon(Icons.edit_square),
                  onPressed: blocked ? null : newChat,
                ),
              ],
            ),
            Expanded(
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : turns.isEmpty && pendingQuestion == null
                  ? Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          children: [
                            const Mark(size: 56),
                            gap(14),
                            Text(
                              tr('How can I help?'),
                              style: TextStyle(
                                fontSize: 25,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            gap(10),
                            Text(
                              tr(
                                'Ask about a report, a health reading, or describe your symptoms.',
                              ),
                              textAlign: TextAlign.center,
                            ),
                            gap(14),
                            TextButton.icon(
                              onPressed: blocked || account == null
                                  ? null
                                  : () => setState(prepareStatistics),
                              icon: const Icon(Icons.auto_awesome_outlined),
                              label: Text(tr('Summarize my statistics')),
                            ),
                            TextButton.icon(
                              onPressed: () => go(context, 'health-dashboard'),
                              icon: const Icon(Icons.insights_outlined),
                              label: Text(tr('View health dashboard')),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                      itemCount:
                          turns.length + (pendingQuestion == null ? 0 : 1),
                      itemBuilder: (c, i) {
                        if (pendingQuestion != null && i == 0) {
                          return Column(
                            children: [
                              _userBubble(pendingQuestion!),
                              const LinearProgressIndicator(),
                            ],
                          );
                        }
                        final turn =
                            turns[turns.length -
                                1 -
                                i +
                                (pendingQuestion == null ? 0 : 1)];
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _userBubble('${turn['question']}'),
                            _reply(c, turn),
                            gap(14),
                          ],
                        );
                      },
                    ),
            ),
            if (statisticsMode)
              TextButton.icon(
                onPressed: blocked
                    ? null
                    : () => setState(() => statisticsMode = false),
                icon: const Icon(Icons.close),
                label: Text(tr('Statistics summary mode')),
              ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 6,
                ),
                child: Text(
                  tr(error!),
                  style: const TextStyle(color: Color(0xffa42b48)),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
              child: StudioSurface(
                radius: 27,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: tr(
                        useRecords ? 'Health context on' : 'Chat context',
                      ),
                      icon: Icon(
                        useRecords ? Icons.folder_shared : Icons.add,
                        color: blue,
                      ),
                      onPressed: blocked ? null : () => options(state),
                    ),
                    Expanded(
                      child: TextField(
                        controller: input,
                        enabled: !blocked && account != null,
                        minLines: 1,
                        maxLines: 4,
                        maxLength: 2000,
                        decoration: InputDecoration(
                          hintText: tr('Ask Med.ai'),
                          counterText: '',
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: tr('Dictate symptoms'),
                      icon: const Icon(Icons.mic_none),
                      onPressed: blocked || account == null ? null : speech,
                    ),
                    IconButton.filled(
                      tooltip: 'Send message',
                      icon: const Icon(Icons.arrow_upward),
                      onPressed: blocked || account == null ? null : send,
                    ),
                  ],
                ),
              ),
            ),
            Text(
              tr(
                useRecords
                    ? 'Health context on · synced records only'
                    : 'AI can make mistakes. Check important information.',
              ),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 10, color: muted),
            ),
            gap(6),
            SafeArea(top: false, child: const BottomBar(tab: 4)),
          ],
        ),
      ),
    );
  }

  Widget _userBubble(String text) => Align(
    alignment: Alignment.centerRight,
    child: Container(
      constraints: const BoxConstraints(maxWidth: 340),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xffe9efff),
        borderRadius: BorderRadius.circular(20),
      ),
      child: SelectableText(
        text,
        style: const TextStyle(fontSize: 14, height: 1.45),
      ),
    ),
  );

  Widget _reply(BuildContext c, Map<String, dynamic> turn) {
    final rawTriage = turn['triage'];
    final triage = rawTriage is Map
        ? Map<String, dynamic>.from(rawTriage)
        : <String, dynamic>{};
    final routine = triage['level'] == 'routine';
    final bn = turn['language'] == 'bn';
    final departments = routine
        ? _rows(triage['departments'])
        : <Map<String, dynamic>>[];
    final questions = _followUp(triage);
    final browseDirectory = routine || triage['level'] == 'clarify';
    final doctors = browseDirectory
        ? _rows(turn['doctors'])
        : <Map<String, dynamic>>[];
    final sources = _rows(turn['sources']);
    final health = _rows(turn['health']);
    final answer = turn['answer'] as String? ?? '';
    final lines = answer.isEmpty ? <String>[] : answer.split('\n');
    return StudioSurface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Mark(size: 27),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  tr('Med.ai Assistant'),
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          gap(10),
          if (triage.isNotEmpty && triage['level'] != 'general')
            _triageCard(triage, bn),
          for (final line in lines)
            if (line.trim().isEmpty) gap(7) else _answerLine(line),
          if (_rows(turn['findings']).isNotEmpty) ...[
            gap(10),
            Text(
              tr('Values read from report text'),
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(tr('Verify these OCR values against the original report.')),
            for (final finding in _rows(turn['findings'])) ...[
              gap(8),
              StudioSurface(
                color: const Color(0xffeff4ff),
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(tr('${finding['name']} · [${finding['source']}]')),
                    Text(
                      tr('${finding['value']}'),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (finding['date'] != null) Text(tr('${finding['date']}')),
                  ],
                ),
              ),
            ],
          ],
          ReportEvidence(
            sources: _rows(turn['report_details']),
            onOpen: (id) => Navigator.of(c).push<void>(
              MaterialPageRoute(builder: (_) => DocumentViewer(id: id)),
            ),
          ),
          if (sources.isNotEmpty || health.isNotEmpty)
            ExpansionTile(
              shape: const Border(),
              collapsedShape: const Border(),
              tilePadding: EdgeInsets.zero,
              title: Text(tr('Sources used')),
              children: [
                for (final s in sources)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text(tr('[${s['label']}] ${s['title']}')),
                    subtitle: Text(
                      tr('${s['date'] ?? 'Date not listed'} · Report OCR'),
                    ),
                    onTap: () {
                      for (final report in Scope.of(c).documents) {
                        if (report['id'] == s['document_id']) {
                          openReport(c, report);
                          return;
                        }
                      }
                      go(c, 'health-dashboard');
                    },
                  ),
                for (final h in health)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    onTap: () => go(c, 'health-dashboard'),
                    title: Text(
                      tr(
                        '[${h['label']}] ${healthLabel('${h['kind']}')} · ${h['value']} ${h['unit']}',
                      ),
                    ),
                    subtitle: Text(tr('${h['measured_at']}')),
                  ),
              ],
            ),
          if (departments.isNotEmpty) ...[
            gap(10),
            Text(
              tr(
                bn
                    ? 'প্রস্তাবিত বিভাগ · সাধারণ পরামর্শ'
                    : 'Recommended department · routine consultation',
              ),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            for (final department in departments) ...[
              gap(6),
              Text(
                tr('${department['name']}'),
                style: const TextStyle(
                  color: blue,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(tr('${department['reason']}')),
            ],
            gap(8),
            if (doctors.isEmpty)
              Text(
                tr(
                  bn
                      ? 'নির্বাচিত বিভাগ বা এলাকায় কোনো তালিকা পাওয়া যায়নি।'
                      : 'No directory matches in the selected area.',
                ),
              ),
          ],
          if (browseDirectory && doctors.isNotEmpty) ...[
            if (triage['directory_context'] is String)
              Text(tr(triage['directory_context'] as String)),
            gap(8),
            ChatDoctorList(turn: turn),
          ],
          if (routine && questions.isNotEmpty) ...[
            gap(10),
            Text(
              tr(bn ? 'ঐচ্ছিক প্রশ্ন' : 'Optional question'),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(tr(questions.first)),
          ],
        ],
      ),
    );
  }

  List<String> _followUp(Map<String, dynamic> triage) =>
      (triage['follow_up'] as List? ?? const [])
          .whereType<String>()
          .where((q) => q.trim().isNotEmpty)
          .take(1)
          .toList();

  Widget _triageCard(Map<String, dynamic> triage, bool bn) {
    final level = triage['level'];
    final emergency = level == 'emergency';
    final title = switch (level) {
      'emergency' => bn ? 'জরুরি সতর্কতা' : 'Emergency warning',
      'urgent' => bn ? 'আজই চিকিৎসা নিন' : 'Same-day assessment',
      'clarify' =>
        _followUp(triage).isEmpty
            ? (bn ? 'পরবর্তী করণীয়' : 'What to do next')
            : (bn ? 'একটি প্রশ্ন' : 'One question'),
      _ => bn ? 'সাধারণ চিকিৎসা পরামর্শ' : 'Routine care guidance',
    };
    final symptoms = _rows(triage['symptoms']);
    final guidance = triage['guidance'] as String? ?? '';
    final reason = triage['reason'] as String? ?? '';
    return StudioSurface(
      color: emergency
          ? const Color(0xffffe9eb)
          : level == 'urgent' || level == 'clarify'
          ? const Color(0xfffff4df)
          : const Color(0xffeff4ff),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                emergency
                    ? Icons.warning_amber_rounded
                    : Icons.medical_services_outlined,
                color: emergency ? const Color(0xffa62642) : navy,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  tr(title),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          if (reason.isNotEmpty) ...[gap(7), Text(tr(reason))],
          if (guidance.isNotEmpty) ...[gap(7), Text(tr(guidance))],
          if (level == 'emergency' && triage['phone'] == '999')
            TextButton.icon(
              icon: const Icon(Icons.call_outlined),
              label: Text(
                tr(
                  bn
                      ? 'বাংলাদেশে ৯৯৯ ডায়াল করুন'
                      : 'Open dialer for 999 (Bangladesh)',
                ),
              ),
              onPressed: () async {
                var opened = false;
                try {
                  opened = await launchUrl(Uri(scheme: 'tel', path: '999'));
                } catch (_) {}
                if (!opened && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        tr(
                          bn
                              ? 'আপনার ফোনের ডায়ালারে ৯৯৯ লিখুন।'
                              : 'Dial 999 using your phone app.',
                        ),
                      ),
                    ),
                  );
                }
              },
            ),
          if (symptoms.isNotEmpty) ...[
            gap(7),
            Text(
              tr(bn ? 'আপনার বলা লক্ষণ' : 'Symptoms mentioned'),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            for (final symptom in symptoms)
              Text(
                tr(
                  [
                        symptom['name'],
                        symptom['onset'],
                        symptom['duration'],
                        symptom['severity'],
                        symptom['associated'],
                      ]
                      .whereType<String>()
                      .where((value) => value.isNotEmpty)
                      .join(' · '),
                ),
              ),
          ],
          if (level == 'clarify')
            for (final q in _followUp(triage)) ...[gap(7), Text(tr(q))],
          gap(7),
          Text(
            tr(
              bn
                  ? 'এটি চিকিৎসার দিকনির্দেশনা, রোগনির্ণয় নয়।'
                  : 'This is guidance on where to seek care, not a diagnosis.',
            ),
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _answerLine(String line) {
    final heading = RegExp(r'^#{1,4}\s+').hasMatch(line);
    return Padding(
      padding: EdgeInsets.only(top: heading ? 9 : 1, bottom: heading ? 5 : 1),
      child: SelectableText(
        line
            .replaceFirst(RegExp(r'^#{1,4}\s+'), '')
            .replaceAll('**', '')
            .replaceFirst(RegExp(r'^[-*]\s+'), '• '),
        style: TextStyle(
          fontSize: heading ? 16 : 14,
          height: 1.5,
          fontWeight: heading ? FontWeight.w700 : FontWeight.normal,
          color: navy,
        ),
      ),
    );
  }
}
