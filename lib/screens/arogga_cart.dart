import '../localization.dart';

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../design.dart';
import '../models.dart';
import '../services/retailer_session.dart';
import '../services/cart_queue.dart';
import '../services/cart_timing.dart';

/// A best-effort normal-UI assistant. Never submits an order or payment.
class AroggaCartLive extends StatefulWidget {
  const AroggaCartLive({super.key, required this.rows});
  final List<Map<String, dynamic>> rows;
  @override
  State<AroggaCartLive> createState() => _AroggaCartLiveState();
}

class _AroggaCartLiveState extends State<AroggaCartLive> {
  late final WebViewController controller;
  Future<void>? retailerReady;
  Future<String>? cartScript;
  int lastRenderProgress = -1;
  int generation = 0, index = 0, progress = 0;
  bool running = false, started = false, consent = false, loginRequired = false;
  final confirmed = <int>{};
  final skipped = <int, String>{};
  String profilePhone = '';
  bool useProfilePhone = false, loginSendTried = false;
  String status =
      'Review the supplier page. Start only after checking your selected items.';
  Map<String, dynamic> get row => widget.rows[index];
  Map<String, dynamic> get quote => Map<String, dynamic>.from(row['quote']);

  @override
  void initState() {
    super.initState();
    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => progress = 100);
          },
          onProgress: (p) {
            if (!mounted || (p != 100 && (p - lastRenderProgress).abs() < 8))
              return;
            lastRenderProgress = p;
            setState(() => progress = p);
          },
          onWebResourceError: (e) {
            if (e.isForMainFrame == true && mounted && !running)
              pause(
                'Supplier page failed to load. Use its controls manually or retry.',
              );
          },
          onNavigationRequest: (r) async {
            final u = Uri.tryParse(r.url);
            if (u?.scheme == 'https' &&
                ['www.arogga.com', 'arogga.com'].contains(u?.host))
              return NavigationDecision.navigate;
            if (!r.isMainFrame) return NavigationDecision.navigate;
            if (running) {
              pause(
                'External navigation needs your review. Automation has stopped.',
              );
              return NavigationDecision.prevent;
            }
            if (u?.scheme == 'https' && mounted) {
              final open = await showDialog<bool>(
                context: context,
                builder: (c) => AlertDialog(
                  title: Text(tr('Open external page?')),
                  content: Text(
                    tr(
                      'Continue manually at ${u!.host}? Med.ai will not fill payment details or submit an order.',
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: Text(tr('Stay here')),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: Text(tr('Open')),
                    ),
                  ],
                ),
              );
              if (open == true)
                await launchUrl(u!, mode: LaunchMode.externalApplication);
            }
            return NavigationDecision.prevent;
          },
        ),
      );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!started) {
      final digits = Scope.of(context).phone
          .replaceAll(RegExp(r'[\s()+-]'), '');
      profilePhone = digits.startsWith('880') ? digits.substring(2) : digits;
      if (!RegExp(r'^01[3-9]\d{8}$').hasMatch(profilePhone)) profilePhone = '';
      started = true;
      retailerReady = RetailerSession.prepare(
        Scope.of(context).userId!,
        controller,
      );
      retailerReady!
          .then((_) async {
            if (mounted && !running)
              await controller.loadRequest(Uri.parse(quote['source_url']));
          })
          .catchError((Object e) {
            if (mounted && !running)
              pause(
                'Could not open the supplier session. Close this page and try again.',
              );
          });
    }
  }

  @override
  void dispose() {
    generation++;
    super.dispose();
  }

  void pause(String message) {
    generation++;
    if (mounted)
      setState(() {
        running = false;
        status = message;
      });
  }

  bool active(int epoch) => mounted && generation == epoch;

  Future<bool> waitForLogin(String script, int epoch) async {
    if (!active(epoch)) return false;
    setState(() {
      loginRequired = true;
      status = 'Complete Arogga sign-in below. The assistant will resume after sign-in.';
    });
    if (useProfilePhone && profilePhone.isNotEmpty && !loginSendTried) {
      loginSendTried = true;
      try {
        for (var attempt = 0; attempt < 6 && active(epoch); attempt++) {
          final result = await controller
              .runJavaScriptReturningResult(
                '(()=>{$script;return medaiSendLogin(${jsonEncode(profilePhone)});})()',
              )
              .timeout(const Duration(seconds: 5));
          if (!active(epoch)) return false;
          if (result.toString().contains('sent')) {
            setState(
              () => status = 'Code requested on Arogga. Enter or autofill the SMS code below and confirm login.',
            );
            break;
          }
          await Future<void>.delayed(const Duration(milliseconds: 350));
        }
      } catch (_) {
        /* Leave the visible sign-in panel usable. */
      }
    }
    final deadline = DateTime.now().add(const Duration(minutes: 4));
    var stable = 0;
    while (active(epoch) && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 850));
      if (!active(epoch)) return false;
      try {
        final raw = await controller
            .runJavaScriptReturningResult(
              '(()=>{$script;medaiPrepareOtp();return medaiLoginRequired() || document.readyState === "loading";})()',
            )
            .timeout(const Duration(seconds: 5));
        stable = raw.toString() == 'false' ? stable + 1 : 0;
        if (stable >= 2 && active(epoch)) {
          setState(() => loginRequired = false);
          return true;
        }
      } catch (_) {
        stable = 0;
      }
    }
    if (active(epoch))
      pause(
        'Sign-in was not completed. Finish it on Arogga, then tap Fill / Resume Cart.',
      );
    return false;
  }

  void skipCurrent(String reason) {
    if (mounted) setState(() => skipped[index] = reason);
  }

  // The WebView loadRequest future acknowledges navigation, not page readiness.
  // Check the actual document in the same evaluation as the existing assistant.
  // Never run a cart action on a stale document or an unexpected origin.
  String guardedCartStep(
    String script,
    Map<String, dynamic> request,
    String token,
    bool allowAction,
  ) => '''(() => {
    const medaiGateResult = (status, message) => JSON.stringify({status, message});
    const medaiGateUrl = new URL(window.location.href);
    if (medaiGateUrl.protocol !== 'https:' ||
        !['www.arogga.com', 'arogga.com'].includes(medaiGateUrl.hostname) ||
        (medaiGateUrl.port && medaiGateUrl.port !== '443')) {
      return medaiGateResult('page_wait', 'Waiting for the supplier product page.');
    }
    if (document.readyState === 'loading' || !document.body) {
      return medaiGateResult('page_wait', 'Waiting for the supplier document to load.');
    }
    const medaiGateToken = medaiGateUrl.searchParams.get('_medai_run');
    const medaiGateMatches = medaiGateToken === ${jsonEncode(token)};
    if (medaiGateToken && !medaiGateMatches) {
      return medaiGateResult('page_wait', 'Waiting for the assigned product; the previous page is still visible.');
    }
    if (medaiGateMatches && !${jsonEncode(allowAction)}) {
      return medaiGateResult('page_ready', 'Product page opened; waiting for its controls to settle.');
    }
    try {
      return (() => {
      $script;
      if (!medaiGateMatches) {
        // Login detection is read-only; a supplier redirect may remove the token.
        // Never invoke the cart mutation helper without the assigned token.
        if (medaiLoginRequired()) {
          return medaiGateResult('login_required', 'Supplier sign-in is required.');
        }
        return medaiGateResult('page_wait', 'Waiting for this product URL and navigation token. The supplier may have redirected or removed the token.');
      }
      return JSON.stringify(medaiCartStep(${jsonEncode(request)}));
      })();
    } catch (e) {
      return medaiGateResult('script_error', 'Supplier assistant JavaScript error: ' + (e && e.name ? e.name : 'UnknownError'));
    }
  })()''';

  Future<void> fill() async {
    if (running || !consent) return;
    final epoch = ++generation;
    final runTime = Stopwatch()..start();
    setState(() {
      index = 0;
      confirmed.clear();
      loginSendTried = false;
      skipped.clear();
      running = true;
      status = 'Verifying product and current price…';
    });
    try {
      await retailerReady?.timeout(const Duration(seconds: 7));
      final script = await (cartScript ??= rootBundle.loadString(
        'assets/arogga_assistant.js',
      ));
      if (!active(epoch)) return;
      // Check the visible login panel once before replacing the current page.
      // Subsequent rows detect sign-in via the exact same JS step that checks the product.
      try {
        final raw = await controller
            .runJavaScriptReturningResult(
              '(()=>{$script;return medaiLoginRequired();})()',
            )
            .timeout(const Duration(milliseconds: 650));
        if (raw.toString() == 'true' && !await waitForLogin(script, epoch))
          return;
      } catch (_) {
        /* The preview may still be loading. */
      }
      if (!active(epoch)) return;
      final finished = await processCartQueue(
        widget.rows.length,
        () => active(epoch),
        (item) async {
          if (!active(epoch)) return false;
          setState(() => index = item);
          final q = quote;
          final packs = row['packs'];
          if (packs is! int || packs <= 0 || packs > 100) {
            skipCurrent('Quantity needs supplier review.');
            return true;
          }
          final expiry = int.tryParse('${q['expires_at']}');
          if (expiry == null || expiry <=
              DateTime.now().millisecondsSinceEpoch ~/ 1000) {
            skipCurrent('Price estimate is expired or invalid. Refresh the quote.');
            return true;
          }
          final expected = Uri.tryParse('${q['source_url'] ?? ''}');
          if (expected == null ||
              expected.scheme != 'https' ||
              !['www.arogga.com', 'arogga.com'].contains(expected.host) ||
              expected.userInfo.isNotEmpty ||
              expected.port != 443) {
            skipCurrent('Supplier product link could not be verified.');
            return true;
          }
          var loginInterruptions = 0;
          var navigationRetries = 0;
          var completed = false;
          while (active(epoch) && !completed) {
            // A new URL per attempt forces the visible product to re-read
            // supplier state. A late script from a different attempt cannot click.
            final token =
                '${DateTime.now().microsecondsSinceEpoch}-$epoch-$item-$loginInterruptions-$navigationRetries';
            final target = expected.replace(
              queryParameters: {
                ...expected.queryParameters,
                '_medai_run': token,
              },
            );
            const bridgeWait = Duration(seconds: 7);
            var lastStep = 'Waiting for Arogga to load this product.';
            if (!active(epoch)) return false;
            setState(() {
              progress = 0;
              lastRenderProgress = -1;
              status = 'Opening item ${item + 1} of ${widget.rows.length}…';
            });
            try {
              await controller.loadRequest(target).timeout(bridgeWait);
            } on TimeoutException {
              // The page may still open. Check the assigned URL until the row deadline.
              lastStep = 'Arogga did not acknowledge the page load.';
            } catch (_) {
              if (navigationRetries++ == 0) continue;
              skipCurrent('Could not load the supplier product.');
              break;
            }
            final rowDeadline = DateTime.now().add(const Duration(seconds: 42));
            var interrupted = false;
            final rowTimer = Stopwatch()..start();
            Duration? readySince;
            while (DateTime.now().isBefore(rowDeadline)) {
              var cycleDelay = cartProbeDelay(rowTimer.elapsed);
              if (!active(epoch)) return false;
              try {
                // Allow actions only after the assigned page has been observed
                // ready for a short settling window. Re-check the token inside
                // JavaScript immediately before invoking the existing assistant.
                final allowAction = readySince != null &&
                    rowTimer.elapsed - readySince >=
                        const Duration(milliseconds: 1800);
                final request = <String, dynamic>{
                  ...q,
                  'target_packs': packs,
                  'run_token': token,
                  'deadline_ms': DateTime.now().add(bridgeWait).millisecondsSinceEpoch,
                };
                dynamic decoded = await controller
                    .runJavaScriptReturningResult(
                      guardedCartStep(script, request, token, allowAction),
                    )
                    .timeout(bridgeWait);
                if (decoded is String) decoded = jsonDecode(decoded);
                if (decoded is String) decoded = jsonDecode(decoded);
                final result = Map<String, dynamic>.from(decoded as Map);
                if (!active(epoch)) return false;
                final outcome = result['status'];
                cycleDelay = cartProbeDelay(
                  rowTimer.elapsed,
                  justClicked: outcome == 'clicked',
                );
                lastStep =
                    '${result['message'] ?? 'Checking supplier quantity.'}';
                if (outcome == 'page_wait') {
                  readySince = null;
                } else if (outcome == 'page_ready') {
                  readySince ??= rowTimer.elapsed;
                }
                if (outcome == 'script_error') {
                  // Do not retry a possibly partially executed cart action.
                  // A read-only login probe may safely be tried again.
                  if (allowAction) {
                    skipCurrent(lastStep);
                    completed = true;
                    break;
                  }
                  readySince = null;
                }
                if (outcome == 'ready') {
                  setState(() => confirmed.add(item));
                  completed = true;
                  break;
                }
                if (outcome == 'login_required') {
                  if (++loginInterruptions > 2) {
                    pause(
                      'Arogga sign-in is still required. Complete it before resuming.',
                    );
                    return false;
                  }
                  if (!await waitForLogin(script, epoch)) return false;
                  interrupted = true;
                  break;
                }
                if (outcome == 'blocked') {
                  skipCurrent('Supplier verification blocked: $lastStep');
                  completed = true;
                  break;
                }
                if (outcome == 'manual') {
                  skipCurrent(lastStep);
                  completed = true;
                  break;
                }
                final nextStatus =
                    'Item ${item + 1}/${widget.rows.length}: $lastStep';
                if (status != nextStatus) setState(() => status = nextStatus);
              } on TimeoutException {
                lastStep = 'The supplier view stopped responding. Quantity was not confirmed.';
                // A timed-out mutation may still be in flight. Do not retry it
                // or assume the item was saved; the user can review the cart.
                break;
              } catch (e) {
                // Navigation can briefly make JavaScript unavailable. Keep an
                // actionable error category without logging prescription data.
                if (!active(epoch)) return false;
                readySince = null;
                lastStep = 'Supplier bridge/result error (${e.runtimeType}).';
                final nextStatus = 'Item ${item + 1}/${widget.rows.length}: $lastStep';
                if (status != nextStatus) setState(() => status = nextStatus);
              }
              await Future<void>.delayed(cycleDelay);
            }
            if (!active(epoch)) return false;
            if (interrupted) continue;
            if (!completed) {
              skipCurrent('Timed out. $lastStep');
              completed = true;
            }
          }
          return true;
        },
      );
      if (finished && active(epoch))
        setState(() {
          running = false;
          loginRequired = false;
          status =
              '${confirmed.length}/${widget.rows.length} quantities verified '
              'in ${(runTime.elapsedMilliseconds / 1000).toStringAsFixed(1)}s. '
              '${skipped.isEmpty ? 'Review the supplier cart before checkout.' : '${skipped.length} need review. Open the supplier cart to check what was saved.'}';
        });
    } catch (_) {
      if (active(epoch))
        pause(
          'The supplier session could not be verified. Use the visible Arogga controls or resume.',
        );
    }
  }

  void reviewSkipped() => showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(tr('Items to review on Arogga')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final entry in skipped.entries)
              ListTile(
                title: Text(
                  tr(
                    '${(widget.rows[entry.key]['quote'] as Map)['product_name']}',
                  ),
                ),
                subtitle: Text(tr(entry.value)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: Text(tr('Close'))),
      ],
    ),
  );

  Future<void> openSupplierCart() async {
    try {
      final script = await rootBundle.loadString('assets/arogga_assistant.js');
      if (!mounted || running) return;
      final result = await controller.runJavaScriptReturningResult(
        '(()=>{$script;return medaiOpenSupplierCart();})()',
      );
      if (mounted && !result.toString().contains('opened'))
        pause('Tap the cart icon on the supplier website to review all items.');
    } catch (_) {
      if (mounted) pause('Tap the cart icon on Arogga to continue manually.');
    }
  }

  @override
  Widget build(BuildContext c) => PopScope(
    onPopInvokedWithResult: (didPop, result) {
      if (didPop) generation++;
    },
    child: Scaffold(
      appBar: AppBar(
        title: const Brand(),
        actions: [
          IconButton(
            tooltip: tr('Continue manually in browser'),
            onPressed: running
                ? null
                : () async {
                    final uri = Uri.tryParse(
                      await controller.currentUrl() ?? quote['source_url'],
                    );
                    if (uri != null &&
                        uri.scheme == 'https' &&
                        ['www.arogga.com', 'arogga.com'].contains(uri.host)) {
                      await launchUrl(
                        uri,
                        mode: LaunchMode.externalApplication,
                      );
                    }
                  },
            icon: const Icon(Icons.open_in_new, size: 20),
          ),
          IconButton(
            tooltip: tr('Clear supplier login/session'),
            onPressed: running
                ? null
                : () async {
                    await RetailerSession.clear();
                    if (mounted) {
                      setState(
                        () => status = 'Supplier session cleared. Log in again on Arogga if needed.',
                      );
                      await RetailerSession.prepare(
                        Scope.of(c).userId!,
                        controller,
                      );
                      await controller.reload();
                    }
                  },
            icon: const Icon(Icons.logout, size: 20),
          ),
        ],
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => Column(
            children: [
              SizedBox(
                height: constraints.maxHeight * (loginRequired ? .25 : .36),
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tr(
                                'Arogga · item ${index + 1}/${widget.rows.length}',
                              ),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                            gap(5),
                            small(
                              tr(
                                '${quote['product_name']} · ${row['packs']} pack(s) · ${money(row['line_total_minor'])}',
                              ),
                            ),
                            gap(6),
                            Text(
                              tr(status),
                              style: const TextStyle(
                                fontSize: 11,
                                height: 1.45,
                              ),
                            ),
                            if (!running && !loginRequired)
                              CheckboxListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                value: consent,
                                onChanged: (v) =>
                                    setState(() => consent = v ?? false),
                                title: Text(
                                  tr(
                                    'Allow Med.ai to add only these reviewed products and quantities. I will review checkout and pay manually.',
                                  ),
                                  style: TextStyle(fontSize: 11),
                                ),
                              ),
                            if (!running && profilePhone.isNotEmpty)
                              CheckboxListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                value: useProfilePhone,
                                onChanged: (v) => setState(
                                  () => useProfilePhone = v ?? false,
                                ),
                                title: Text(
                                  tr(
                                    'Use my Med.ai profile number and request an Arogga SMS code',
                                  ),
                                ),
                              ),
                            if (!running && skipped.isNotEmpty)
                              TextButton(
                                onPressed: reviewSkipped,
                                child: Text(
                                  tr(
                                    'Review ${skipped.length} unfinished items',
                                  ),
                                ),
                              ),
                            Row(
                              children: [
                                Expanded(
                                  child: ActionButton(
                                    tr(
                                      running
                                          ? 'Stop Assistant'
                                          : 'Fill / Resume Cart',
                                    ),
                                    onTap: running
                                        ? () => pause(
                                            'Paused. You can use Arogga manually or resume verification.',
                                          )
                                        : consent
                                        ? fill
                                        : null,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  tooltip: tr('Next product (manual)'),
                                  onPressed:
                                      running || index + 1 >= widget.rows.length
                                      ? null
                                      : () {
                                          setState(() => index++);
                                          controller.loadRequest(
                                            Uri.parse(quote['source_url']),
                                          );
                                        },
                                  icon: const Icon(
                                    Icons.skip_next,
                                    color: blue,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (!running && !loginRequired)
                        TextButton.icon(
                          onPressed: openSupplierCart,
                          icon: const Icon(
                            Icons.shopping_cart_outlined,
                            size: 18,
                          ),
                          label: Text(
                            tr('Open Supplier Cart · checkout manually'),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              SizedBox(
                height: 4,
                child: progress < 100
                    ? LinearProgressIndicator(value: progress / 100)
                    : null,
              ),
              Expanded(child: WebViewWidget(controller: controller)),
              if (MediaQuery.sizeOf(c).height > 600)
                Padding(
                  padding: EdgeInsets.all(10),
                  child: Text(
                    tr(
                      'Confirm the SMS code, prescription and order on Arogga. Payment is always manual.',
                    ),
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 10, color: muted),
                  ),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
