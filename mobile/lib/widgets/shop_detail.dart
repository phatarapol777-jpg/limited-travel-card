import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/merchant_models.dart';
import '../services/api_client.dart';
import '../theme.dart';
import '../screens/show_to_staff_screen.dart';

/// Opens the shop detail drawer over whatever screen is showing.
void showShopDetail(BuildContext context, ShopPin pin) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.8,
      maxChildSize: 0.95,
      expand: false,
      builder: (ctx, controller) => ShopDetailBody(pin: pin, controller: controller),
    ),
  );
}

class ShopDetailBody extends StatefulWidget {
  final ShopPin pin;
  final ScrollController? controller;
  const ShopDetailBody({super.key, required this.pin, this.controller});

  @override
  State<ShopDetailBody> createState() => _ShopDetailBodyState();
}

class _ShopDetailBodyState extends State<ShopDetailBody> {
  ShopDetail? _d;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await apiClient.get('/merchants/${widget.pin.merchantId}');
      if (mounted) setState(() => _d = ShopDetail.fromJson(data));
    } catch (e) {
      if (mounted) setState(() => _error = 'โหลดข้อมูลร้านไม่สำเร็จ: $e');
    }
  }

  Future<void> _open(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  String _lineUrl(String v) => v.startsWith('http') ? v : 'https://line.me/R/ti/p/${Uri.encodeComponent(v.startsWith('@') ? v : '@$v')}';

  Widget _title(String t) => Padding(
        padding: const EdgeInsets.only(top: 18, bottom: 8),
        child: Text(t, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.navy)),
      );

  Widget _contactChip(IconData icon, String label, String url) => ActionChip(avatar: Icon(icon, size: 18, color: AppColors.navy), label: Text(label), onPressed: () => _open(url));

  @override
  Widget build(BuildContext context) {
    final pin = widget.pin;
    final cat = pin.cat;
    final d = _d;
    return ListView(
      controller: widget.controller,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 30),
      children: [
        if (pin.coverUrl != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Image.network(pin.coverUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => ColoredBox(color: cat.color.withValues(alpha: 0.15), child: Icon(cat.icon, color: cat.color, size: 48))),
            ),
          ),
        const SizedBox(height: 12),
        Text(pin.nameTh, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
        if (pin.nameEn.isNotEmpty) Text(pin.nameEn, style: const TextStyle(color: Colors.grey)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 6, children: [
          Chip(avatar: Icon(cat.icon, size: 16, color: cat.color), label: Text(cat.label), visualDensity: VisualDensity.compact),
          Chip(
            label: Text(pin.openNow ? 'เปิดอยู่ตอนนี้' : 'ปิดอยู่ตอนนี้', style: TextStyle(color: pin.openNow ? AppColors.success : Colors.grey.shade700, fontWeight: FontWeight.w600)),
            visualDensity: VisualDensity.compact,
          ),
          if (pin.hasPrivilege) Chip(avatar: const Icon(Icons.card_giftcard, size: 16, color: AppColors.gold), label: const Text('มีสิทธิประโยชน์การ์ด'), visualDensity: VisualDensity.compact),
        ]),
        if (d == null && _error == null) const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator())),
        if (_error != null) Padding(padding: const EdgeInsets.all(20), child: Text(_error!, style: const TextStyle(color: Colors.red))),
        if (d != null) ...[
          const SizedBox(height: 10),
          Text(d.description),
          _title('สิทธิประโยชน์สำหรับผู้ถือการ์ด'),
          if (d.privileges.isEmpty) const Text('ร้านนี้ยังไม่มีสิทธิประโยชน์ในตอนนี้', style: TextStyle(color: Colors.grey)),
          ...d.privileges.map((p) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      const Icon(Icons.card_giftcard, color: AppColors.gold),
                      const SizedBox(width: 8),
                      Expanded(child: Text('การ์ด "${p.cardName}"', style: const TextStyle(fontWeight: FontWeight.bold))),
                    ]),
                    const SizedBox(height: 6),
                    Text(p.description),
                    const SizedBox(height: 4),
                    Text(p.period, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.badge_outlined),
                      label: const Text('แสดงให้พนักงาน'),
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => ShowToStaffScreen(shop: pin, privilege: p))),
                    ),
                  ]),
                ),
              )),
          if (d.items.isNotEmpty) ...[
            _title('เมนู / สินค้าแนะนำ'),
            SizedBox(
              height: 150,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: d.items
                    .map((i) => Container(
                          width: 112,
                          margin: const EdgeInsets.only(right: 10),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: SizedBox(
                                width: 112,
                                height: 90,
                                child: Stack(fit: StackFit.expand, children: [
                                  Image.network(i.imageUrl, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFFE3E7EF))),
                                  if (i.signature) const Positioned(top: 4, right: 4, child: Icon(Icons.star, color: AppColors.gold, size: 20)),
                                ]),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(i.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                            if (i.price != null) Text('${i.price!.toStringAsFixed(i.price! == i.price!.roundToDouble() ? 0 : 2)} บาท', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                          ]),
                        ))
                    .toList(),
              ),
            ),
          ],
          if (d.galleryUrls.isNotEmpty) ...[
            _title('บรรยากาศร้าน'),
            SizedBox(
              height: 110,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: d.galleryUrls
                    .map((u) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.network(u, height: 110, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox(width: 110, child: ColoredBox(color: Color(0xFFE3E7EF))))),
                        ))
                    .toList(),
              ),
            ),
          ],
          _title('เวลาเปิด-ปิด'),
          ...dayKeys.map((k) {
            final ranges = d.hours[k] ?? const [];
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(children: [
                SizedBox(width: 100, child: Text(dayNames[k]!, style: const TextStyle(color: Colors.grey))),
                Expanded(child: Text(ranges.isEmpty ? 'ปิด' : ranges.map((r) => '${r[0]} - ${r[1]}').join(', '))),
              ]),
            );
          }),
          _title('ที่ตั้งและติดต่อ'),
          Text(d.address),
          if (d.nearbyName != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text('ใกล้กับ ${d.nearbyName}', style: const TextStyle(color: Colors.grey))),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 4, children: [
            _contactChip(Icons.phone, d.phone, 'tel:${d.phone.replaceAll(RegExp(r'[^0-9+]'), '')}'),
            if (d.facebook != null) _contactChip(Icons.facebook, 'Facebook', d.facebook!),
            if (d.instagram != null) _contactChip(Icons.camera_alt_outlined, 'Instagram', d.instagram!),
            if (d.line != null) _contactChip(Icons.chat_bubble_outline, 'LINE', _lineUrl(d.line!)),
            _contactChip(Icons.map_outlined, 'เปิดแผนที่นำทาง', 'https://www.google.com/maps/search/?api=1&query=${pin.latitude},${pin.longitude}'),
          ]),
        ],
      ],
    );
  }
}
