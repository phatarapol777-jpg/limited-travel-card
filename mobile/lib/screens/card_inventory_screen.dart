import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/api_client.dart';
import '../utils/icon_map.dart';
import '../widgets/travel_card_tile.dart';
import 'home_shell.dart';

class CardInventoryScreen extends StatefulWidget {
  const CardInventoryScreen({super.key});

  @override
  State<CardInventoryScreen> createState() => _CardInventoryScreenState();
}

class _CardInventoryScreenState extends State<CardInventoryScreen> {
  List<TravelCard> _cards = [];
  bool _loading = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await apiClient.get('/cards');
      setState(() {
        _cards = (data['cards'] as List).map((e) => TravelCard.fromJson(e)).toList();
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('โหลดการ์ดไม่สำเร็จ: $e')));
    }
  }

  List<TravelCard> get _filtered =>
      _query.isEmpty ? _cards : _cards.where((c) => c.name.toLowerCase().contains(_query.toLowerCase())).toList();

  void _showAddInfo() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('เพิ่มการ์ด'),
        content: const Text('การ์ดจะถูกปลดล็อกอัตโนมัติเมื่อคุณเช็คอินสำเร็จที่สถานที่ท่องเที่ยวและทำภารกิจสำเร็จ ไปที่แท็บแผนที่เพื่อเริ่มเช็คอิน'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('ปิด')),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              final state = context.findAncestorStateOfType<HomeShellState>();
              state?.goToTab(0);
            },
            child: const Text('ไปที่แผนที่'),
          ),
        ],
      ),
    );
  }

  void _showTransferDialog() {
    if (_cards.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('คุณยังไม่มีการ์ดให้โอน')));
      return;
    }
    TravelCard selected = _cards.first;
    final usernameCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Transfer การ์ด'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<TravelCard>(
                initialValue: selected,
                isExpanded: true,
                items: _cards
                    .map((c) => DropdownMenuItem(value: c, child: Text(c.name, overflow: TextOverflow.ellipsis)))
                    .toList(),
                onChanged: (v) => setDialogState(() => selected = v!),
                decoration: const InputDecoration(labelText: 'เลือกการ์ด'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: usernameCtrl,
                decoration: const InputDecoration(labelText: 'Username ผู้รับ'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('ยกเลิก')),
            ElevatedButton(
              onPressed: () async {
                try {
                  await apiClient.post('/cards/transfer', {
                    'card_instance_id': selected.cardInstanceId,
                    'to_username': usernameCtrl.text.trim(),
                  });
                  if (!mounted) return;
                  Navigator.of(ctx).pop();
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('โอนการ์ด "${selected.name}" ให้ ${usernameCtrl.text} สำเร็จ')));
                  _load();
                } on ApiException catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
                }
              },
              child: const Text('ยืนยันโอน'),
            ),
          ],
        ),
      ),
    );
  }

  void _openCardDetail(TravelCard card) {
    final addressCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(ctx).viewInsets.bottom + 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              CircleAvatar(backgroundColor: colorFromHex(card.colorHex), child: Icon(iconFor(card.icon), color: Colors.white)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(card.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    Text('${card.rarity.toUpperCase()} · ${card.locationName ?? "-"}', style: const TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 16),
            TextField(controller: addressCtrl, decoration: const InputDecoration(labelText: 'ที่อยู่จัดส่ง (สำหรับสั่งพิมพ์การ์ดจริง)')),
            const SizedBox(height: 12),
            ElevatedButton.icon(
              icon: const Icon(Icons.local_shipping_outlined),
              label: const Text('สั่งพิมพ์การ์ดจริง'),
              onPressed: () async {
                if (addressCtrl.text.trim().isEmpty) {
                  ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('กรอกที่อยู่จัดส่งก่อน')));
                  return;
                }
                try {
                  await apiClient.post('/cards/order', {
                    'card_instance_id': card.cardInstanceId,
                    'shipping_address': addressCtrl.text.trim(),
                  });
                  if (!mounted) return;
                  Navigator.of(ctx).pop();
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('สั่งพิมพ์การ์ดจริงสำเร็จ รอการจัดส่ง')));
                } on ApiException catch (e) {
                  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(e.message)));
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Card Inventory')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: const InputDecoration(hintText: 'Search', prefixIcon: Icon(Icons.search)),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                    ? const Center(child: Text('ยังไม่มีการ์ดในคลัง ไปเช็คอินที่แผนที่เพื่อรับการ์ดแรกของคุณ', textAlign: TextAlign.center))
                    : GridView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 140,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          childAspectRatio: 0.78,
                        ),
                        itemCount: _filtered.length,
                        itemBuilder: (ctx, i) => TravelCardTile(card: _filtered[i], onTap: () => _openCardDetail(_filtered[i])),
                      ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(icon: const Icon(Icons.add), label: const Text('Add'), onPressed: _showAddInfo),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                      icon: const Icon(Icons.swap_horiz), label: const Text('Transfer'), onPressed: _showTransferDialog),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
