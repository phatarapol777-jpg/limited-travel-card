import 'package:flutter/material.dart';
import '../models/merchant_models.dart';
import '../models/models.dart';
import '../screens/booking_screen.dart';
import '../screens/community_feed_screen.dart';
import '../screens/scan_kiosk_screen.dart';
import '../services/api_client.dart';
import '../theme.dart';
import '../utils/icon_map.dart';
import 'location_quests.dart';
import 'shop_detail.dart';

/// Everything about one attraction: description, check-in, booking, quests, missions, partner shops and what travelers posted about it.
/// Used by the map's bottom sheet and by [PlaceDetailScreen] (opened from a place tag in a community post).
class PlaceDetailContent extends StatelessWidget {
  final TravelLocation loc;
  final List<Mission> missions;
  final List<ShopPin> shops;

  /// True inside a bottom sheet: it is closed before another screen opens.
  final bool inSheet;
  const PlaceDetailContent({super.key, required this.loc, this.missions = const [], this.shops = const [], this.inSheet = false});

  void _go(BuildContext context, Widget screen) {
    if (inSheet) Navigator.of(context).pop();
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            CircleAvatar(
              backgroundColor: AppColors.navy,
              backgroundImage: loc.pinImageUrl != null ? NetworkImage(loc.pinImageUrl!) : null,
              child: loc.pinImageUrl != null ? null : Icon(iconFor(loc.icon), color: Colors.white),
            ),
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
                onPressed: () => _go(context, ScanKioskScreen(location: loc)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                icon: const Icon(Icons.hotel),
                label: const Text('ค้นหาที่พัก'),
                onPressed: () => _go(context, BookingScreen(location: loc)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          icon: const Icon(Icons.forum_outlined),
          label: const Text('โพสต์จากนักเดินทางที่นี่'),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
          onPressed: () => _go(context, CommunityFeedScreen(locationId: loc.locationId, title: loc.name)),
        ),
        const SizedBox(height: 20),
        LocationQuests(locationId: loc.locationId),
        if (missions.isNotEmpty) ...[
          const Text('ภารกิจ (Missions)', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...missions.map(
            (m) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(m.completed ? Icons.check_circle : Icons.flag_outlined, color: m.completed ? AppColors.success : Colors.grey),
              title: Text(m.title),
              subtitle: Text(m.description, maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
          ),
        ],
        if (shops.isNotEmpty) ...[
          const SizedBox(height: 8),
          const Text('ร้านค้าพันธมิตร', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          ...shops.map(
            (s) => ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(radius: 18, backgroundColor: s.cat.color, child: Icon(s.cat.icon, size: 18, color: Colors.white)),
              title: Text(s.nameTh),
              subtitle: Text('${s.cat.label} · ${s.openNow ? 'เปิดอยู่' : 'ปิดอยู่'}'),
              trailing: s.hasPrivilege ? const Icon(Icons.card_giftcard, size: 20, color: AppColors.gold) : null,
              onTap: () => showShopDetail(context, s),
            ),
          ),
        ],
      ],
    );
  }
}

/// A full page for one attraction, loaded by id (a place tag in a post opens this).
class PlaceDetailScreen extends StatefulWidget {
  final String locationId;
  const PlaceDetailScreen({super.key, required this.locationId});

  @override
  State<PlaceDetailScreen> createState() => _PlaceDetailScreenState();
}

class _PlaceDetailScreenState extends State<PlaceDetailScreen> {
  TravelLocation? _loc;
  List<Mission> _missions = [];
  List<ShopPin> _shops = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final locs = (await apiClient.get('/catalog/locations'))['locations'] as List;
      final found = locs.map((e) => TravelLocation.fromJson(e)).where((l) => l.locationId == widget.locationId).toList();
      if (found.isEmpty) throw ApiException('ไม่พบสถานที่นี้');
      final missions = (await apiClient.get('/catalog/missions'))['missions'] as List;
      final shops = (await apiClient.get('/merchants'))['shops'] as List;
      if (!mounted) return;
      setState(() {
        _loc = found.first;
        _missions = missions.map((e) => Mission.fromJson(e)).where((m) => m.locationId == widget.locationId).toList();
        _shops = shops.map((e) => ShopPin.fromJson(e)).where((s) => s.nearbyLocationId == widget.locationId).toList();
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'โหลดข้อมูลสถานที่ไม่สำเร็จ: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_loc?.name ?? 'ข้อมูลสถานที่ท่องเที่ยว')),
      body: _error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
          : _loc == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(padding: const EdgeInsets.all(20), children: [PlaceDetailContent(loc: _loc!, missions: _missions, shops: _shops)]),
    );
  }
}

void openPlace(BuildContext context, String locationId) {
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => PlaceDetailScreen(locationId: locationId)));
}
