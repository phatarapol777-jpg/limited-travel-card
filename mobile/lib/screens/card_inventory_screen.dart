import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/api_client.dart';
import '../theme.dart';
import '../widgets/travel_card_tile.dart';
import 'card_detail_screen.dart';
import 'main_scan_screen.dart';
import 'notifications_screen.dart';
import 'trades_screen.dart';

class CardInventoryScreen extends StatefulWidget {
  const CardInventoryScreen({super.key});

  @override
  State<CardInventoryScreen> createState() => _CardInventoryScreenState();
}

class _CardInventoryScreenState extends State<CardInventoryScreen> {
  List<TravelCard> _cards = [];
  bool _loading = true;
  String _query = '';
  String _rarity = 'all';
  String _kind = 'all';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await apiClient.get('/cards');
      if (!mounted) return;
      setState(() {
        _cards = (data['cards'] as List).map((e) => TravelCard.fromJson(e)).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('โหลดการ์ดไม่สำเร็จ: $e')));
    }
  }

  List<TravelCard> get _filtered => _cards.where((c) {
        if (_query.isNotEmpty && !c.name.toLowerCase().contains(_query.toLowerCase())) return false;
        if (_rarity != 'all' && c.rarity != _rarity) return false;
        if (_kind == 'quest' && c.isPhysicalPack) return false;
        if (_kind == 'physical' && !c.isPhysicalPack) return false;
        return true;
      }).toList();

  Future<void> _open(TravelCard c) async {
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => CardDetailScreen(card: c)));
    if (changed == true) _load();
  }

  Future<void> _go(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    if (mounted) _load();
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(label: Text(label), selected: selected, onSelected: (_) => onTap(), selectedColor: AppColors.navy, labelStyle: TextStyle(color: selected ? Colors.white : null)),
      );

  @override
  Widget build(BuildContext context) {
    final cards = _filtered;
    return Scaffold(
      appBar: AppBar(
        title: const Text('คลังการ์ด'),
        actions: [
          IconButton(icon: const Icon(Icons.swap_horiz), tooltip: 'แลกเปลี่ยนการ์ด', onPressed: () => _go(const TradesScreen())),
          IconButton(icon: const Icon(Icons.notifications_none), tooltip: 'การแจ้งเตือน', onPressed: () => _go(const NotificationsScreen())),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              decoration: const InputDecoration(hintText: 'ค้นหาการ์ด', prefixIcon: Icon(Icons.search)),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
              _chip('ทั้งหมด', _rarity == 'all', () => setState(() => _rarity = 'all')),
              _chip('Normal', _rarity == 'normal', () => setState(() => _rarity = 'normal')),
              _chip('Rare', _rarity == 'rare', () => setState(() => _rarity = 'rare')),
              _chip('Special', _rarity == 'special', () => setState(() => _rarity = 'special')),
              const SizedBox(width: 8),
              _chip('ทุกประเภท', _kind == 'all', () => setState(() => _kind = 'all')),
              _chip('ภารกิจ/สถานที่', _kind == 'quest', () => setState(() => _kind = 'quest')),
              _chip('การ์ดจริง', _kind == 'physical', () => setState(() => _kind = 'physical')),
            ]),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: cards.isEmpty
                        ? ListView(children: const [
                            Padding(
                              padding: EdgeInsets.all(40),
                              child: Center(child: Text('ยังไม่มีการ์ด เช็คอินที่ตู้ ทำภารกิจ หรือสแกน QR หลังการ์ดจริงเพื่อรับการ์ดแรก', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey))),
                            ),
                          ])
                        : GridView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 140, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 0.71),
                            itemCount: cards.length,
                            itemBuilder: (ctx, i) => TravelCardTile(card: cards[i], onTap: () => _open(cards[i])),
                          ),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton.icon(
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('สแกนรับการ์ด'),
              onPressed: () => _go(const MainScanScreen()),
            ),
          ),
        ],
      ),
    );
  }
}
