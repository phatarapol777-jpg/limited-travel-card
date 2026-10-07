import 'dart:async';
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/api_client.dart';
import '../theme.dart';
import '../widgets/card_widgets.dart';
import '../widgets/travel_card_tile.dart';
import 'main_scan_screen.dart';

class _Person {
  final String username;
  final String name;
  _Person(this.username, this.name);
}

/// Offer one of your cards to a friend: as a gift, or in exchange for one of theirs.
class TradeComposerScreen extends StatefulWidget {
  final TravelCard card;
  final String? recipientUsername;
  const TradeComposerScreen({super.key, required this.card, this.recipientUsername});

  @override
  State<TradeComposerScreen> createState() => _TradeComposerScreenState();
}

class _TradeComposerScreenState extends State<TradeComposerScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<_Person> _results = [];
  _Person? _recipient;
  String _mode = 'gift';
  List<TravelCard> _theirCards = [];
  TravelCard? _requested;
  bool _loadingCards = false;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.recipientUsername != null) _pick(_Person(widget.recipientUsername!, ''));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onQuery(String q) {
    _debounce?.cancel();
    if (q.trim().length < 2) {
      setState(() => _results = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final data = await apiClient.get('/users/search?q=${Uri.encodeQueryComponent(q.trim())}');
        if (!mounted) return;
        setState(() => _results = (data['users'] as List).map((e) => _Person(e['username'], e['name'] ?? '')).toList());
      } catch (_) {
        // keep the previous results
      }
    });
  }

  Future<void> _scanFriend() async {
    final username = await Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const MainScanScreen(pickUser: true)));
    if (username != null && mounted) _pick(_Person(username, ''));
  }

  void _pick(_Person p) {
    setState(() {
      _recipient = p;
      _results = [];
      _requested = null;
      _theirCards = [];
      _error = null;
    });
    if (_mode == 'swap') _loadTheirCards();
  }

  Future<void> _loadTheirCards() async {
    final r = _recipient;
    if (r == null) return;
    setState(() => _loadingCards = true);
    try {
      final data = await apiClient.get('/users/${Uri.encodeComponent(r.username)}/cards');
      if (!mounted) return;
      setState(() {
        _theirCards = (data['cards'] as List).map((e) => TravelCard.fromJson(e)).toList();
        _loadingCards = false;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() {
        _loadingCards = false;
        _error = e.message;
      });
    }
  }

  Future<void> _send() async {
    final r = _recipient;
    if (r == null) return;
    if (_mode == 'swap' && _requested == null) {
      setState(() => _error = 'เลือกการ์ดของเพื่อนที่ต้องการแลก');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await apiClient.post('/trades', {
        'mode': _mode,
        'to_username': r.username,
        'offered_card_id': widget.card.cardInstanceId,
        if (_mode == 'swap') 'requested_card_id': _requested!.cardInstanceId,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('ส่งข้อเสนอให้ @${r.username} แล้ว รอเขายอมรับ')));
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (_) {
      setState(() => _error = 'เชื่อมต่อเซิร์ฟเวอร์ไม่ได้');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _recipient;
    return Scaffold(
      appBar: AppBar(title: const Text('เทรด / ส่งการ์ด')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(children: [
            SizedBox(width: 90, child: CardFace(card: widget.card)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('การ์ดที่คุณจะส่ง', style: TextStyle(color: Colors.grey, fontSize: 12)),
                Text(widget.card.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                if (widget.card.serialLabel != null) Text(widget.card.serialLabel!, style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.w700)),
              ]),
            ),
          ]),
          const SizedBox(height: 20),
          const Text('ส่งให้ใคร', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (r == null) ...[
            TextField(
              controller: _search,
              onChanged: _onQuery,
              decoration: const InputDecoration(hintText: 'ค้นหาจาก Username หรือ User ID', prefixIcon: Icon(Icons.search)),
            ),
            ..._results.map((p) => ListTile(
                  leading: const CircleAvatar(child: Icon(Icons.person)),
                  title: Text('@${p.username}'),
                  subtitle: p.name.isEmpty ? null : Text(p.name),
                  onTap: () => _pick(p),
                )),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('สแกน QR โปรไฟล์ของเพื่อน'),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
              onPressed: _scanFriend,
            ),
          ] else
            Card(
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person)),
                title: Text('@${r.username}'),
                subtitle: r.name.isEmpty ? null : Text(r.name),
                trailing: TextButton(onPressed: () => setState(() => _recipient = null), child: const Text('เปลี่ยน')),
              ),
            ),
          if (r != null) ...[
            const SizedBox(height: 20),
            const Text('รูปแบบ', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'gift', label: Text('ให้ฟรี'), icon: Icon(Icons.card_giftcard)),
                ButtonSegment(value: 'swap', label: Text('แลกการ์ด'), icon: Icon(Icons.swap_horiz)),
              ],
              selected: {_mode},
              onSelectionChanged: (v) {
                setState(() {
                  _mode = v.first;
                  _requested = null;
                });
                if (_mode == 'swap' && _theirCards.isEmpty) _loadTheirCards();
              },
            ),
            if (_mode == 'swap') ...[
              const SizedBox(height: 16),
              const Text('เลือกการ์ดของเขาที่ต้องการแลก', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              if (_loadingCards)
                const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
              else if (_theirCards.isEmpty)
                const Text('เพื่อนคนนี้ยังไม่มีการ์ดที่แลกเปลี่ยนได้', style: TextStyle(color: Colors.grey))
              else
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 110, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 0.71),
                  itemCount: _theirCards.length,
                  itemBuilder: (_, i) {
                    final c = _theirCards[i];
                    final selected = _requested?.cardInstanceId == c.cardInstanceId;
                    return Stack(children: [
                      Positioned.fill(child: TravelCardTile(card: c, onTap: () => setState(() => _requested = c))),
                      if (selected)
                        Positioned.fill(
                          child: IgnorePointer(
                            child: Container(
                              decoration: BoxDecoration(border: Border.all(color: AppColors.success, width: 4), borderRadius: BorderRadius.circular(14)),
                              alignment: Alignment.topRight,
                              padding: const EdgeInsets.all(4),
                              child: const Icon(Icons.check_circle, color: AppColors.success),
                            ),
                          ),
                        ),
                    ]);
                  },
                ),
            ],
            const SizedBox(height: 8),
            const Text('เมื่อส่งข้อเสนอ การ์ดของคุณจะถูกล็อกจนกว่าเพื่อนจะตอบรับหรือปฏิเสธ (หมดอายุใน 48 ชั่วโมง)', style: TextStyle(color: Colors.grey, fontSize: 12)),
            if (_error != null) ...[const SizedBox(height: 10), Text(_error!, style: const TextStyle(color: Colors.red))],
            const SizedBox(height: 14),
            ElevatedButton(
              onPressed: _sending ? null : _send,
              child: _sending
                  ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : Text(_mode == 'gift' ? 'ส่งการ์ดให้เพื่อน' : 'ส่งข้อเสนอแลกการ์ด'),
            ),
          ] else if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
        ],
      ),
    );
  }
}
