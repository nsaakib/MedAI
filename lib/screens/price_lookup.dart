import '../localization.dart';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../design.dart';
import '../models.dart';
import '../motion.dart';
import '../services/retailer_session.dart';
import '../services/purchase_math.dart';

class PriceLookupLive extends StatefulWidget {
  const PriceLookupLive({super.key, required this.medicineId});
  final String medicineId;
  @override
  State<PriceLookupLive> createState() => _PriceLookupLiveState();
}

class _PriceLookupLiveState extends State<PriceLookupLive> {
  final url = TextEditingController();
  Map<String, dynamic>? quote;
  bool busy = false, confirmed = false;
  String? error;
  bool started = false;
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!started) {
      started = true;
      Future.microtask(discover);
    }
  }

  Future<void> discover() async {
    final med = Scope.of(context).medicines
        .firstWhere((m) => m.id == widget.medicineId);
    if (med.strength.trim().isEmpty || med.form.trim().isEmpty) {
      setState(
        () => error = 'Review the prescribed strength (including mg/mcg or other unit) and dosage form first.',
      );
      return;
    }
    setState(() {
      busy = true;
      error = null;
      quote = null;
      confirmed = false;
    });
    try {
      final q = await Scope.of(context).api.request('POST', '/market/resolve', {
        'name': med.name,
        'strength': med.strength,
        'form': med.form,
      });
      if (mounted) setState(() => quote = Map<String, dynamic>.from(q));
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    url.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = Scope.of(context);
    final med = s.medicines.where((m) => m.id == widget.medicineId).firstOrNull;
    if (med == null)
      return AppFrame(
        back: true,
        title: tr('Medicine not found'),
        child: SizedBox(),
      );
    final matching =
        quote != null &&
        strengthKey(med.strength) == strengthKey(quote!['strength']) &&
        quantityFormKey(med.form) == quantityFormKey(quote!['form']);
    return AppFrame(
      back: true,
      bottom: false,
      title: tr('Match Online Price'),
      subtitle: tr('${med.name} · ${med.strength} · ${med.form}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          note(
            tr(
              'Choose the exact prescribed brand, strength and dosage form. A similar medicine is not an automatic substitute.',
            ),
            color: blue,
          ),
          ActionButton(
            tr('Find Exact Product & Price'),
            icon: Icons.search,
            onTap: busy ? null : discover,
          ),
          if (busy)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(
                child: MedLoader(label: 'Checking the product listing…'),
              ),
            ),
          if (error != null) ...[
            gap(12),
            note(tr(error!)),
            TextButton(
              onPressed: () => go(context, 'medicine', arguments: med.id),
              child: Text(tr('Review prescribed medicine details')),
            ),
          ],
          if (quote != null) ...[
            gap(15),
            Tile(
              outlined: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr(quote!['product_name']),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  gap(8),
                  small(
                    tr(
                      '${quote!['strength']} · ${quote!['form']}\n${quote!['manufacturer']}',
                    ),
                  ),
                  gap(12),
                  Text(
                    tr(
                      '${money(quote!['pack_price_minor'])} / ${quote!['pack_label']}',
                    ),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  gap(6),
                  small(
                    tr(
                      'Unit estimate: ৳${quote!['unit_price_bdt']} / ${quote!['base_unit']}\nSource: Arogga · checked ${DateTime.fromMillisecondsSinceEpoch((quote!['fetched_at'] as int) * 1000).toLocal()}',
                    ),
                  ),
                  gap(8),
                  Pill(
                    tr(
                      quote!['available'] == true
                          ? 'Listed in stock'
                          : 'Listed unavailable',
                    ),
                    color: quote!['available'] == true ? mint : Colors.orange,
                  ),
                  TextButton(
                    onPressed: () => launchUrl(
                      Uri.parse(quote!['source_url']),
                      mode: LaunchMode.externalApplication,
                    ),
                    child: Text(tr('View source listing')),
                  ),
                ],
              ),
            ),
            if (!matching)
              note(
                tr(
                  'The listed strength or dosage form differs from your medicine entry. Check the prescription and choose an exact match before using this price.',
                ),
              ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: confirmed,
              onChanged: !matching
                  ? null
                  : (v) => setState(() => confirmed = v ?? false),
              title: Text(
                tr(
                  'I checked the brand, strength, form and pack. My prescribed quantity (${med.quantity}) is in individual ${quote!['base_unit']} units, not packs.',
                ),
                style: TextStyle(fontSize: 12),
              ),
            ),
            ActionButton(
              tr('Use This Price'),
              onTap: !confirmed || !matching || busy
                  ? null
                  : () async {
                      setState(() => busy = true);
                      try {
                        // Names/instructions remain prescribed; only procurement metadata changes.
                        med.quoteId = quote!['quote_id'];
                        med.quantityUnit = quote!['base_unit'];
                        med.priceQuote = Map<String, dynamic>.from(quote!);
                        med.productMatchConfirmed = true;
                        med.unitPrice = quote!['unit_price_minor'];
                        med.priceConfirmed = false;
                        await s.commit();
                        if (context.mounted) Navigator.pop(context, true);
                      } catch (e) {
                        if (mounted) setState(() => error = '$e');
                      } finally {
                        if (mounted) setState(() => busy = false);
                      }
                    },
            ),
            gap(10),
            small(
              tr(
                'Estimates expire after 24 hours. The supplier may change its price or availability before checkout.',
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> fetch() async {
    if (url.text.trim().isEmpty) {
      await discover();
      return;
    }
    setState(() {
      busy = true;
      error = null;
      quote = null;
      confirmed = false;
    });
    try {
      final q = await Scope.of(context).api
          .request('POST', '/market/quote', {'product_url': url.text.trim()});
      if (mounted) setState(() => quote = Map<String, dynamic>.from(q));
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}

/// Live supplier search remains in the user's on-device WebView session.
class SupplierPicker extends StatefulWidget {
  const SupplierPicker({super.key, required this.query});
  final String query;
  @override
  State<SupplierPicker> createState() => _SupplierPickerState();
}

class _SupplierPickerState extends State<SupplierPicker> {
  late final WebViewController controller;
  String? current, error;
  int progress = 0;
  bool started = false;
  bool get product =>
      current != null &&
      RegExp(r'^https://(www\.)?arogga\.com/product/\d+/').hasMatch(current!);
  @override
  void initState() {
    super.initState();
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) {
            if (mounted) setState(() => progress = p);
          },
          onUrlChange: (c) {
            if (mounted) setState(() => current = c.url);
          },
          onWebResourceError: (e) {
            if (e.isForMainFrame == true && mounted)
              setState(
                () => error = 'Supplier page could not load. Retry or paste its product link.',
              );
          },
          onNavigationRequest: (r) {
            final u = Uri.tryParse(r.url);
            return u?.scheme == 'https' &&
                    ['arogga.com', 'www.arogga.com'].contains(u?.host)
                ? NavigationDecision.navigate
                : NavigationDecision.prevent;
          },
        ),
      );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!started) {
      started = true;
      RetailerSession.prepare(Scope.of(context).userId!, controller)
          .then((_) {
            if (mounted)
              controller.loadRequest(
                Uri.https('www.arogga.com', '/search', {'q': widget.query}),
              );
          })
          .catchError((Object e) {
            if (mounted)
              setState(() => error = 'Could not open the supplier session.');
          });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(tr('Choose Exact Product'), style: TextStyle(fontSize: 16)),
      actions: [
        IconButton(
          onPressed: () {
            setState(() => error = null);
            controller.reload();
          },
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: small(
              tr(
                'Arogga website · Choose your prescribed product, then use the button below. No account credentials are sent to Med.ai.',
              ),
            ),
          ),
          if (progress < 100) LinearProgressIndicator(value: progress / 100),
          if (error != null)
            Padding(padding: const EdgeInsets.all(12), child: Text(tr(error!))),
          Expanded(child: WebViewWidget(controller: controller)),
          Padding(
            padding: const EdgeInsets.all(14),
            child: ActionButton(
              tr('Use This Product Listing'),
              onTap: product ? () => Navigator.pop(context, current) : null,
            ),
          ),
        ],
      ),
    ),
  );
}
