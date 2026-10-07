import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import '../theme.dart';

/// A base map style (only one is shown at a time).
class MapBase {
  final String id;
  final String label;
  final IconData icon;
  final String url;
  final int maxNativeZoom;
  final String credit;
  final bool dark; // a dark picture: the credit text is drawn in white
  /// Reference layer (place names, borders) drawn on top, for satellite pictures.
  final String? labelsUrl;
  const MapBase(this.id, this.label, this.icon, this.url, this.maxNativeZoom, this.credit, {this.dark = false, this.labelsUrl});
}

/// An extra layer drawn over the base map (can be switched on together with others).
class MapOverlay {
  final String id;
  final String label;
  final IconData icon;
  final String url;
  final int maxNativeZoom;
  final String credit;
  const MapOverlay(this.id, this.label, this.icon, this.url, this.maxNativeZoom, this.credit);
}

const mapBases = <MapBase>[
  MapBase('standard', 'แผนที่ปกติ', Icons.map_outlined, 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', 19, '© OpenStreetMap contributors'),
  MapBase('satellite', 'ดาวเทียม', Icons.satellite_alt, 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}', 18,
      'Imagery © Esri, Maxar, Earthstar Geographics', dark: true),
  MapBase('hybrid', 'ดาวเทียม + ชื่อสถานที่', Icons.layers_outlined, 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}', 18,
      'Imagery © Esri, Maxar, Earthstar Geographics', dark: true,
      labelsUrl: 'https://server.arcgisonline.com/ArcGIS/rest/services/Reference/World_Boundaries_and_Places/MapServer/tile/{z}/{y}/{x}'),
  MapBase('terrain', 'ภูมิประเทศ', Icons.terrain, 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Topo_Map/MapServer/tile/{z}/{y}/{x}', 18, 'Map © Esri, USGS, NOAA'),
  MapBase('light', 'สว่าง (เรียบ)', Icons.light_mode_outlined, 'https://a.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png', 19, '© OpenStreetMap contributors © CARTO'),
];

const mapOverlays = <MapOverlay>[
  MapOverlay('rail', 'เส้นทางรถไฟ', Icons.train_outlined, 'https://tiles.openrailwaymap.org/standard/{z}/{x}/{y}.png', 19, '© OpenRailwayMap'),
  MapOverlay('cycling', 'เส้นทางจักรยาน', Icons.pedal_bike, 'https://tile.waymarkedtrails.org/cycling/{z}/{x}/{y}.png', 18, '© Waymarked Trails'),
];

MapBase baseById(String id) => mapBases.firstWhere((b) => b.id == id, orElse: () => mapBases.first);

const _agent = 'com.travelcard.mobile';

/// The tile layers for the chosen base map and overlays, bottom to top.
List<Widget> mapTileLayers(MapBase base, Set<String> overlayIds) => [
      TileLayer(urlTemplate: base.url, maxNativeZoom: base.maxNativeZoom, maxZoom: 19, userAgentPackageName: _agent),
      if (base.labelsUrl != null) TileLayer(urlTemplate: base.labelsUrl!, maxNativeZoom: 13, maxZoom: 19, userAgentPackageName: _agent),
      for (final o in mapOverlays)
        if (overlayIds.contains(o.id)) TileLayer(urlTemplate: o.url, maxNativeZoom: o.maxNativeZoom, maxZoom: 19, userAgentPackageName: _agent),
    ];

/// The small credit line the map providers ask for.
String mapCredit(MapBase base, Set<String> overlayIds) =>
    [base.credit, for (final o in mapOverlays) if (overlayIds.contains(o.id)) o.credit].join(' · ');

/// Bottom sheet like the layer menu of a maps app: pick the map type, switch extra layers on or off.
Future<void> showMapLayerSheet(
  BuildContext context, {
  required String baseId,
  required Set<String> overlayIds,
  required void Function(String baseId, Set<String> overlayIds) onChanged,
}) {
  var base = baseId;
  final overlays = {...overlayIds};
  return showModalBottomSheet<void>(
    context: context,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setSheet) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('ประเภทแผนที่', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final b in mapBases)
                    InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () {
                        setSheet(() => base = b.id);
                        onChanged(base, overlays);
                      },
                      child: Container(
                        width: 92,
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                        decoration: BoxDecoration(
                          color: base == b.id ? AppColors.navy.withValues(alpha: 0.08) : Colors.white,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: base == b.id ? AppColors.navy : const Color(0xFFDDE2EA), width: base == b.id ? 2 : 1),
                        ),
                        child: Column(children: [
                          Icon(b.icon, color: base == b.id ? AppColors.navy : Colors.grey, size: 28),
                          const SizedBox(height: 6),
                          Text(b.label, textAlign: TextAlign.center, maxLines: 2, style: TextStyle(fontSize: 11, fontWeight: base == b.id ? FontWeight.bold : FontWeight.normal)),
                        ]),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 18),
              const Text('รายละเอียดแผนที่', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  for (final o in mapOverlays)
                    FilterChip(
                      avatar: Icon(o.icon, size: 18, color: overlays.contains(o.id) ? Colors.white : AppColors.navy),
                      label: Text(o.label),
                      selected: overlays.contains(o.id),
                      selectedColor: AppColors.navy,
                      checkmarkColor: Colors.white,
                      labelStyle: TextStyle(color: overlays.contains(o.id) ? Colors.white : null),
                      onSelected: (on) {
                        setSheet(() => on ? overlays.add(o.id) : overlays.remove(o.id));
                        onChanged(base, overlays);
                      },
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
