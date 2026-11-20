import '../localization.dart';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../design.dart';
import '../models.dart';
import '../services/purchase_math.dart';

Future<String?> updateAllPrices(
  BuildContext c,
  AppState s,
  ValueChanged<String> progress,
) async {
  final account = s.userId;
  final medicines = s.medicines.where((m) => m.neededToBuy > 0).toList();
  if (medicines.isEmpty) return 'There is nothing to price.';
  final found = <({Medicine original, Map<String, dynamic> quote})>[];
  final issues = <String>[];
  var done = 0;
  for (final med in medicines) {
    if (!c.mounted || s.userId != account || !s.signedIn) return null;
    progress('Checking ${++done}/${medicines.length} · ${med.name}');
    try {
      if (med.strength.isEmpty || med.form.isEmpty) {
        throw StateError('Enter the prescribed strength and dosage form.');
      }
      final response = await s.api.request('POST', '/market/resolve', {
        'name': med.name,
        'strength': med.strength,
        'form': med.form,
      });
      final q = Map<String, dynamic>.from(response as Map);
      if (strengthKey(med.strength) != strengthKey(q['strength'] as String) ||
          quantityFormKey(med.form) != quantityFormKey(q['form'] as String) ||
          quantityFormKey(med.form) !=
              quantityFormKey(q['base_unit'] as String)) {
        throw StateError('Check the prescribed units against this listing.');
      }
      found.add((original: med, quote: q));
    } catch (e) {
      issues.add('${med.name}: $e');
    }
  }
  if (!c.mounted || s.userId != account || !s.signedIn) return null;
  if (found.isEmpty) {
    await showDialog<void>(
      context: c,
      builder: (d) => AlertDialog(
        title: Text(tr('No prices updated')),
        content: SingleChildScrollView(child: Text(tr(issues.join('\n\n')))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d),
            child: Text(tr('Done')),
          ),
        ],
      ),
    );
    return 'Existing prices were kept.';
  }
  final confirmed = <String>{};
  final approved = await showDialog<bool>(
    context: c,
    builder: (d) => StatefulBuilder(
      builder: (context, redraw) => AlertDialog(
        title: Text(tr('Review price matches')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                tr(
                  'Select each exact brand, strength and form. Prices are for the listed pack; prescribe and log quantities in individual units.',
                ),
              ),
              for (final item in found) ...[
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    tr(
                      item.original.name +
                          ' → ' +
                          (item.quote['product_name'] as String),
                    ),
                  ),
                  subtitle: Text(
                    tr(
                      '${item.quote['strength']} · ${item.quote['form']} · ${money(item.quote['pack_price_minor'] as int)} / ${item.quote['pack_label']}${item.quote['available'] == true ? '' : ' · unavailable'}',
                    ),
                  ),
                  value: confirmed.contains(item.original.id),
                  onChanged: (v) => redraw(() {
                    if (v == true) {
                      confirmed.add(item.original.id);
                    } else {
                      confirmed.remove(item.original.id);
                    }
                  }),
                ),
                TextButton(
                  onPressed: () => launchUrl(
                    Uri.parse(item.quote['source_url'] as String),
                    mode: LaunchMode.externalApplication,
                  ),
                  child: Text(tr('View supplier listing')),
                ),
              ],
              for (final issue in issues)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(tr(issue)),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(d, false),
            child: Text(tr('Cancel')),
          ),
          TextButton(
            onPressed: confirmed.isEmpty ? null : () => Navigator.pop(d, true),
            child: Text(tr('Apply selected prices')),
          ),
        ],
      ),
    ),
  );
  if (approved != true || !c.mounted || s.userId != account || !s.signedIn)
    return null;
  var updated = 0;
  for (final item in found) {
    if (!confirmed.contains(item.original.id)) continue;
    final live = s.medicines.where((m) => m.id == item.original.id).firstOrNull;
    if (live == null ||
        live.name != item.original.name ||
        live.strength != item.original.strength ||
        live.form != item.original.form ||
        live.neededToBuy == 0 ||
        (item.quote['expires_at'] as int) <=
            DateTime.now().millisecondsSinceEpoch ~/ 1000)
      continue;
    live.quoteId = item.quote['quote_id'] as String;
    live.quantityUnit = item.quote['base_unit'] as String;
    live.priceQuote = item.quote;
    live.productMatchConfirmed = true;
    live.unitPrice = item.quote['unit_price_minor'] as int;
    live.priceConfirmed = false;
    updated++;
  }
  if (updated > 0) await s.commit();
  return updated == 0
      ? 'No selected prices could be applied.'
      : '$updated price match${updated == 1 ? '' : 'es'} saved. Other entries were kept.';
}
