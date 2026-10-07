import 'package:flutter/material.dart';
import '../models/collection_models.dart';
import '../services/api_client.dart';
import '../theme.dart';
import 'my_quests_screen.dart';
import 'my_shops_screen.dart';
import 'community_profile_screen.dart';
import 'leaderboard_screen.dart';
import 'post_detail_screen.dart';
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
    if (type == 'merchant_approved') return Icons.storefront;
    if (type == 'merchant_rejected') return Icons.edit_note;
    if (type == 'merchant_suspended') return Icons.pause_circle_outline;
    if (type == 'community_comment') return Icons.mode_comment_outlined;
    if (type == 'community_reaction') return Icons.add_reaction_outlined;
    if (type == 'community_follow') return Icons.person_add_alt_1;
    if (type == 'community_badge') return Icons.workspace_premium;
    if (type == 'order_ready') return Icons.local_shipping_outlined;
    if (type == 'card_voided') return Icons.block;
    return Icons.notifications;
  }

  void _open(AppNotification n) {
    if (n.type.startsWith('trade')) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const TradesScreen()));
    } else if (n.type.startsWith('quest')) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MyQuestsScreen()));
    } else if (n.type == 'community_comment' || n.type == 'community_reaction') {
      final id = n.data?['post_id'] as String?;
      if (id != null) Navigator.of(context).push(MaterialPageRoute(builder: (_) => PostDetailScreen(postId: id)));
    } else if (n.type == 'community_follow') {
      final u = n.data?['username'] as String?;
      if (u != null) Navigator.of(context).push(MaterialPageRoute(builder: (_) => CommunityProfileScreen(username: u)));
    } else if (n.type == 'community_badge') {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LeaderboardScreen()));
    } else if (n.type.startsWith('merchant')) {
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MyShopsScreen()));
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
