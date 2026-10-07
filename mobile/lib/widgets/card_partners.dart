import 'package:flutter/material.dart';
import '../models/merchant_models.dart';
import '../services/api_client.dart';
import '../services/geo_service.dart';
import '../theme.dart';
import 'shop_detail.dart';

class _Partner {
  final ShopPin pin;
  final String perk;
  final bool validNow;
  double? km;
  _Partner(this.pin, this.perk, this.validNow);
}

/// "Partners offering perks": the shops that give something to holders of this card. The traveler's position is used
/// only on the phone (to sort by distance); it is never sent to the server.
class CardPartners extends StatefulWidget {
  final String templateId;
  const CardPartners({super.key, required this.templateId});

  @override
  State<CardPartners> createState() => _CardPartnersState();
}

class _CardPartnersState extends State<CardPartners> {
  List<_Partner>? _partners;
  bool _locating = false;
  bool _sorted = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await apiClient.get('/merchants/for-card/${Uri.encodeComponent(widget.templateId)}');
      final list = (data['shops'] as List).map((e) {
        final priv = e['privilege'] as Map<String, dynamic>;
        return _Partner(ShopPin.fromJson(e), '${priv['description']}', priv['valid_now'] != false);
      }).toList();
      if (mounted) setState(() => _partners = list);
    } catch (_) {
      if (mounted) setState(() => _partners = []);
    }
  }

  Future<void> _sortByDistance() async {
    setState(() => _locating = true);
    final p = await currentPosition();
    if (!mounted) return;
    if (p == null) {
      setState(() => _locating = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('อ่านตำแหน่งปัจจุบันไม่ได้ กรุณาอนุญาตการเข้าถึงตำแหน่ง')));
      return;
    }
    setState(() {
      for (final x in _partners!) {
        x.km = distanceKm(p.lat, p.lng, x.pin.latitude, x.pin.longitude);
      }
      _partners!.sort((a, b) => a.km!.compareTo(b.km!));
      _locating = false;
      _sorted = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final list = _partners;
    if (list == null || list.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 18),
      Row(children: [
        const Icon(Icons.card_giftcard, color: AppColors.gold),
        const SizedBox(width: 8),
        const Expanded(child: Text('ร้านพันธมิตรที่ให้สิทธิประโยชน์', style: TextStyle(fontWeight: FontWeight.bold))),
        if (!_sorted)
          TextButton.icon(
            icon: _locating ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.near_me, size: 18),
            label: const Text('ใกล้ฉัน'),
            onPressed: _locating ? null : _sortByDistance,
          ),
      ]),
      const SizedBox(height: 6),
      ...list.map((x) => Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: CircleAvatar(backgroundColor: x.pin.cat.color, child: Icon(x.pin.cat.icon, color: Colors.white, size: 20)),
              title: Text(x.pin.nameTh, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(x.perk, maxLines: 2, overflow: TextOverflow.ellipsis),
              trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                if (x.km != null) Text(distanceText(x.km!), style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.navy)),
                Text(x.pin.openNow ? 'เปิดอยู่' : 'ปิดอยู่', style: TextStyle(fontSize: 11, color: x.pin.openNow ? AppColors.success : Colors.grey)),
              ]),
              onTap: () => showShopDetail(context, x.pin),
            ),
          )),
    ]);
  }
}
