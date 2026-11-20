# Pharmacy map

The native app requests foreground location only when the user selects Find Near My Location. It sends coordinates/radius to the authenticated Med.ai backend, which performs a bounded OpenStreetMap Overpass query for pharmacy tags. Searches are cached in memory on roughly 100m coordinate cells for 15 minutes. Coordinates are not added to patient records or application audit logs. The displayed distance is approximate straight-line distance; directions are opened separately in Google Maps.

The embedded map uses flutter_map with an identifying app user agent, visible OpenStreetMap attribution and the package's network tile cache. No bulk/offline tile download is implemented. Public OpenStreetMap/Overpass services can be limited or unavailable and are not a guaranteed production hosting service. Choose a suitable map/tile/query provider for deployment scale. The tile URL can be configured with `MAP_TILE_URL`; preserve the provider's attribution requirements when changing it.

Location denial, no mapped results and source failures are explicit UI states. The external Google Maps search accepts a city/neighbourhood and works without giving this app GPS access; it does not require a Google Maps API key. Neither map source verifies pharmacy licensing, opening-now status, stock, exact prices or medicine availability. Reported hours/phone numbers are shown only when supplied by OSM; call to confirm before travelling.

Primary service references:

- https://operations.osmfoundation.org/policies/tiles/
- https://wiki.openstreetmap.org/wiki/Overpass_API
- https://pub.dev/packages/flutter_map
- https://pub.dev/packages/geolocator
