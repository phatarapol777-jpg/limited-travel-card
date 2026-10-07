import 'package:flutter/material.dart';
import '../models/collection_models.dart';
import '../services/api_client.dart';
import '../theme.dart';
import 'my_quests_screen.dart';
import 'trades_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<AppNotification> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await apiClient.get('/notifications');
      if (!mounted) return;
      setState(() {
        _items = (data['notifications'] as List).map((e) => AppNotification.fromJson(e)).toList();
        _loading = false;
      });
      if ((data['unread'] as int? ?? 0) > 0) await apiClient.post('/notifications/read', {});
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  IconData _icon(String type) {
    if (type.startsWith('trade')) return Icons.swap_horiz;
    if (type == 'quest_approved') return Icons.check_circle;
    if (type == 'quest_rejected') return Icons.cancel;
    if (type == 'order_ready') return Icons.local_shipping_outlined;
    if (type == 'card_voided') return Icons.block;
    return Icons.notifications;
  }

  void _open(AppNotification n) {
    if (n.type.startsWith('trade')) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TradesScreen()));
    } else if (n.type.startsWith('quest')) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MyQuestsScreen()));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('การแจ้งเตือน')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _items.isEmpty
                  ? ListView(children: const [Padding(padding: EdgeInsets.all(40), child: Center(child: Text('ยังไม่มีการแจ้งเตือน', style: TextStyle(color: Colors.grey))))])
                  : ListView.separated(
                      itemCount: _items.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final n = _items[i];
                        return ListTile(
                          leading: CircleAvatar(backgroundColor: AppColors.navy.withValues(alpha: 0.1), child: Icon(_icon(n.type), color: AppColors.navy)),
                          title: Text(n.text, style: TextStyle(fontWeight: n.read ? FontWeight.normal : FontWeight.bold)),
                          subtitle: Text(n.createdAt.replaceFirst('T', ' ').substring(0, 16), style: const TextStyle(fontSize: 12)),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _open(n),
                        );
                      },
                    ),
            ),
    );
  }
}
