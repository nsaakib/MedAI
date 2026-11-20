import '../localization.dart';

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../design.dart';
import '../models.dart';
import '../motion.dart';

class PharmaciesLive extends StatefulWidget {
  const PharmaciesLive({super.key});
  @override
  State<PharmaciesLive> createState() => _PharmaciesLiveState();
}

class _PharmaciesLiveState extends State<PharmaciesLive> {
  LatLng? position;
  List<Map<String, dynamic>> pharmacies = [];
  bool busy = false;
  String? error;
  final area = TextEditingController();
  int radius = 3000;
  @override
  void dispose() {
    area.dispose();
    super.dispose();
  }

  Future<void> locate() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled())
        throw StateError(
          'Turn on location services, or search an area in Google Maps below.',
        );
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied)
        permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever)
        throw StateError(
          'Location permission is unavailable. Enable it in settings, or search an area below.',
        );
      Position p;
      try {
        p = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 45),
          ),
        );
      } on TimeoutException {
        final cached = await Geolocator.getLastKnownPosition();
        final age = cached == null
            ? const Duration(days: 1)
            : DateTime.now().difference(cached.timestamp);
        if (cached == null ||
            age.isNegative ||
            age > const Duration(minutes: 5) ||
            cached.accuracy > 300) {
          throw StateError(
            'Could not obtain your location. Enable Precise location and Google Location Accuracy, then retry outdoors or use the area search below.',
          );
        }
        if (!mounted) return;
        final use = await showDialog<bool>(
          context: context,
          builder: (d) => AlertDialog(
            title: Text(tr('Use recent location?')),
            content: Text(
              tr(
                'Location is ${age.inMinutes} minute(s) old, estimated accuracy ${cached.accuracy.round()} m. Search around it?',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(d, false),
                child: Text(tr('Cancel')),
              ),
              TextButton(
                onPressed: () => Navigator.pop(d, true),
                child: Text(tr('Use location')),
              ),
            ],
          ),
        );
        if (use != true) return;
        p = cached;
      }
      if (!mounted) return;
      final data = await Scope.of(context).api.request(
        'POST',
        '/pharmacies/nearby',
        {'latitude': p.latitude, 'longitude': p.longitude, 'radius_m': radius},
      );
      if (mounted)
        setState(() {
          position = LatLng(p.latitude, p.longitude);
          pharmacies = (data['items'] as List)
              .map((i) => Map<String, dynamic>.from(i))
              .toList();
        });
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> maps([Map<String, dynamic>? pharmacy]) async {
    final query = pharmacy == null
        ? 'pharmacies near ${area.text.trim().isEmpty ? 'me' : area.text.trim()}'
        : '${pharmacy['latitude']},${pharmacy['longitude']}';
    final uri = pharmacy == null
        ? Uri.https('www.google.com', '/maps/search/', {
            'api': '1',
            'query': query,
          })
        : Uri.https('www.google.com', '/maps/dir/', {
            'api': '1',
            'destination': query,
          });
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication) && mounted)
      message(
        context,
        tr('Could not open maps'),
        tr('Open Google Maps and search for pharmacies in your area.'),
      );
  }

  @override
  Widget build(BuildContext c) => AppFrame(
    back: true,
    title: tr('Nearby Pharmacies'),
    subtitle: tr('Choose a nearby pharmacy for an in-person purchase.'),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        note(
          tr(
            'Use your location to show mapped pharmacies. Location is sent only for this search, not saved to your patient record. Listings do not confirm medicine stock.',
          ),
          color: blue,
        ),
        DropdownButtonFormField<int>(
          initialValue: radius,
          decoration: InputDecoration(labelText: tr('Search radius')),
          items: [
            DropdownMenuItem(value: 1000, child: Text(tr('Within 1 km'))),
            DropdownMenuItem(value: 3000, child: Text(tr('Within 3 km'))),
            DropdownMenuItem(value: 5000, child: Text(tr('Within 5 km'))),
          ],
          onChanged: busy ? null : (v) => setState(() => radius = v!),
        ),
        gap(12),
        ActionButton(
          tr('Find Near My Location'),
          icon: Icons.my_location,
          onTap: busy ? null : locate,
        ),
        if (busy)
          const Padding(
            padding: EdgeInsets.all(25),
            child: Center(child: MedLoader(label: 'Finding pharmacies…')),
          ),
        if (error != null) ...[
          gap(12),
          note(tr(error!)),
          TextButton(
            onPressed: Geolocator.openAppSettings,
            child: Text(tr('Open location permissions')),
          ),
        ],
        TextButton(
          onPressed: Geolocator.openLocationSettings,
          child: Text(tr('Open location service settings')),
        ),
        if (position != null) ...[
          gap(16),
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: SizedBox(
              height: 280,
              child: FlutterMap(
                key: ValueKey(
                  '${position!.latitude}/${position!.longitude}/$radius',
                ),
                options: MapOptions(initialCenter: position!, initialZoom: 14),
                children: [
                  TileLayer(
                    urlTemplate: const String.fromEnvironment(
                      'MAP_TILE_URL',
                      defaultValue:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    ),
                    userAgentPackageName: 'bd.medai.patient',
                  ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: position!,
                        width: 28,
                        height: 28,
                        child: const Icon(
                          Icons.my_location,
                          color: blue,
                          size: 25,
                        ),
                      ),
                      for (final p in pharmacies)
                        Marker(
                          point: LatLng(
                            (p['latitude'] as num).toDouble(),
                            (p['longitude'] as num).toDouble(),
                          ),
                          width: 38,
                          height: 38,
                          child: GestureDetector(
                            onTap: () => maps(p),
                            child: const Icon(
                              Icons.local_pharmacy,
                              color: purple,
                              size: 30,
                            ),
                          ),
                        ),
                    ],
                  ),
                  Align(
                    alignment: Alignment.bottomRight,
                    child: Material(
                      color: Colors.white,
                      child: InkWell(
                        onTap: () => launchUrl(
                          Uri.parse('https://www.openstreetmap.org/copyright'),
                          mode: LaunchMode.externalApplication,
                        ),
                        child: Padding(
                          padding: EdgeInsets.all(5),
                          child: Text(
                            tr('© OpenStreetMap contributors'),
                            style: TextStyle(fontSize: 10),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          gap(14),
          Heading(tr('${pharmacies.length} mapped pharmacies')),
          if (pharmacies.isEmpty)
            note(
              tr(
                'No pharmacies were mapped in this search area. Coverage may be incomplete; try Google Maps below.',
              ),
              color: blue,
            ),
          for (final p in pharmacies)
            Tile(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr(p['name']),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  gap(6),
                  small(
                    tr(
                      '${((p['distance_m'] as int) / 1000).toStringAsFixed(1)} km · ${p['address'].toString().isEmpty ? 'Address not mapped' : p['address']}',
                    ),
                  ),
                  if (p['opening_hours'] != null)
                    small(tr('Reported hours: ${p['opening_hours']}')),
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: () => maps(p),
                        icon: const Icon(Icons.directions_outlined, size: 18),
                        label: Text(tr('Directions')),
                      ),
                      if (p['phone'] != null)
                        TextButton.icon(
                          onPressed: () =>
                              launchUrl(Uri(scheme: 'tel', path: p['phone'])),
                          icon: const Icon(Icons.call_outlined, size: 18),
                          label: Text(tr('Call')),
                        ),
                    ],
                  ),
                ],
              ),
            ),
        ],
        gap(16),
        Heading(tr('Search another area')),
        TextField(
          controller: area,
          decoration: InputDecoration(
            labelText: tr('City or neighbourhood (optional)'),
          ),
        ),
        gap(12),
        ActionButton(
          tr('Open Google Maps'),
          icon: Icons.map_outlined,
          onTap: () => maps(),
        ),
      ],
    ),
  );
}
