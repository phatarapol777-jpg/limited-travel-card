import 'package:flutter/material.dart';
import '../models/community_models.dart';
import '../services/api_client.dart';
import '../theme.dart';
import '../widgets/community_widgets.dart';

/// The monthly ranking: who tagged the most different places. The running month is live; finished months are final.
class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  String? _month;
  List<Map<String, dynamic>> _months = [];
  List<LeaderRow> _rows = [];
  String _label = '';
  bool _finalized = false;
  int? _myRank;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load([String? month]) async {
    setState(() => _loading = true);
    try {
      final data = await apiClient.get('/community/leaderboard${month == null ? '' : '?month=$month'}');
      if (!mounted) return;
      setState(() {
        _month = data['month'] as String;
        _label = data['label'] as String;
        _finalized = data['finalized'] == true;
        _months = (data['months'] as List).map((e) => e as Map<String, dynamic>).toList();
        _rows = (data['rows'] as List).map((e) => LeaderRow.fromJson(e)).toList();
        _myRank = (data['my_rank'] as num?)?.toInt();
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'โหลดอันดับไม่สำเร็จ: $e';
        });
      }
    }
  }

  Color _medal(int rank) => rank == 1 ? const Color(0xFFD4AF37) : (rank == 2 ? const Color(0xFF9AA5B1) : const Color(0xFFB87333));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('นักเที่ยวประจำเดือน')),
      body: _error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)))
          : ListView(padding: const EdgeInsets.all(16), children: [
              if (_months.isNotEmpty)
                DropdownButtonFormField<String>(
                  initialValue: _month,
                  decoration: const InputDecoration(labelText: 'เดือน'),
                  items: _months.map((m) => DropdownMenuItem(value: m['month'] as String, child: Text(m['label'] as String))).toList(),
                  onChanged: (v) => v == null ? null : _load(v),
                ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: AppColors.navy.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(12)),
                child: Text(
                  _finalized
                      ? 'ผลสรุปประจำเดือน $_label (ปิดรอบแล้ว) · นับจำนวนสถานที่ท่องเที่ยวที่ไม่ซ้ำกันที่แท็กในโพสต์ ผู้ติดอันดับได้รับตราสัญลักษณ์พิเศษ'
                      : 'อันดับเดือน $_label (กำลังนับอยู่) · นับจำนวนสถานที่ท่องเที่ยวที่ไม่ซ้ำกันที่แท็กในโพสต์ ตัดรอบทุกสิ้นเดือน ตามเวลาประเทศไทย',
                  style: const TextStyle(fontSize: 12.5),
                ),
              ),
              if (_myRank != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text('อันดับของคุณ: $_myRank', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.navy))),
              const SizedBox(height: 8),
              if (_loading) const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
              if (!_loading && _rows.isEmpty) const Padding(padding: EdgeInsets.all(40), child: Text('ยังไม่มีใครแท็กสถานที่ในเดือนนี้\nโพสต์พร้อมแท็กสถานที่เพื่อขึ้นอันดับ!', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey))),
              if (!_loading)
                for (final r in _rows)
                  Card(
                    color: r.isMe ? AppColors.gold.withValues(alpha: 0.12) : null,
                    child: ListTile(
                      leading: SizedBox(
                        width: 36,
                        child: r.rank <= 3 ? Icon(Icons.workspace_premium, color: _medal(r.rank), size: 32) : Center(child: Text('${r.rank}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                      ),
                      title: Row(children: [AuthorAvatar(author: r.author, radius: 16), const SizedBox(width: 10), Expanded(child: AuthorName(author: r.author))]),
                      trailing: Text('${r.uniqueCount} แห่ง', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.navy)),
                      onTap: () => openProfile(context, r.author.username),
                    ),
                  ),
            ]),
    );
  }
}
