import 'package:flutter/material.dart';
import '../models/collection_models.dart';
import '../models/models.dart';
import '../services/api_client.dart';
import '../theme.dart';
import '../widgets/card_widgets.dart';
import '../widgets/profile_widgets.dart';
import 'trade_composer_screen.dart';

/// Another traveler's showcase: pinned cards, rank and conquest statistics.
class ProfileViewScreen extends StatefulWidget {
  final String username;
  const ProfileViewScreen({super.key, required this.username});

  @override
  State<ProfileViewScreen> createState() => _ProfileViewScreenState();
}

class _ProfileViewScreenState extends State<ProfileViewScreen> {
  ProfileData? _profile;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await apiClient.get('/profile/${Uri.encodeComponent(widget.username)}');
      if (mounted) setState(() => _profile = ProfileData.fromJson(data));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'โหลดโปรไฟล์ไม่สำเร็จ: $e');
    }
  }

  // Start a trade by picking one of your own cards first.
  Future<void> _startTrade() async {
    TravelCard? mine;
    try {
      final data = await apiClient.get('/cards');
      final cards = (data['cards'] as List).map((e) => TravelCard.fromJson(e)).where((c) => c.activationStatus == 'CLAIMED').toList();
      if (!mounted) return;
      if (cards.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('คุณยังไม่มีการ์ดที่แลกเปลี่ยนได้')));
        return;
      }
      mine = await showModalBottomSheet<TravelCard>(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (ctx) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          builder: (ctx, controller) => Column(children: [
            const Padding(padding: EdgeInsets.all(16), child: Text('เลือกการ์ดของคุณที่จะส่ง', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
            Expanded(
              child: GridView.builder(
                controller: controller,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 120, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 0.71),
                itemCount: cards.length,
                itemBuilder: (_, i) => InkWell(onTap: () => Navigator.of(ctx).pop(cards[i]), child: CardFace(card: cards[i])),
              ),
            ),
          ]),
        ),
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('โหลดการ์ดไม่สำเร็จ: $e')));
    }
    if (mine != null && mounted) {
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => TradeComposerScreen(card: mine!, recipientUsername: widget.username)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _profile;
    return Scaffold(
      appBar: AppBar(title: Text('@${widget.username}')),
      body: _error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
          : p == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Center(
                      child: Column(children: [
                        CircleAvatar(radius: 36, backgroundColor: AppColors.navy, child: Text(p.name.isEmpty ? '?' : p.name.substring(0, 1), style: const TextStyle(color: Colors.white, fontSize: 26))),
                        const SizedBox(height: 10),
                        Text(p.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        Text('@${p.username}', style: const TextStyle(color: Colors.grey)),
                      ]),
                    ),
                    const SizedBox(height: 18),
                    RankCard(stats: p.stats),
                    const SizedBox(height: 14),
                    StatBoxes(stats: p.stats),
                    const SizedBox(height: 20),
                    const Text('ตู้โชว์การ์ดเด่น', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 10),
                    Showcase(pins: p.pins, empty: 'ยังไม่ได้ปักหมุดการ์ด'),
                    const SizedBox(height: 20),
                    RegionProgressList(regions: p.stats.regions),
                    const SizedBox(height: 22),
                    ElevatedButton.icon(icon: const Icon(Icons.swap_horiz), label: const Text('เทรด / ส่งการ์ดให้คนนี้'), onPressed: _startTrade),
                  ],
                ),
    );
  }
}
