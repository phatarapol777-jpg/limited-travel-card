import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import '../models/merchant_models.dart';
import '../models/models.dart';
import '../services/api_client.dart';
import '../theme.dart';
import '../utils/icon_map.dart';
import '../widgets/place_detail.dart';
import '../widgets/map_layers.dart';
import '../widgets/shop_detail.dart';
import 'booking_screen.dart';
import 'transport_screens.dart';

class MapMissionsScreen extends StatefulWidget {
  const MapMissionsScreen({super.key});

  @override
  State<MapMissionsScreen> createState() => MapMissionsScreenState();
}

String _savedBase = 'standard';
Set<String> _savedOverlays = {};

class MapMissionsScreenState extends State<MapMissionsScreen> {
  String _baseId = _savedBase;
  Set<String> _overlayIds = {..._savedOverlays};
  final MapController _mapController = MapController();
  double _zoom = 5.4;

  /// Attractions: a small dot when the whole country is in view, a small icon from province level, bigger as you get closer.
  double _locSize(double z) => z < 7 ? 14 : (z < 10 ? 28 : (z < 14 ? 34 : 40));

  /// Shops are only drawn once you are zoomed in close (like points of interest on a street map), and grow a little as you zoom.
  double _shopSize(double z) => z < 11 ? 0 : (z < 13 ? 24 : (z < 15 ? 30 : 36));

  void _zoomChanged(double z) {
    final changed = _locSize(z) != _locSize(_zoom) || _shopSize(z) != _shopSize(_zoom);
    _zoom = z;
    if (changed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    }
  }
  Timer? _refreshTimer;
  List<TravelLocation> _locations = [];
  List<Mission> _missions = [];
  List<ShopPin> _shops = [];
  String? _shopCategory;
  bool _perksOnly = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    reload();
    // places added by an admin appear without reopening the app
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => reload(silent: true),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  List<ShopPin> get _visibleShops => _shops.where((s) => (_shopCategory == null || s.category == _shopCategory) && (!_perksOnly || s.hasPrivilege)).toList();

  /// Reloads places, missions and shops. [silent] keeps the current screen instead of showing the spinner.
  Future<void> reload({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final locData = await apiClient.get('/catalog/locations');
      final missionData = await apiClient.get('/catalog/missions');
      final shopData = await apiClient.get('/merchants');
      setState(() {
        _locations = (locData['locations'] as List)
            .map((e) => TravelLocation.fromJson(e))
            .toList();
        _missions = (missionData['missions'] as List)
            .map((e) => Mission.fromJson(e))
            .toList();
        _shops = (shopData['shops'] as List)
            .map((e) => ShopPin.fromJson(e))
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (silent) return;
      setState(() {
        _error = 'โหลดข้อมูลไม่สำเร็จ: $e';
        _loading = false;
      });
    }
  }

  /// Centre the map on a place and open its details (works even when the marker is outside the visible area).
  void _goTo(TravelLocation loc) {
    _mapController.move(ll.LatLng(loc.latitude, loc.longitude), 10);
    _openLocationSheet(loc);
  }

  void _openLocationSheet(TravelLocation loc) {
    final missionsHere = _missions.where((m) => m.locationId == loc.locationId).toList();
    final shopsHere = _shops.where((s) => s.nearbyLocationId == loc.locationId).toList();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        expand: false,
        builder: (ctx, scrollController) => SingleChildScrollView(
          controller: scrollController,
          padding: const EdgeInsets.all(20),
          child: PlaceDetailContent(loc: loc, missions: missionsHere, shops: shopsHere, inSheet: true),
        ),
      ),
    );
  }

  void _pickLocationForBooking() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                'ค้นหาที่พักใกล้สถานที่ไหน',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: _locations
                    .map(
                      (loc) => ListTile(
                        leading: CircleAvatar(
                          backgroundColor: AppColors.navy,
                          child: Icon(iconFor(loc.icon), color: Colors.white),
                        ),
                        title: Text(loc.name),
                        subtitle: Text(loc.province),
                        onTap: () {
                          Navigator.of(ctx).pop();
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => BookingScreen(location: loc),
                            ),
                          );
                        },
                      ),
                    )
                    .toList(),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Travel Map & Missions'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'โหลดสถานที่ใหม่',
            onPressed: () => reload(),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!, textAlign: TextAlign.center),
              ),
            )
          : Column(
              children: [
                Expanded(
                  flex: 3,
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: FlutterMap(
                          mapController: _mapController,
                          options: MapOptions(
                            initialCenter: const ll.LatLng(15.5, 101.0),
                            initialZoom: 5.4,
                            onPositionChanged: (camera, _) => _zoomChanged(camera.zoom),
                          ),
                          children: [
                            ...mapTileLayers(baseById(_baseId), _overlayIds),
                            MarkerLayer(
                              markers: _locations
                                  .map(
                                    (loc) => Marker(
                                      point: ll.LatLng(loc.latitude, loc.longitude),
                                      width: _locSize(_zoom) + 6,
                                      height: _locSize(_zoom) + 6,
                                      child: GestureDetector(onTap: () => _openLocationSheet(loc), child: _LocationMarker(loc: loc, size: _locSize(_zoom))),
                                    ),
                                  )
                                  .toList(),
                            ),
                            MarkerLayer(
                              markers: _shopSize(_zoom) == 0
                                  ? const []
                                  : _visibleShops
                                      .map((s) => Marker(
                                            point: ll.LatLng(s.latitude, s.longitude),
                                            width: _shopSize(_zoom) + 6,
                                            height: _shopSize(_zoom) + 6,
                                            child: GestureDetector(onTap: () => showShopDetail(context, s), child: _ShopMarker(shop: s, size: _shopSize(_zoom))),
                                          ))
                                      .toList(),
                            ),
                          ],
                        ),
                      ),
                      Positioned(
                        right: 10,
                        top: 10,
                        child: Material(
                          color: Colors.white,
                          elevation: 3,
                          borderRadius: BorderRadius.circular(12),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => showMapLayerSheet(
                              context,
                              baseId: _baseId,
                              overlayIds: _overlayIds,
                              onChanged: (b, o) => setState(() {
                                _baseId = _savedBase = b;
                                _overlayIds = {...o};
                                _savedOverlays = {...o};
                              }),
                            ),
                            child: const Padding(
                              padding: EdgeInsets.all(10),
                              child: Icon(Icons.layers, color: AppColors.navy),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 6,
                        bottom: 4,
                        right: 70,
                        child: Text(
                          mapCredit(baseById(_baseId), _overlayIds),
                          style: TextStyle(
                            fontSize: 9,
                            color: baseById(_baseId).dark
                                ? Colors.white
                                : Colors.black54,
                            shadows: const [
                              Shadow(blurRadius: 3, color: Colors.black26),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    children: [
                      _SectionHeader(
                        title: 'สถานที่ทั้งหมด (${_locations.length})',
                      ),
                      SizedBox(
                        height: 44,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          children: _locations
                              .map(
                                (l) => Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: ActionChip(
                                    avatar: Icon(
                                      iconFor(l.icon),
                                      size: 16,
                                      color: AppColors.navy,
                                    ),
                                    label: Text(l.name),
                                    onPressed: () => _goTo(l),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                      _SectionHeader(title: 'Booking services'),
                      SizedBox(
                        height: 76,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          children: [
                            _ExternalServiceCard(
                              label: 'จองที่พัก',
                              icon: Icons.hotel,
                              onTap: _pickLocationForBooking,
                            ),
                            _ExternalServiceCard(
                              label: 'จองเที่ยวบิน',
                              icon: Icons.flight,
                              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FlightsScreen())),
                            ),
                            _ExternalServiceCard(
                              label: 'เช่ารถ',
                              icon: Icons.directions_car,
                              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CarsScreen())),
                            ),
                          ],
                        ),
                      ),
                      _SectionHeader(title: 'ร้านค้าพันธมิตร (${_visibleShops.length})'),
                      SizedBox(
                        height: 44,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: FilterChip(
                                avatar: const Icon(Icons.card_giftcard, size: 16, color: AppColors.gold),
                                label: const Text('มีสิทธิประโยชน์'),
                                selected: _perksOnly,
                                onSelected: (v) => setState(() => _perksOnly = v),
                              ),
                            ),
                            ...shopCategories.map(
                              (c) => Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: FilterChip(
                                  avatar: Icon(c.icon, size: 16, color: c.color),
                                  label: Text(c.label),
                                  selected: _shopCategory == c.id,
                                  onSelected: (v) => setState(() => _shopCategory = v ? c.id : null),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        height: 96,
                        child: _visibleShops.isEmpty
                            ? const Center(child: Text('ยังไม่มีร้านค้าในหมวดนี้', style: TextStyle(color: Colors.grey)))
                            : ListView(
                                scrollDirection: Axis.horizontal,
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                children: _visibleShops
                                    .map((s) => _ShopCard(
                                          shop: s,
                                          onTap: () {
                                            _mapController.move(ll.LatLng(s.latitude, s.longitude), 15);
                                            showShopDetail(context, s);
                                          },
                                        ))
                                    .toList(),
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
    child: Text(
      title,
      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
    ),
  );
}

class _ExternalServiceCard extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  const _ExternalServiceCard({
    required this.label,
    required this.icon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap:
          onTap ??
          () => ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('เปิดลิงก์จองภายนอก (mock): $label')),
          ),
      child: Container(
        width: 120,
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE3E7EF)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: AppColors.navy),
            const Spacer(),
            Text(
              label,
              maxLines: 2,
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

class _LocationMarker extends StatelessWidget {
  final TravelLocation loc;
  final double size;
  const _LocationMarker({required this.loc, required this.size});

  @override
  Widget build(BuildContext context) {
    final fallback = Icon(iconFor(loc.icon), color: AppColors.gold, size: size * 0.55);
    return Container(
      margin: const EdgeInsets.all(3),
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppColors.navy,
        shape: BoxShape.circle,
        border: Border.all(color: size < 20 ? AppColors.gold : Colors.white, width: size < 20 ? 2 : 2),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 3)],
      ),
      clipBehavior: Clip.antiAlias,
      child: size < 20
          ? null
          : (loc.pinImageUrl != null
              ? Image.network(loc.pinImageUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => fallback, loadingBuilder: (c, child, p) => p == null ? child : fallback)
              : fallback),
    );
  }
}

class _ShopMarker extends StatelessWidget {
  final ShopPin shop;
  final double size;
  const _ShopMarker({required this.shop, required this.size});

  @override
  Widget build(BuildContext context) {
    final cat = shop.cat;
    return Stack(clipBehavior: Clip.none, children: [
      Container(
        width: size,
        height: size,
        margin: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: cat.color,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 2),
          boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 3)],
        ),
        child: Icon(cat.icon, color: Colors.white, size: size * 0.55),
      ),
      if (shop.hasPrivilege)
        Positioned(
          right: -1,
          top: -1,
          child: Container(
            padding: EdgeInsets.all(size < 30 ? 2 : 3),
            decoration: BoxDecoration(color: AppColors.gold, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 1.5)),
            child: Icon(Icons.card_giftcard, size: size < 30 ? 8 : 11, color: Colors.black87),
          ),
        ),
    ]);
  }
}

class _ShopCard extends StatelessWidget {
  final ShopPin shop;
  final VoidCallback onTap;
  const _ShopCard({required this.shop, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cat = shop.cat;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 160,
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE3E7EF)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              CircleAvatar(radius: 14, backgroundColor: cat.color, child: Icon(cat.icon, size: 14, color: Colors.white)),
              const SizedBox(width: 6),
              if (shop.hasPrivilege) const Icon(Icons.card_giftcard, size: 16, color: AppColors.gold),
              const Spacer(),
              Text(shop.openNow ? 'เปิด' : 'ปิด', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: shop.openNow ? AppColors.success : Colors.grey)),
            ]),
            const Spacer(),
            Text(shop.nameTh, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
