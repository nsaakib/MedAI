import '../localization.dart';

import 'package:flutter/material.dart';

import '../models.dart';

Future<void> showPublicAppGuide(BuildContext context, AppState state) async {
  final topic = await showModalBottomSheet<String>(
    context: context,
    builder: (c) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text(tr('Finding brand alternatives')),
            onTap: () => Navigator.pop(c, 'navigation'),
          ),
          ListTile(
            title: Text(tr('Using another device')),
            onTap: () => Navigator.pop(c, 'sync'),
          ),
          ListTile(
            title: Text(tr('What App Guide sends to Gemini')),
            onTap: () => Navigator.pop(c, 'privacy'),
          ),
        ],
      ),
    ),
  );
  if (topic == null || !context.mounted) return;
  final response = state.api.request('GET', '/app-guide/$topic');
  await showDialog<void>(
    context: context,
    builder: (_) => AlertDialog(
      title: Text(tr('Med.ai App Guide')),
      content: FutureBuilder<dynamic>(
        future: response,
        builder: (_, result) {
          if (result.hasError)
            return Text(tr('App Guide is currently unavailable.'));
          if (result.connectionState != ConnectionState.done) {
            return const SizedBox(width: 160, child: LinearProgressIndicator());
          }
          final value = result.data;
          return Text(tr(value is Map ? value['text']?.toString() ?? '' : ''));
        },
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr('Close')),
        ),
      ],
    ),
  );
}
