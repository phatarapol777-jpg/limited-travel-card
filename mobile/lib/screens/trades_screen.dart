import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/collection_models.dart';
import '../models/models.dart';
import '../services/api_client.dart';
import '../services/app_state.dart';
import '../theme.dart';
import '../widgets/card_widgets.dart';

/// Incoming offers (accept / reject), offers you sent (cancel) and finished trades.
class TradesScreen extends StatefulWidget {
  const TradesScreen({super.key});

  @override
  State<TradesScreen> createState() => _TradesScreenState();
}

class _TradesScreenState extends State<TradesScreen> {
  List<Trade> _incoming = [];
  List<Trade> _outgoing = [];
  List<Trade> _history = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await apiClient.get('/trades');
      if (!mounted) return;
      setState(() {
        _incoming = (data['incoming'] as List).map((e) => Trade.fromJson(e)).toList();
        _outgoing = (data['outgoing'] as List).map((e) => Trade.fromJson(e)).toList();
        _history = (data['history'] as List).map((e) => Trade.fromJson(e)).toList();
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() {
        _loading = false;
        _error = 'โหลดไม่สำเร็จ: $e';
      });
    }
  }

  Future<void> _act(Trade t, String action) async {
    try {
      await apiClient.post('/trades/${t.tradeId}/$action', {});
      if (!mounted) return;
      final msg = {'accept': 'ยอมรับแล้ว การ์ดเข้าคลังของคุณเรียบร้อย', 'reject': 'ปฏิเสธข้อเสนอแล้ว', 'cancel': 'ยกเลิกข้อเสนอแล้ว'}[action]!;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      context.read<AppState>().refreshStats();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
    _load();
  }

  String _statusLabel(String s) =>
      {'accepted': 'สำเร็จ', 'rejected': 'ถูกปฏิเสธ', 'cancelled': 'ยกเลิก', 'expired': 'หมดอายุ', 'pending': 'รอคำตอบ'}[s] ?? s;

  Widget _miniCard(TravelCard c) => SizedBox(width: 78, child: CardFace(card: c));

  Widget _tradeCard(Trade t, {required List<Widget> actions, required String headline}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(headline, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text(t.mode == 'gift' ? 'ให้ฟรี (ไม่ขอการ์ดตอบแทน)' : 'แลกการ์ด', style: const TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 10),
            Row(children: [
              _miniCard(t.offered),
              if (t.requested != null) ...[
                const Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Icon(Icons.swap_horiz, color: AppColors.navy)),
                _miniCard(t.requested!),
              ],
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(t.offered.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                  if (t.offered.serialLabel != null) Text(t.offered.serialLabel!, style: const TextStyle(color: AppColors.gold, fontSize: 12, fontWeight: FontWeight.w700)),
                  Text(t.offered.rarityLabel, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  if (t.requested != null) ...[
                    const SizedBox(height: 6),
                    Text('แลกกับ: ${t.requested!.name} ${t.requested!.serialLabel ?? ''}', style: const TextStyle(fontSize: 12)),
                  ],
                ]),
              ),
            ]),
            if (actions.isNotEmpty) ...[const SizedBox(height: 10), Row(children: actions)],
          ],
        ),
      ),
    );
  }

  Widget _list(List<Trade> trades, String empty, Widget Function(Trade) build) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: _load,
      child: trades.isEmpty
          ? ListView(children: [Padding(padding: const EdgeInsets.all(40), child: Center(child: Text(_error ?? empty, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey))))])
          : ListView(padding: const EdgeInsets.all(16), children: trades.map(build).toList()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final me = context.read<AppState>().currentUser?.userId;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('แลกเปลี่ยนการ์ด'),
          bottom: TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white60,
            indicatorColor: AppColors.gold,
            tabs: [
              Tab(text: 'ที่ได้รับ${_incoming.isEmpty ? '' : ' (${_incoming.length})'}'),
              Tab(text: 'ที่ส่งไป${_outgoing.isEmpty ? '' : ' (${_outgoing.length})'}'),
              const Tab(text: 'ประวัติ'),
            ],
          ),
        ),
        body: TabBarView(children: [
          _list(
            _incoming,
            'ยังไม่มีข้อเสนอใหม่',
            (t) => _tradeCard(
              t,
              headline: '${t.from.name.isEmpty ? '@${t.from.username}' : t.from.name} (@${t.from.username}) ${t.mode == 'gift' ? 'ส่งการ์ดให้คุณ' : 'ขอแลกการ์ดกับคุณ'}',
              actions: [
                Expanded(child: ElevatedButton(onPressed: () => _act(t, 'accept'), style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(44)), child: const Text('ยอมรับ'))),
                const SizedBox(width: 10),
                Expanded(child: OutlinedButton(onPressed: () => _act(t, 'reject'), style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)), child: const Text('ปฏิเสธ'))),
              ],
            ),
          ),
          _list(
            _outgoing,
            'คุณยังไม่ได้ส่งข้อเสนอที่รอคำตอบ',
            (t) => _tradeCard(
              t,
              headline: 'ส่งถึง @${t.to.username} · รอคำตอบ',
              actions: [Expanded(child: OutlinedButton(onPressed: () => _act(t, 'cancel'), style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(44)), child: const Text('ยกเลิกข้อเสนอ')))],
            ),
          ),
          _list(
            _history,
            'ยังไม่มีประวัติการแลกเปลี่ยน',
            (t) => _tradeCard(
              t,
              headline: '${t.from.userId == me ? 'ส่งถึง @${t.to.username}' : 'จาก @${t.from.username}'} · ${_statusLabel(t.status)}',
              actions: const [],
            ),
          ),
        ]),
      ),
    );
  }
}
