import 'package:flutter/material.dart';
import '../models/collection_models.dart';
import '../services/api_client.dart';
import '../theme.dart';

/// Quests from other travelers / shop owners at a location: cover picture, what to do, how long, how many cards are left.
class LocationQuests extends StatefulWidget {
  final String locationId;
  const LocationQuests({super.key, required this.locationId});

  @override
  State<LocationQuests> createState() => _LocationQuestsState();
}

class _LocationQuestsState extends State<LocationQuests> {
  List<Quest>? _quests;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await apiClient.get('/quests?location_id=${Uri.encodeQueryComponent(widget.locationId)}');
      if (mounted) setState(() => _quests = (data['quests'] as List).map((e) => Quest.fromJson(e)).toList());
    } catch (_) {
      if (mounted) setState(() => _quests = []);
    }
  }

  void _details(Quest q) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(q.title),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (q.coverUrl != null) ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.network(q.coverUrl!, fit: BoxFit.cover)),
            const SizedBox(height: 10),
            Text(q.description),
            const SizedBox(height: 10),
            Text('ระยะเวลา: ${q.period}', style: const TextStyle(color: Colors.grey)),
            if (q.card != null) ...[
              const Divider(height: 24),
              Text('รางวัล: ${q.card!.name} (${q.card!.rarity.toUpperCase()})', style: const TextStyle(fontWeight: FontWeight.bold)),
              if (q.card!.lore != null && q.card!.lore!.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text(q.card!.lore!)),
              const SizedBox(height: 6),
              Text(q.card!.remaining == null ? 'ไม่จำกัดจำนวน' : 'เหลือ ${q.card!.remaining} จาก ${q.card!.mintLimit} ใบ'),
            ],
            const SizedBox(height: 10),
            const Text('ไปที่สถานที่จริง ทำกิจกรรมตามเงื่อนไข แล้วสแกน QR ภารกิจด้วยปุ่มสแกนหลัก (ปุ่มสีทองด้านล่าง)', style: TextStyle(fontSize: 12, color: Colors.grey)),
          ]),
        ),
        actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('ปิด'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final quests = _quests;
    if (quests == null || quests.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('ภารกิจจากผู้ประกอบการ (Quests)', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        ...quests.map((q) {
          final left = q.card?.remaining;
          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => _details(q),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (q.coverUrl != null)
                  AspectRatio(aspectRatio: 16 / 9, child: Image.network(q.coverUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFFE3E7EF)))),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(q.title, style: const TextStyle(fontWeight: FontWeight.bold))),
                      if (q.claimedByMe)
                        const Chip(label: Text('รับแล้ว'), backgroundColor: Color(0x222FBF71), side: BorderSide.none, visualDensity: VisualDensity.compact)
                      else if (left == 0)
                        const Chip(label: Text('หมดแล้ว'), backgroundColor: Color(0x22FF0000), side: BorderSide.none, visualDensity: VisualDensity.compact),
                    ]),
                    const SizedBox(height: 2),
                    Text(q.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.black87)),
                    const SizedBox(height: 6),
                    Text(
                      '${q.period}${left == null ? '' : ' · เหลือ $left ใบ'}${q.phase == 'upcoming' ? ' · ยังไม่เริ่ม' : ''}',
                      style: const TextStyle(color: AppColors.navy, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ]),
                ),
              ]),
            ),
          );
        }),
        const SizedBox(height: 8),
      ],
    );
  }
}
