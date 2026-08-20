import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import '../models/models.dart';
import '../services/api_client.dart';
import '../theme.dart';
import '../utils/icon_map.dart';
import 'booking_screen.dart';
import 'scan_kiosk_screen.dart';

class MapMissionsScreen extends StatefulWidget {
  const MapMissionsScreen({super.key});

  @override
  State<MapMissionsScreen> createState() => _MapMissionsScreenState();
}

class _MapMissionsScreenState extends State<MapMissionsScreen> {
  List<TravelLocation> _locations = [];
  List<Mission> _missions = [];
  List<Shop> _shops = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final locData = await apiClient.get('/catalog/locations');
      final missionData = await apiClient.get('/catalog/missions');
      final shopData = await apiClient.get('/catalog/shops');
      setState(() {
        _locations = (locData['locations'] as List).map((e) => TravelLocation.fromJson(e)).toList();
        _missions = (missionData['missions'] as List).map((e) => Mission.fromJson(e)).toList();
        _shops = (shopData['shops'] as List).map((e) => Shop.fromJson(e)).toList();
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'โหลดข้อมูลไม่สำเร็จ: $e';
        _loading = false;
      });
    }
  }

  void _openLocationSheet(TravelLocation loc) {
    final missionsHere = _missions.where((m) => m.locationId == loc.locationId).toList();
    final shopsHere = _shops.where((s) => s.locationName == loc.name).toList();
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(backgroundColor: AppColors.navy, child: Icon(iconFor(loc.icon), color: Colors.white)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(loc.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        Text(loc.province, style: const TextStyle(color: Colors.grey)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(loc.description ?? '', style: const TextStyle(color: Colors.black87)),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text('Check-in ที่นี่'),
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        Navigator.of(context).push(MaterialPageRoute(builder: (_) => ScanKioskScreen(location: loc)));
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.hotel),
                      label: const Text('ค้นหาที่พัก'),
                      onPressed: () {
                        Navigator.of(ctx).pop();
                        Navigator.of(context).push(MaterialPageRoute(builder: (_) => BookingScreen(location: loc)));
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (missionsHere.isNotEmpty) ...[
                const Text('ภารกิจ (Missions)', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ...missionsHere.map((m) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(m.completed ? Icons.check_circle : Icons.flag_outlined,
                          color: m.completed ? AppColors.success : Colors.grey),
                      title: Text(m.title),
                      subtitle: Text(m.description, maxLines: 2, overflow: TextOverflow.ellipsis),
                    )),
              ],
              if (shopsHere.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text('ร้านค้าพันธมิตร', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ...shopsHere.map((s) => ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(iconFor(s.icon), color: AppColors.gold),
                      title: Text(s.shopName),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.star, size: 16, color: Colors.amber),
                        Text(' ${s.rating}'),
                      ]),
                    )),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Travel Map & Missions')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
              : Column(
                  children: [
                    Expanded(
                      flex: 3,
                      child: FlutterMap(
                        options: const MapOptions(
                          initialCenter: ll.LatLng(15.5, 101.0),
                          initialZoom: 5.4,
                        ),
                        children: [
                          TileLayer(
                            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                            userAgentPackageName: 'com.travelcard.mobile',
                          ),
                          MarkerLayer(
                            markers: _locations
                                .map((loc) => Marker(
                                      point: ll.LatLng(loc.latitude, loc.longitude),
                                      width: 44,
                                      height: 44,
                                      child: GestureDetector(
                                        onTap: () => _openLocationSheet(loc),
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: AppColors.navy,
                                            shape: BoxShape.circle,
                                            border: Border.all(color: Colors.white, width: 2),
                                            boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 4)],
                                          ),
                                          child: Icon(iconFor(loc.icon), color: AppColors.gold, size: 20),
                                        ),
                                      ),
                                    ))
                                .toList(),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: ListView(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        children: [
                          _SectionHeader(title: 'Booking services'),
                          SizedBox(
                            height: 76,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              children: const [
                                _ExternalServiceCard(label: 'Booking.com', icon: Icons.hotel),
                                _ExternalServiceCard(label: 'Booking.com Flights', icon: Icons.flight),
                                _ExternalServiceCard(label: 'HRVI Booking', icon: Icons.directions_car),
                              ],
                            ),
                          ),
                          _SectionHeader(title: 'Partner shops'),
                          SizedBox(
                            height: 84,
                            child: ListView(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              children: _shops
                                  .map((s) => _ShopCard(shop: s))
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
        child: Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
      );
}

class _ExternalServiceCard extends StatelessWidget {
  final String label;
  final IconData icon;
  const _ExternalServiceCard({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('เปิดลิงก์จองภายนอก (mock): $label')),
      ),
      child: Container(
        width: 120,
        margin: const EdgeInsets.only(right: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE3E7EF))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: AppColors.navy),
            const Spacer(),
            Text(label, maxLines: 2, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _ShopCard extends StatelessWidget {
  final Shop shop;
  const _ShopCard({required this.shop});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 150,
      margin: const EdgeInsets.only(right: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE3E7EF))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            CircleAvatar(radius: 14, backgroundColor: AppColors.gold.withValues(alpha: 0.2), child: Icon(iconFor(shop.icon), size: 14, color: AppColors.navy)),
            const SizedBox(width: 6),
            const Icon(Icons.star, size: 14, color: Colors.amber),
            Text(' ${shop.rating}', style: const TextStyle(fontSize: 11)),
          ]),
          const Spacer(),
          Text(shop.shopName, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
