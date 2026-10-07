import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import '../services/geo_service.dart';
import '../theme.dart';
import '../widgets/map_layers.dart';

/// Tap the map to drop the pin where the shop is (or use the phone's position); returns the chosen point.
class ShopLocationPickerScreen extends StatefulWidget {
  final ll.LatLng? initial;
  const ShopLocationPickerScreen({super.key, this.initial});

  @override
  State<ShopLocationPickerScreen> createState() => _ShopLocationPickerScreenState();
}

class _ShopLocationPickerScreenState extends State<ShopLocationPickerScreen> {
  final _map = MapController();
  ll.LatLng? _point;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    _point = widget.initial;
  }

  Future<void> _useMyPosition() async {
    setState(() => _locating = true);
    final p = await currentPosition();
    if (!mounted) return;
    setState(() => _locating = false);
    if (p == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('อ่านตำแหน่งปัจจุบันไม่ได้ กรุณาอนุญาตการเข้าถึงตำแหน่ง หรือแตะบนแผนที่เพื่อปักหมุด')));
      return;
    }
    final pt = ll.LatLng(p.lat, p.lng);
    setState(() => _point = pt);
    _map.move(pt, 16);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ปักหมุดตำแหน่งร้าน')),
      body: Stack(children: [
        FlutterMap(
          mapController: _map,
          options: MapOptions(
            initialCenter: widget.initial ?? const ll.LatLng(15.5, 101.0),
            initialZoom: widget.initial != null ? 16 : 5.6,
            onTap: (_, p) => setState(() => _point = p),
          ),
          children: [
            ...mapTileLayers(baseById('standard'), const {}),
            if (_point != null)
              MarkerLayer(markers: [
                Marker(point: _point!, width: 48, height: 56, alignment: Alignment.topCenter, child: const Icon(Icons.location_on, color: Colors.red, size: 48)),
              ]),
          ],
        ),
        Positioned(
          left: 12,
          right: 12,
          top: 12,
          child: Material(
            elevation: 2,
            borderRadius: BorderRadius.circular(12),
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Text(_point == null ? 'แตะบนแผนที่เพื่อปักหมุด (ซูมเข้าให้ใกล้ที่สุดเพื่อความแม่นยำ)' : 'พิกัด ${_point!.latitude.toStringAsFixed(6)}, ${_point!.longitude.toStringAsFixed(6)}', style: const TextStyle(fontSize: 13)),
            ),
          ),
        ),
      ]),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                icon: _locating ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.my_location),
                label: const Text('ตำแหน่งปัจจุบัน'),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: _locating ? null : _useMyPosition,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(48), backgroundColor: AppColors.navy),
                onPressed: _point == null ? null : () => Navigator.of(context).pop(_point),
                child: const Text('ใช้ตำแหน่งนี้'),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
