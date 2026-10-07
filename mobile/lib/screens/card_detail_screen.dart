import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/api_client.dart';
import '../theme.dart';
import '../widgets/card_partners.dart';
import '../widgets/card_widgets.dart';
import 'trade_composer_screen.dart';

/// One card, large, with a 3D tilt: its story, serial number, and what you can do with it.
class CardDetailScreen extends StatefulWidget {
  final TravelCard card;
  const CardDetailScreen({super.key, required this.card});

  @override
  State<CardDetailScreen> createState() => _CardDetailScreenState();
}

class _CardDetailScreenState extends State<CardDetailScreen> {
  List<String> _pinIds = [];
  bool _pinsLoaded = false;
  bool _busy = false;
  bool _changed = false;

  TravelCard get card => widget.card;

  @override
  void initState() {
    super.initState();
    _loadPins();
  }

  Future<void> _loadPins() async {
    try {
      final data = await apiClient.get('/profile/me');
      if (!mounted) return;
      setState(() {
        _pinIds = (data['pins'] as List).map((e) => e['card_instance_id'] as String).toList();
        _pinsLoaded = true;
      });
    } catch (_) {
      // the pin button just stays hidden
    }
  }

  Future<void> _togglePin() async {
    final pinned = _pinIds.contains(card.cardInstanceId);
    final next = [..._pinIds];
    if (pinned) {
      next.remove(card.cardInstanceId);
    } else {
      if (next.length >= 5) {
        _snack('ปักหมุดได้สูงสุด 5 ใบ เอาใบอื่นออกก่อน');
        return;
      }
      next.add(card.cardInstanceId);
    }
    setState(() => _busy = true);
    try {
      await apiClient.put('/profile/pins', {'card_instance_ids': next});
      if (!mounted) return;
      setState(() => _pinIds = next);
      _changed = true;
      _snack(pinned ? 'เอาออกจากตู้โชว์แล้ว' : 'ปักหมุดบนโปรไฟล์แล้ว');
    } on ApiException catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _orderIntent() async {
    setState(() => _busy = true);
    try {
      final data = await apiClient.post('/cards/${card.cardInstanceId}/order-intent', {});
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.local_shipping_outlined, color: AppColors.navy, size: 36),
          title: const Text('สั่งซื้อการ์ดจริง'),
          content: Text(data['message'] ?? 'เปิดรับความสนใจสั่งซื้อการ์ดจริงแล้ว ระบบจะแจ้งเตือนเมื่อสินค้าพร้อมจัดส่ง'),
          actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('ตกลง'))],
        ),
      );
    } on ApiException catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _trade() async {
    final done = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => TradeComposerScreen(card: card)));
    if (done == true && mounted) {
      _changed = true;
      Navigator.of(context).pop(true);
    }
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  @override
  Widget build(BuildContext context) {
    final pinned = _pinIds.contains(card.cardInstanceId);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        appBar: AppBar(title: Text(card.name, overflow: TextOverflow.ellipsis)),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 300),
                child: TiltCard(child: CardFace(card: card, large: true)),
              ),
            ),
            const SizedBox(height: 6),
            const Center(child: Text('ลากนิ้วบนการ์ดเพื่อเอียงดู', style: TextStyle(color: Colors.grey, fontSize: 12))),
            const SizedBox(height: 16),
            if (card.isLocked)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                child: const Row(children: [
                  Icon(Icons.lock_clock, color: Colors.orange),
                  SizedBox(width: 10),
                  Expanded(child: Text('การ์ดใบนี้อยู่ในข้อเสนอแลกเปลี่ยนที่รอคำตอบ จึงถูกล็อกชั่วคราว')),
                ]),
              ),
            _row('ระดับความหายาก', card.rarityLabel),
            if (card.serialLabel != null) _row('หมายเลขการ์ด', card.serialLabel!),
            _row('ประเภท', card.isPhysicalPack ? 'การ์ดสุ่มจำหน่ายภายนอก' : 'การ์ดภารกิจ / สถานที่'),
            if (card.locationName != null) _row('สถานที่', '${card.locationName}${card.province != null ? ' · ${card.province}' : ''}'),
            if (card.mintLimit != null) _row(card.isPhysicalPack ? 'ผลิตทั้งหมด' : 'แจกแล้ว', card.isPhysicalPack ? '${card.mintLimit} ใบ' : '${card.mintedCount}/${card.mintLimit} ใบ'),
            if (card.acquiredAt != null) _row('ได้รับเมื่อ', card.acquiredAt!.substring(0, 10)),
            if (card.lore != null && card.lore!.isNotEmpty) ...[
              const SizedBox(height: 14),
              const Text('เรื่องราวของการ์ด', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 6),
              Text(card.lore!),
            ],
            CardPartners(templateId: card.templateId),
            const SizedBox(height: 22),
            ElevatedButton.icon(
              icon: const Icon(Icons.swap_horiz),
              label: const Text('เทรด / ส่งการ์ด'),
              onPressed: (card.isLocked || _busy) ? null : _trade,
            ),
            const SizedBox(height: 10),
            if (_pinsLoaded)
              OutlinedButton.icon(
                icon: Icon(pinned ? Icons.push_pin : Icons.push_pin_outlined),
                label: Text(pinned ? 'เอาออกจากตู้โชว์บนโปรไฟล์' : 'ปักหมุดบนโปรไฟล์'),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: _busy ? null : _togglePin,
              ),
            if (!card.isPhysicalPack) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                icon: const Icon(Icons.local_shipping_outlined),
                label: const Text('สั่งซื้อการ์ดจริง (Order Physical Card)'),
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: _busy ? null : _orderIntent,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _row(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: 120, child: Text(label, style: const TextStyle(color: Colors.grey))),
            Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600))),
          ],
        ),
      );
}
