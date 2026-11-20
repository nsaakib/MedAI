import '../localization.dart';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' show LatLng;

class MedAiTrackingMap extends StatefulWidget {
  const MedAiTrackingMap({
    super.key,
    required this.pickup,
    this.vehicle,
    this.tiles,
    this.credit,
    this.onPickupChanged,
    this.accuracy,
  });
  final LatLng pickup;
  final LatLng? vehicle;
  final String? tiles, credit;
  final ValueChanged<LatLng>? onPickupChanged;
  final double? accuracy;

  @override
  State<MedAiTrackingMap> createState() => _MedAiTrackingMapState();
}

class _MedAiTrackingMapState extends State<MedAiTrackingMap> {
  final map = MapController();
  bool ready = false, follow = true;

  @override
  void didUpdateWidget(covariant MedAiTrackingMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pickup != widget.pickup ||
        (follow &&
            oldWidget.vehicle != widget.vehicle &&
            widget.vehicle != null)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && ready)
          map.move(widget.vehicle ?? widget.pickup, map.camera.zoom);
      });
    }
  }

  @override
  void dispose() {
    map.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vehicle = widget.vehicle;
    final tiles = widget.tiles;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 248,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: FlutterMap(
              mapController: map,
              options: MapOptions(
                initialCenter: vehicle ?? widget.pickup,
                initialZoom: 15,
                onMapReady: () => ready = true,
                onTap: widget.onPickupChanged == null
                    ? null
                    : (_, point) => widget.onPickupChanged!(point),
                onPositionChanged: (_, gesture) {
                  if (gesture && vehicle != null && follow)
                    setState(() => follow = false);
                },
              ),
              children: [
                if (tiles != null)
                  TileLayer(
                    urlTemplate: tiles,
                    userAgentPackageName: 'Med.ai',
                    maxNativeZoom: 18,
                  ),
                if (widget.accuracy != null && widget.accuracy! > 0)
                  CircleLayer(
                    circles: [
                      CircleMarker(
                        point: widget.pickup,
                        radius: widget.accuracy!.clamp(1, 2000).toDouble(),
                        useRadiusInMeter: true,
                        color: const Color(0x242357c4),
                        borderColor: const Color(0x802357c4),
                        borderStrokeWidth: 1,
                      ),
                    ],
                  ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: widget.pickup,
                      width: 38,
                      height: 38,
                      child: const Tooltip(
                        message: 'Pickup location',
                        child: Icon(
                          Icons.location_pin,
                          size: 36,
                          color: Color(0xff123670),
                        ),
                      ),
                    ),
                    if (vehicle != null)
                      Marker(
                        point: vehicle,
                        width: 40,
                        height: 40,
                        child: const Tooltip(
                          message: 'Ambulance last reported location',
                          child: Material(
                            color: Color(0xff1460c2),
                            shape: CircleBorder(),
                            child: Icon(
                              Icons.airport_shuttle,
                              color: Colors.white,
                              size: 25,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (widget.credit != null && tiles != null)
          Text(
            tr(widget.credit!),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        if (tiles == null)
          Text(
            tr(
              'Street map is not configured. GPS markers still show the relative positions.',
            ),
          ),
        if (vehicle != null)
          TextButton.icon(
            onPressed: () {
              if (!ready) return;
              setState(() => follow = true);
              map.move(vehicle, map.camera.zoom);
            },
            icon: const Icon(Icons.my_location),
            label: Text(
              tr(follow ? 'Center on ambulance' : 'Resume following ambulance'),
            ),
          ),
      ],
    );
  }
}
