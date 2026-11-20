import 'report_evidence.dart';
import '../localization.dart';

import 'package:flutter/material.dart';

import '../design.dart';
import '../models.dart';
import 'documents_live.dart';

class ReportChat extends StatefulWidget {
  const ReportChat({super.key, this.documentId});
  final String? documentId;
  @override
  State<ReportChat> createState() => _ReportChatState();
}

class _ReportChatState extends State<ReportChat> {
  final input = TextEditingController();
  final scroll = ScrollController();
  String language = 'auto';
  List<Map<String, dynamic>> turns = [];
  bool loading = true, sending = false, consent = false, configured = false;
  String? error, pendingId, pendingQuestion;
  bool started = false;
  String? activeAccount;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final account = Scope.of(context).userId;
    if (!started || activeAccount != account) {
      started = true;
      activeAccount = account;
      turns = [];
      consent = false;
      configured = false;
      loading = true;
      input.clear();
      pendingId = null;
      pendingQuestion = null;
      error = null;
      load();
    }
  }

  @override
  void dispose() {
    input.dispose();
    scroll.dispose();
    super.dispose();
  }

  Future<void> load() async {
    final state = Scope.of(context);
    final account = state.userId;
    try {
      final data = await state.api.request('GET', '/report-chat');
      if (!mounted || state.userId != account) return;
      setState(() {
        configured = data['configured'] == true;
        turns = (data['turns'] as List)
            .map((t) => Map<String, dynamic>.from(t as Map))
            .toList();
        error = null;
      });
    } catch (e) {
      if (mounted && state.userId == account)
        setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> send() async {
    final question = input.text.trim();
    if (question.isEmpty || sending) return;
    if (!consent && !await allowSharing()) return;
    if (!mounted) return;
    final state = Scope.of(context);
    final account = state.userId;
    if (pendingQuestion != question) {
      pendingQuestion = question;
      pendingId = identifier();
    }
    setState(() {
      sending = true;
      error = null;
    });
    try {
      final result = await state.api.request('POST', '/report-chat', {
        'question': question,
        'request_id': pendingId,
        'consent': consent,
        'language': language,
        'document_ids': widget.documentId == null
            ? <String>[]
            : [widget.documentId!],
      });
      if (!mounted || state.userId != account) return;
      setState(() {
        if (!turns.any((t) => t['request_id'] == result['request_id'])) {
          turns.add(Map<String, dynamic>.from(result as Map));
        }
        input.clear();
        pendingId = null;
        pendingQuestion = null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && scroll.hasClients)
          scroll.animateTo(
            0,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
      });
    } catch (e) {
      if (mounted && state.userId == account)
        setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> clear() async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('Clear chat history?')),
        content: Text(
          tr(
            'This deletes your saved conversation from Med.ai. Your reports are kept.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(tr('Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(tr('Clear')),
          ),
        ],
      ),
    );
    if (!mounted || accepted != true) return;
    final state = Scope.of(context);
    final account = state.userId;
    setState(() => sending = true);
    try {
      await state.api.request('DELETE', '/report-chat');
      if (mounted && state.userId == account)
        setState(() {
          turns.clear();
          pendingId = null;
          pendingQuestion = null;
        });
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<bool> allowSharing() async {
    final accepted = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('Use report-aware AI?')),
        content: SingleChildScrollView(
          child: Text(
            tr(
              'For report analysis, relevant report text and your question are sent to the configured AI provider. If text is missing, the report image may be read by Groq. With Ollama, processing stays on your server. Verify results against the original.',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(tr('Cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(tr('Allow and send')),
          ),
        ],
      ),
    );
    if (!mounted) return false;
    setState(() => consent = accepted == true);
    return consent;
  }

  Widget bubble(String text, {required bool user}) => Align(
    alignment: user ? Alignment.centerRight : Alignment.centerLeft,
    child: Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: user ? soft : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE6ECF7)),
      ),
      child: Text(tr(text), style: const TextStyle(height: 1.5)),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF5F8FF),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Material(
          color: Colors.white,
          child: SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: tr('Back'),
                        onPressed: () => Navigator.maybePop(context),
                        icon: const Icon(Icons.chevron_left),
                      ),
                      const Expanded(child: Brand()),
                      IconButton(
                        tooltip: tr('Clear chat history'),
                        onPressed: sending || loading ? null : clear,
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          tr('Report assistant'),
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: navy,
                          ),
                        ),
                      ),
                      DropdownButton<String>(
                        value: language,
                        underline: const SizedBox(),
                        items: [
                          DropdownMenuItem(
                            value: 'auto',
                            child: Text(tr('Auto language')),
                          ),
                          DropdownMenuItem(
                            value: 'bn',
                            child: Text(tr('বাংলা')),
                          ),
                          DropdownMenuItem(
                            value: 'en',
                            child: Text(tr('English')),
                          ),
                        ],
                        onChanged: sending
                            ? null
                            : (v) => setState(() {
                                language = v ?? 'auto';
                                pendingId = null;
                                pendingQuestion = null;
                              }),
                      ),
                    ],
                  ),
                ),
                if (loading || sending) const LinearProgressIndicator(),
                Expanded(
                  child: SelectionArea(
                    child: ListView.builder(
                      key: const ValueKey('chat-messages'),
                      controller: scroll,
                      reverse: true,
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.all(16),
                      itemCount: turns.length + 1,
                      itemBuilder: (context, index) {
                        if (index == turns.length)
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Text(
                              tr(
                                widget.documentId == null
                                    ? 'Ask about your saved reports. AI can make mistakes; verify values against the original.'
                                    : 'Ask about this report. AI can make mistakes; verify values against the original.',
                              ),
                              style: const TextStyle(color: muted),
                            ),
                          );
                        final turn = turns[turns.length - 1 - index];
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            bubble(turn['question'] as String, user: true),
                            bubble(turn['answer'] as String, user: false),
                            ReportEvidence(
                              sources:
                                  (turn['report_details'] as List? ?? const [])
                                      .whereType<Map>()
                                      .map((s) => Map<String, dynamic>.from(s))
                                      .toList(),
                              onOpen: (id) => Navigator.of(context).push<void>(
                                MaterialPageRoute(
                                  builder: (_) => DocumentViewer(id: id),
                                ),
                              ),
                            ),
                            for (final raw in (turn['sources'] as List? ?? []))
                              TextButton(
                                onPressed: () =>
                                    Navigator.of(context).push<void>(
                                      MaterialPageRoute(
                                        builder: (_) => DocumentViewer(
                                          id: raw['document_id'] as String,
                                          tab: 1,
                                        ),
                                      ),
                                    ),
                                child: Text(
                                  tr(
                                    '[${raw['label']}] ${raw['title']} · ${raw['date'] ?? 'Date not identified'}',
                                  ),
                                ),
                              ),
                            const SizedBox(height: 12),
                          ],
                        );
                      },
                    ),
                  ),
                ),
                if (error != null)
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 90),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        tr(error!),
                        style: const TextStyle(color: Colors.deepOrange),
                      ),
                    ),
                  ),
                if (!loading && !configured)
                  TextButton(
                    onPressed: load,
                    child: Text(tr('AI setup needed · Check connection')),
                  ),
                Container(
                  key: const ValueKey('chat-composer'),
                  padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: Color(0xFFE6ECF7))),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: input,
                          enabled: !sending,
                          minLines: 1,
                          maxLines: 4,
                          maxLength: 2000,
                          decoration: InputDecoration(
                            hintText: tr('Message / আপনার প্রশ্ন'),
                            counterText: '',
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: tr('Send message'),
                        icon: const Icon(Icons.arrow_upward, color: blue),
                        onPressed: loading || sending || !configured
                            ? null
                            : send,
                      ),
                    ],
                  ),
                ),
                const BottomBar(tab: 1),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
