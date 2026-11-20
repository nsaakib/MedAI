import '../localization.dart';

import 'dart:async';
import 'dart:ui' as ambulance_ui show Path;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'medai_tracking_map.dart';

import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../design.dart';
import '../models.dart';
import '../services/api.dart';

bool isSosRoute(String? name) {
  if (name == '/ambulance-sos') return true;
  final u = name == null ? null : Uri.tryParse(name);
  return u?.scheme == 'medai' &&
      u?.host == 'sos' &&
      u?.path == '/ambulance-sos';
}

class EmergencySosEntry extends StatelessWidget {
  const EmergencySosEntry({super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 16, bottom: 8),
    child: Material(
      color: const Color(0xff154bb0),
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xff122c70), Color(0xff1458c9), Color(0xff1f74bb)],
          ),
        ),
        child: InkWell(
          onTap: () => go(context, 'ambulance-sos'),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 17, 13, 17),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.emergency_outlined,
                            size: 15,
                            color: Color(0xffbce8ff),
                          ),
                          SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              tr('AMBULANCE SERVICE'),
                              style: TextStyle(
                                color: Color(0xffd1ebff),
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.1,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 7),
                      Text(
                        tr('Emergency Ambulance'),
                        style: TextStyle(
                          fontSize: 19,
                          height: 1.12,
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        tr('Request or track an ambulance'),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: .92),
                          fontSize: 12,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ),
                ),
                if (MediaQuery.sizeOf(context).width >= 345) ...[
                  const SizedBox(width: 6),
                  const ExcludeSemantics(
                    child: SizedBox(
                      width: 95,
                      height: 65,
                      child: CustomPaint(painter: _AmbulanceArtwork()),
                    ),
                  ),
                ],
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.white,
                  size: 21,
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _AmbulanceArtwork extends CustomPainter {
  const _AmbulanceArtwork();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 110, size.height / 76);
    void box(
      double x,
      double y,
      double w,
      double h,
      double radius,
      Color color,
    ) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, w, h),
          Radius.circular(radius),
        ),
        Paint()..color = color,
      );
    }

    void disk(double x, double y, double r, Color color) =>
        canvas.drawCircle(Offset(x, y), r, Paint()..color = color);
    const light = Color(0xffd9f3ff),
        dark = Color(0xff163471),
        sky = Color(0xff5cbbf0);
    disk(58, 37, 37, const Color(0xff3279d2));
    for (final y in [35.0, 44.0, 53.0]) {
      box(0, y, y == 44 ? 16 : 12, 2, 1, const Color(0xff8cd2f6));
    }
    box(15, 61, 90, 5, 2.5, const Color(0xff286abf));
    final body = ambulance_ui.Path()
      ..moveTo(20, 24)
      ..quadraticBezierTo(20, 20, 24, 20)
      ..lineTo(71, 20)
      ..quadraticBezierTo(75, 20, 75, 25)
      ..lineTo(88, 25)
      ..quadraticBezierTo(92, 25, 94, 30)
      ..lineTo(102, 43)
      ..lineTo(104, 45)
      ..lineTo(104, 58)
      ..quadraticBezierTo(104, 61, 101, 61)
      ..lineTo(24, 61)
      ..quadraticBezierTo(20, 61, 20, 57)
      ..close();
    canvas.drawPath(body, Paint()..color = light);
    box(20, 49, 84, 5, 1, sky);
    box(47, 14, 17, 6, 3, sky);
    box(52, 13, 7, 3, 1.5, light);
    final window = ambulance_ui.Path()
      ..moveTo(78, 30)
      ..lineTo(88, 30)
      ..lineTo(97, 43)
      ..lineTo(78, 43)
      ..close();
    canvas.drawPath(window, Paint()..color = const Color(0xff2265b1));
    box(39, 30, 6, 17, 2, const Color(0xff2671cb));
    box(33.5, 35.5, 17, 6, 2, const Color(0xff2671cb));
    for (final x in [35.0, 87.0]) {
      disk(x, 60, 8.5, dark);
      disk(x, 60, 3.6, light);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _AmbulanceArtwork oldDelegate) => false;
}

class EmergencySosLive extends StatefulWidget {
  const EmergencySosLive({super.key});
  @override
  State<EmergencySosLive> createState() => _EmergencySosLiveState();
}

class _EmergencySosLiveState extends State<EmergencySosLive> {
  static const _voice = MethodChannel('medai/voice');
  final phone = TextEditingController(),
      address = TextEditingController(),
      notes = TextEditingController(),
      lat = TextEditingController(),
      lng = TextEditingController();
  final equipment = <String>{};
  bool enabled = false,
      loaded = false,
      gps = false,
      sending = false,
      refreshing = false,
      voice = false,
      consent = false,
      editing = false;
  double? accuracy;
  String? advisory, account, category;
  Map<String, dynamic>? draft, request;
  List<Map<String, dynamic>> near = [];
  Timer? timer;
  int availabilityVersion = 0;
  int requestVersion = 0;
  String? mapTiles, mapCredit;
  static const limit = Duration(seconds: 7);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final s = Scope.of(context);
    if (!loaded || account != s.userId) {
      account = s.userId;
      loaded = true;
      enabled = false;
      lastRefreshed = null;
      refreshFailed = false;
      sandbox = configResolved = false;
      mapTiles = mapCredit = null;
      request = draft = null;
      near = [];
      phone.text = s.phone;
      address.clear();
      notes.clear();
      lat.clear();
      lng.clear();
      equipment.clear();
      category = null;
      consent = false;
      accuracy = null;
      sending = false;
      advisory = null;
      timer ??= Timer.periodic(const Duration(seconds: 5), (_) {
        if (mounted) refresh();
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) refresh();
      });
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    for (final field in [phone, address, notes, lat, lng]) {
      field.dispose();
    }
    super.dispose();
  }

  bool sandbox = false;
  bool configResolved = false;

  bool active(String? state) => [
    'queued',
    'awaiting_driver',
    'dispatched',
    'en_route',
    'arrived',
    'cancel_requested',
  ].contains(state);

  DateTime? lastRefreshed;
  bool refreshFailed = false;

  Future<void> refresh({bool manual = false}) async {
    if (!mounted || refreshing || sending) return;
    setState(() => refreshing = true);
    final s = Scope.of(context), owner = account, version = requestVersion;
    try {
      final config =
          await s.api.request('GET', '/sos/config').timeout(limit) as Map;
      if (!mounted || owner != account) return;
      setState(() {
        if (!configResolved && config['mode'] == 'sandbox')
          phone.text = '01700000000';
        sandbox = config['mode'] == 'sandbox';
        configResolved = true;
        enabled = config['enabled'] == true;
        final configMap = config['map'];
        mapTiles = configMap is Map ? configMap['tiles'] as String? : null;
        mapCredit = configMap is Map
            ? configMap['attribution'] as String?
            : null;
      });
      final rows = !s.signedIn
          ? const []
          : await s.api.request('GET', '/sos/requests').timeout(limit) as List;
      if (!mounted || owner != account || sending || version != requestVersion)
        return;
      setState(() {
        request = rows.isEmpty
            ? null
            : Map<String, dynamic>.from(rows.first as Map);
        lastRefreshed = DateTime.now();
        refreshFailed = false;
        if (draft != null && active(request?['status'] as String?))
          draft = null;
        if (draft == null) advisory = null;
      });
      if (manual &&
          enabled &&
          point != null &&
          !active(request?['status'] as String?)) {
        await nearby();
      }
      if (manual && mounted && owner == account) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tr(
                enabled
                    ? 'Status updated from the server.'
                    : 'Status checked: live dispatch is disabled on this server. Refresh does not enable it.',
              ),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted && owner == account && version == requestVersion) {
        setState(() {
          refreshFailed = true;
          advisory = e is ApiError && e.status == 401
              ? 'Sign in again to refresh your ambulance requests.'
              : e is ApiError && e.status == 403
              ? 'The server refused dispatch access. Ask the server owner to check the HTTPS proxy configuration.'
              : 'Status could not be refreshed. Check your connection and sign-in, then retry. The last request status may be stale.';
        });
      }
    } finally {
      if (mounted) setState(() => refreshing = false);
    }
  }

  Future<void> dial(String number) async {
    final safe = number.replaceAll(RegExp(r'[^+0-9]'), '');
    try {
      if (safe.isNotEmpty && await launchUrl(Uri(scheme: 'tel', path: safe)))
        return;
    } catch (_) {}
    if (mounted)
      message(context, tr('Use your phone dialer'), tr('Dial ' + number + '.'));
  }

  Map<String, dynamic>? get point {
    final a = double.tryParse(lat.text), b = double.tryParse(lng.text);
    if (a == null ||
        b == null ||
        !a.isFinite ||
        !b.isFinite ||
        a.abs() > 90 ||
        b.abs() > 180)
      return null;
    return {'lat': a, 'lng': b, if (accuracy != null) 'accuracy': accuracy};
  }

  void setPin(LatLng pin, [double? precision]) {
    if (!mounted) return;
    setState(() {
      lat.text = pin.latitude.toStringAsFixed(6);
      lng.text = pin.longitude.toStringAsFixed(6);
      accuracy = precision;
      near = [];
    });
  }

  Future<void> locate() async {
    if (gps || draft != null || sending) return;
    setState(() {
      gps = true;
      advisory = null;
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled())
        throw StateError('GPS is off.');
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied)
        permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw StateError('Location denied.');
      }
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      setPin(
        LatLng(p.latitude, p.longitude),
        p.accuracy.clamp(0, 20000).toDouble(),
      );
    } catch (_) {
      if (mounted)
        setState(() {
          editing = true;
          advisory =
              'GPS unavailable. Enter coordinates from a known pickup pin or call 999.';
        });
    } finally {
      if (mounted) setState(() => gps = false);
    }
  }

  Future<void> nearby() async {
    final p = point;
    if (p == null || !consent) {
      message(
        context,
        tr('Check pickup'),
        tr('Set your pickup coordinates and allow location sharing first.'),
      );
      return;
    }
    final owner = account;
    final filters = ({...p}, equipment.toList()..sort(), category);
    final int version = ++availabilityVersion;
    try {
      final result =
          await Scope.of(context).api
                  .request('POST', '/sos/nearby', {
                    ...p,
                    'equipment': equipment.toList(),
                    'category': category,
                  })
                  .timeout(limit)
              as List;
      if (!mounted ||
          owner != account ||
          !consent ||
          version != availabilityVersion ||
          point.toString() != filters.$1.toString() ||
          (equipment.toList()..sort()).join(',') != filters.$2.join(',') ||
          category != filters.$3)
        return;
      setState(
        () => near = result
            .map((r) => Map<String, dynamic>.from(r as Map))
            .toList(),
      );
      if (near.isEmpty)
        message(
          context,
          tr('No verified partner online nearby'),
          tr('No ambulance is confirmed.'),
        );
    } catch (_) {
      if (mounted && owner == account)
        message(
          context,
          tr('Availability not confirmed'),
          tr('Call 999 if you need urgent help.'),
        );
    }
  }

  Future<void> speak() async {
    if (voice || sending) return;
    setState(() => voice = true);
    try {
      final language = await showModalBottomSheet<String>(
        context: context,
        builder: (c) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(tr('Speak an ambulance request')),
                subtitle: Text(
                  tr(
                    'Your Android speech provider may process audio online. This shortcut only listens when opened.',
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
      if (!mounted || language == null) return;
      final command =
          (await _voice.invokeMethod<String>(
            'dictate',
            language,
          ))?.toLowerCase() ??
          '';
      if (!mounted) return;
      if (!RegExp(
            r'\bambulance\b|অ্যাম্বুলেন্স|এম্বুলেন্স',
          ).hasMatch(command) ||
          RegExp(r'\b(cancel|not|don.t)\b|বাতিল|না\b').hasMatch(command)) {
        message(
          context,
          tr('No request sent'),
          tr('Say you need an ambulance, or use the request button.'),
        );
        return;
      }
      if (point == null) await locate();
      if (mounted) await confirmRequest(voiceLocale: language);
    } catch (_) {
      if (mounted)
        message(
          context,
          tr('Voice unavailable'),
          tr('Use the manual request button or call 999.'),
        );
    } finally {
      if (mounted) setState(() => voice = false);
    }
  }

  Future<void> confirmRequest({String? voiceLocale}) async {
    if (gps || sending) return;
    if (draft != null) {
      await submit();
      return;
    }
    if (!enabled || !Scope.of(context).signedIn) return;
    if (point == null) await locate();
    if (!mounted) return;
    final p = point, number = phone.text.replaceAll(RegExp(r'\s+'), '');
    if (p == null ||
        !consent ||
        !RegExp(r'^(?:\+?88)?01[3-9][0-9]{8}$').hasMatch(number)) {
      message(
        context,
        tr('Check pickup details'),
        tr(
          'Add a pickup location, valid Bangladesh mobile number, and sharing consent.',
        ),
      );
      return;
    }
    final owner = account;
    final yes = voiceLocale == null
        ? true
        : await showDialog<bool>(
            context: context,
            builder: (c) => AlertDialog(
              title: Text(tr('Confirm ambulance request')),
              content: Text(
                tr(
                  'Share your pickup location, phone and optional details with the selected partner. A request does not confirm dispatch.',
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(c, false),
                  child: Text(tr('Cancel')),
                ),
                if (voiceLocale != null)
                  TextButton(
                    onPressed: () async {
                      try {
                        final answer = (await _voice.invokeMethod<String>(
                          'dictate',
                          voiceLocale,
                        ))?.toLowerCase().trim();
                        if (!c.mounted) return;
                        final ok =
                            answer == 'confirm ambulance' ||
                            answer == 'অ্যাম্বুলেন্স নিশ্চিত করুন';
                        if (ok) {
                          Navigator.pop(c, true);
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                tr(
                                  'Not confirmed. Say “confirm ambulance” or tap Send request.',
                                ),
                              ),
                            ),
                          );
                        }
                      } catch (_) {
                        if (c.mounted)
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                tr(
                                  'Voice confirmation unavailable. Use Send request.',
                                ),
                              ),
                            ),
                          );
                      }
                    },
                    child: Text(tr('Confirm by voice')),
                  ),
                FilledButton(
                  onPressed: () => Navigator.pop(c, true),
                  child: Text(tr('Send request')),
                ),
              ],
            ),
          );
    if (!mounted ||
        owner != account ||
        yes != true ||
        sending ||
        !Scope.of(context).signedIn)
      return;
    draft = {
      ...p,
      'phone': number,
      'address': address.text.trim(),
      'note': notes.text.trim(),
      'equipment': equipment.toList(),
      'category': category,
      'consent': true,
      'allow_reroute': true,
      'request_key': identifier(),
    };
    await submit();
  }

  Future<void> submit() async {
    final body = draft;
    if (body == null || sending) return;
    final owner = account;
    requestVersion++;
    setState(() {
      sending = true;
      advisory = null;
    });
    try {
      final response =
          await Scope.of(
                context,
              ).api.request('POST', '/sos/requests', body).timeout(limit)
              as Map;

      if (mounted && owner == account) {
        setState(() {
          request = Map<String, dynamic>.from(response);
          draft = null;
        });
        if (response['status'] == 'no_coverage') {
          message(
            context,
            tr('No ambulance confirmed'),
            tr(coverageMessage(response['reason'] as String?)),
          );
        }
      }
    } catch (e) {
      if (mounted && owner == account)
        setState(() {
          if (e is ApiError && e.status >= 400 && e.status < 500) draft = null;
          advisory = draft == null
              ? '$e'
              : 'Receipt unconfirmed. Retry the same request or refresh status. For urgent help, call 999.';
        });
    } finally {
      if (mounted && owner == account) setState(() => sending = false);
    }
  }

  Future<void> cancel() async {
    final key = request?['id'], owner = account;
    if (key == null || sending) return;
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(tr('Cancel the request?')),
        content: Text(
          tr('An accepted assignment requires confirmation from the partner.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(tr('Keep request')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(tr('Request cancellation')),
          ),
        ],
      ),
    );
    if (!mounted || yes != true || owner != account || sending) return;
    requestVersion++;
    setState(() => sending = true);
    try {
      final updated =
          await Scope.of(context).api
                  .request('POST', '/sos/requests/$key/cancel', {})
                  .timeout(limit)
              as Map;
      if (mounted && owner == account)
        setState(() => request = Map<String, dynamic>.from(updated));
    } catch (_) {
      if (mounted && owner == account)
        setState(
          () => advisory =
              'Cancellation unconfirmed. Contact the center directly.',
        );
    } finally {
      if (mounted && owner == account) setState(() => sending = false);
    }
  }

  String coverageMessage(String? reason) => switch (reason) {
    'equipment_or_category_unavailable' =>
      'No nearby vehicle meets the requested category and equipment. Review the selected category, and keep any equipment you need.',
    'matching_vehicles_busy' =>
      'The matching vehicles are busy, offline, or already needed for another request.',
    'no_staffed_partner' =>
      sandbox
          ? 'No test operator is online within range. Open the operator dashboard and check the pickup location.'
          : 'No staffed partner was reachable within the pickup area.',
    'partners_exhausted' =>
      'No matching partner was able to confirm this request.',
    _ =>
      'The request ended without an accepted assignment. Check nearby partners before trying a new request.',
  };

  String describe(String? state) =>
      const {
        'queued': 'Request received · waiting for an operator',
        'awaiting_driver': 'Vehicle reserved · waiting for driver acceptance',
        'dispatched': 'Driver accepted · dispatch confirmed',
        'en_route': 'On the way',
        'arrived': 'At pickup location',
        'no_coverage': 'No ambulance confirmed',
        'cancel_requested': 'Partner confirmation of cancellation pending',
        'cancelled': 'Cancelled',
        'completed': 'Trip completed',
      }[state] ??
      'Status not confirmed';

  String gpsAge(Object? value) {
    if (value is! int) return 'time unavailable';
    final age = ((DateTime.now().millisecondsSinceEpoch ~/ 1000) - value).clamp(
      0,
      86400,
    );
    return '${age}s ago';
  }

  LatLng modelPoint(Map p) =>
      LatLng((p['lat'] as num).toDouble(), (p['lng'] as num).toDouble());

  @override
  Widget build(BuildContext context) {
    final s = Scope.of(context), p = point;
    final state = request?['status'] as String?;
    final frozen = sending || draft != null || active(state);
    final org = request?['org'] as Map?, trip = request?['assignment'] as Map?;
    final driver = trip?['driver'] as Map?, vehicle = trip?['location'] as Map?;
    final pickup = active(state) ? (request?['pickup'] as Map?) : p;
    return AppFrame(
      back: true,
      title: tr('Emergency Ambulance'),
      subtitle: tr(
        sandbox
            ? 'Test a request with a test partner.'
            : 'Request help through a verified Med.ai partner.',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!sandbox) ...[
            ActionButton(
              tr('Call 999'),
              icon: Icons.call,
              onTap: () => dial('999'),
            ),
            gap(8),
            note(
              tr(
                'For urgent help in Bangladesh, call 999. Do not wait for an unanswered app request.',
              ),
            ),
          ],
          if (sandbox)
            note(
              tr(
                'LOCAL SANDBOX · Use fictional details only. No real ambulance, calls or SMS.',
              ),
            ),
          if (!configResolved && advisory == null)
            note(tr('Checking partner dispatch availability…')),
          if (advisory != null) note(tr(advisory!)),
          if (request != null)
            Tile(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr(describe(state)),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  if (state == 'no_coverage')
                    Text(tr(coverageMessage(request?['reason'] as String?))),
                  if (state == 'queued' && request?['rerouted'] == true)
                    Text(
                      tr(
                        'Another matching partner is reviewing your request. No ambulance is confirmed yet.',
                      ),
                    ),
                  if (state == 'no_coverage' && !sandbox)
                    Text(
                      tr(
                        'Do not wait for this request if you need urgent help.',
                      ),
                    ),
                  small(tr('Request: ' + request!['id'].toString())),
                  if (org != null) ...[
                    Text(tr(org['name'].toString())),
                    if (!sandbox)
                      TextButton(
                        onPressed: () => dial(org['phone'].toString()),
                        child: Text(tr('Call center')),
                      ),
                  ],
                  if (trip != null)
                    Text(tr('Ambulance: ' + trip['ambulance_id'].toString())),
                  if (driver != null && !sandbox)
                    TextButton(
                      onPressed: () => dial(driver['phone'].toString()),
                      child: Text(
                        tr('Call driver: ' + driver['name'].toString()),
                      ),
                    ),
                  if (trip != null)
                    small(
                      tr(
                        vehicle == null
                            ? 'Live position unavailable. The driver may not be sharing or the last update expired.'
                            : 'Ambulance GPS · last received ${gpsAge(trip['location_recorded'])} · no road ETA.',
                      ),
                    ),
                  if (active(state) && state != 'cancel_requested')
                    TextButton(
                      onPressed: sending ? null : cancel,
                      child: Text(tr('Cancel request')),
                    ),
                ],
              ),
            ),
          if (!s.signedIn)
            TextButton(
              onPressed: () => go(context, 'login'),
              child: Text(tr('Sign in for partner dispatch')),
            )
          else if (configResolved && !enabled && !active(state))
            note(
              tr(
                'Live partner dispatch has not been enabled on this server. For urgent help, call 999.',
              ),
            ),
          if (configResolved && !enabled && !active(state)) ...[
            Text(
              tr(
                'The server owner must configure verified partners and fleet access before enabling live requests. For fictional testing, start the separate sandbox server.',
              ),
            ),
            TextButton.icon(
              icon: const Icon(Icons.local_hospital_outlined),
              label: Text(tr('Open Partner Operations')),
              onPressed: () async {
                final uri = Uri.parse('${Api.baseUrl}/sos/portal');
                try {
                  if (!await launchUrl(
                    uri,
                    mode: LaunchMode.externalApplication,
                  )) {
                    throw StateError('Could not open partner operations.');
                  }
                } catch (_) {
                  if (mounted)
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          tr(
                            'Could not open Partner Operations. Check your connection.',
                          ),
                        ),
                      ),
                    );
                }
              },
            ),
          ],
          if (enabled && s.signedIn && !active(state)) ...[
            TextField(
              controller: phone,
              enabled: !frozen,
              maxLength: 20,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: tr('Pickup contact number'),
              ),
            ),
            TextField(
              controller: address,
              enabled: !frozen,
              maxLength: 220,
              decoration: InputDecoration(
                labelText: tr('Address or landmark (optional)'),
              ),
            ),
            TextField(
              controller: notes,
              enabled: !frozen,
              maxLength: 350,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: tr('Emergency details (optional)'),
              ),
            ),
            DropdownButtonFormField<String>(
              initialValue: category ?? '',
              decoration: InputDecoration(
                labelText: tr('Known ambulance category (optional)'),
              ),
              items: [
                DropdownMenuItem(value: '', child: Text(tr('No preference'))),
                DropdownMenuItem(value: 'basic', child: Text(tr('Basic'))),
                DropdownMenuItem(
                  value: 'advanced',
                  child: Text(tr('Advanced')),
                ),
                DropdownMenuItem(
                  value: 'neonatal',
                  child: Text(tr('Neonatal')),
                ),
              ],
              onChanged: frozen
                  ? null
                  : (v) => setState(() {
                      category = v == '' ? null : v;
                      near = [];
                    }),
            ),
            Text(tr('Known equipment needs (optional)')),
            Wrap(
              children: [
                for (final item in [
                  'oxygen',
                  'stretcher',
                  'monitor',
                  'ventilator',
                  'neonatal',
                ])
                  FilterChip(
                    label: Text(tr(item)),
                    selected: equipment.contains(item),
                    onSelected: frozen
                        ? null
                        : (yes) => setState(() {
                            if (yes) {
                              equipment.add(item);
                            } else {
                              equipment.remove(item);
                            }
                            near = [];
                          }),
                  ),
              ],
            ),
            TextButton.icon(
              onPressed: frozen || gps ? null : locate,
              icon: const Icon(Icons.my_location),
              label: Text(tr(gps ? 'Getting GPS…' : 'Use my GPS location')),
            ),
            TextButton(
              onPressed: frozen
                  ? null
                  : () => setState(() => editing = !editing),
              child: Text(tr('Enter or correct pickup coordinates')),
            ),
            if (editing)
              for (final item in [(lat, 'Latitude'), (lng, 'Longitude')])
                TextField(
                  controller: item.$1,
                  enabled: !frozen,
                  keyboardType: const TextInputType.numberWithOptions(
                    signed: true,
                    decimal: true,
                  ),
                  onChanged: (_) => setState(() {
                    accuracy = null;
                    near = [];
                  }),
                  decoration: InputDecoration(labelText: tr(item.$2)),
                ),
            if (p != null)
              Text(
                tr(
                  'Pickup: ' +
                      lat.text +
                      ', ' +
                      lng.text +
                      (accuracy == null
                          ? ''
                          : ' · ±' + accuracy!.round().toString() + ' m'),
                ),
              ),
            if (accuracy != null && accuracy! > 100)
              note(
                tr(
                  'GPS precision is low. Check the pin or correct the coordinates.',
                ),
              ),
            CheckboxListTile(
              value: consent,
              onChanged: frozen
                  ? null
                  : (v) => setState(() => consent = v ?? false),
              title: Text(
                tr('Allow sharing pickup details with a matching partner'),
              ),
              subtitle: Text(
                tr(
                  'One partner at a time. If they cannot respond, another matching partner may receive the request.',
                ),
              ),
            ),
            TextButton(
              onPressed: frozen ? null : nearby,
              child: Text(tr('Check nearby partners')),
            ),
            for (final entry in near)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(tr(entry['name'].toString())),
                subtitle: Text(
                  tr(
                    '${entry['distance_km']} km straight-line · '
                    '${entry['compatible_fleet'] == 0 ? 'No vehicle matches this category and equipment' : '${entry['dispatch_slots'] ?? entry['reported_available']} matching dispatch slots'}',
                  ),
                ),
              ),
            if (sending) const LinearProgressIndicator(),
            ActionButton(
              tr(
                sending
                    ? 'Submitting request…'
                    : draft != null
                    ? 'Retry same request'
                    : 'Request ambulance',
              ),
              icon: Icons.emergency_outlined,
              onTap: sending || gps || voice ? null : confirmRequest,
            ),
            TextButton.icon(
              onPressed: frozen || voice ? null : speak,
              icon: const Icon(Icons.mic_none),
              label: Text(tr('Speak an ambulance request')),
            ),
          ],
          if (pickup != null) ...[
            gap(12),
            Text(
              tr(
                vehicle == null
                    ? 'Pickup location'
                    : 'Pickup and ambulance location',
              ),
            ),
            MedAiTrackingMap(
              pickup: modelPoint(pickup),
              vehicle: vehicle == null ? null : modelPoint(vehicle),
              accuracy: (pickup['accuracy'] as num?)?.toDouble(),
              tiles: mapTiles,
              credit: mapCredit,
              onPickupChanged: frozen ? null : (pin) => setPin(pin),
            ),
            if (!frozen) small(tr('Tap the map to adjust the pickup pin.')),
          ],
          TextButton.icon(
            onPressed: sending || refreshing
                ? null
                : () => refresh(manual: true),
            icon: refreshing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            label: Text(tr(refreshing ? 'Refreshing…' : 'Refresh status')),
          ),
          if (lastRefreshed != null && !refreshFailed)
            Text(
              tr(
                'Last checked: ${TimeOfDay.fromDateTime(lastRefreshed!).format(context)}',
              ),
            ),
        ],
      ),
    );
  }
}
