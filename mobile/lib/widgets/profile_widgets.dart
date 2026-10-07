import 'package:flutter/material.dart';
import '../models/collection_models.dart';
import '../models/models.dart';
import '../theme.dart';
import 'card_widgets.dart';

/// Rank and points: the collector rank with a progress bar to the next one, plus the headline numbers.
class RankCard extends StatelessWidget {
  final ShowcaseStats stats;
  const RankCard({super.key, required this.stats});

  @override
  Widget build(BuildContext context) {
    final r = stats.rank;
    final next = r.nextMin;
    final progress = next == null ? 1.0 : ((stats.points - r.min) / (next - r.min)).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [AppColors.navy, Color(0xFF24407A)]),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.workspace_premium, color: AppColors.gold, size: 30),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('ระดับผู้สะสม: ${r.name}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
              Text('${stats.points} แต้มสะสม', style: const TextStyle(color: Colors.white70, fontSize: 12)),
            ]),
          ),
        ]),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(value: progress, minHeight: 8, backgroundColor: Colors.white24, color: AppColors.gold),
        ),
        const SizedBox(height: 6),
        Text(
          next == null ? 'ถึงระดับสูงสุดแล้ว' : 'อีก ${next - stats.points} แต้มถึงระดับ "${r.nextName}"',
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        const SizedBox(height: 4),
        const Text('Normal = 10 แต้ม · Rare = 50 แต้ม · Special = 200 แต้ม', style: TextStyle(color: Colors.white38, fontSize: 11)),
      ]),
    );
  }
}

class StatBoxes extends StatelessWidget {
  final ShowcaseStats stats;
  const StatBoxes({super.key, required this.stats});

  Widget _box(String label, String value) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFE3E7EF))),
          child: Column(children: [
            Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.navy)),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      _box('สถานที่ที่พิชิต', '${stats.placesConquered}'),
      const SizedBox(width: 10),
      _box('การ์ดทั้งหมด', '${stats.totalCards}'),
      const SizedBox(width: 10),
      _box('Special', '${stats.byRarity['special'] ?? 0}'),
    ]);
  }
}

/// "Conquered 12 places" style progress per region of Thailand.
class RegionProgressList extends StatelessWidget {
  final List<RegionProgress> regions;
  const RegionProgressList({super.key, required this.regions});

  @override
  Widget build(BuildContext context) {
    if (regions.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('แผนที่แห่งการพิชิต', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
        const SizedBox(height: 8),
        ...regions.map((r) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(children: [
                SizedBox(width: 150, child: Text(r.region, style: const TextStyle(fontSize: 13), overflow: TextOverflow.ellipsis)),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: LinearProgressIndicator(
                      value: r.total == 0 ? 0 : r.collected / r.total,
                      minHeight: 8,
                      backgroundColor: const Color(0xFFE3E7EF),
                      color: r.percent >= 100 ? AppColors.success : AppColors.navy,
                    ),
                  ),
                ),
                SizedBox(width: 64, child: Text('${r.collected}/${r.total} · ${r.percent}%', textAlign: TextAlign.right, style: const TextStyle(fontSize: 11, color: Colors.grey))),
              ]),
            )),
      ],
    );
  }
}

/// The pinned cards, big, with the 3D tilt. [onTapCard] opens a card; [empty] is shown when nothing is pinned.
class Showcase extends StatelessWidget {
  final List<TravelCard> pins;
  final String empty;
  final void Function(TravelCard)? onTapCard;
  const Showcase({super.key, required this.pins, required this.empty, this.onTapCard});

  @override
  Widget build(BuildContext context) {
    if (pins.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFE3E7EF))),
        child: Center(child: Text(empty, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey))),
      );
    }
    return SizedBox(
      height: 250,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: pins.length,
        separatorBuilder: (_, __) => const SizedBox(width: 14),
        itemBuilder: (_, i) => GestureDetector(
          onTap: onTapCard == null ? null : () => onTapCard!(pins[i]),
          child: SizedBox(width: 178, child: TiltCard(child: CardFace(card: pins[i], large: true))),
        ),
      ),
    );
  }
}
