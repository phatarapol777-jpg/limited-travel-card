import 'package:flutter/material.dart';
import '../models/community_models.dart';
import '../theme.dart';
import 'community_feed_screen.dart';
import 'community_search_screen.dart';
import 'leaderboard_screen.dart';
import 'post_composer_screen.dart';

/// The community tab: all posts, the people you follow, and what is trending, with search and the monthly leaderboard.
class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key});

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> with SingleTickerProviderStateMixin {
  int _reload = 0;
  late final TabController _tabs = TabController(length: 3, vsync: this)..addListener(_tabChanged);

  void _tabChanged() {
    if (_tabs.indexIsChanging) return;
    if (_tabs.index == 1 && followingFeedStale) {
      followingFeedStale = false;
      communityRefresh.value++;
    }
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _compose() async {
    final posted = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const PostComposerScreen()));
    if (posted == true && mounted) setState(() => _reload++);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        appBar: AppBar(
          title: const Text('Community'),
          actions: [
            IconButton(icon: const Icon(Icons.search), tooltip: 'ค้นหา', onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CommunitySearchScreen()))),
            IconButton(icon: const Icon(Icons.emoji_events_outlined), tooltip: 'อันดับนักเที่ยวประจำเดือน', onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const LeaderboardScreen()))),
          ],
          bottom: TabBar(
            controller: _tabs,
            indicatorColor: AppColors.gold,
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white60,
            tabs: const [Tab(text: 'ทั้งหมด'), Tab(text: 'กำลังติดตาม'), Tab(text: 'ยอดนิยม')],
          ),
        ),
        floatingActionButton: FloatingActionButton(backgroundColor: AppColors.navy, onPressed: _compose, child: const Icon(Icons.edit, color: Colors.white)),
        body: TabBarView(controller: _tabs, children: [
          FeedList(key: const PageStorageKey('all'), tab: 'all', reloadToken: _reload, emptyText: 'ยังไม่มีโพสต์ เป็นคนแรกที่แชร์ประสบการณ์!'),
          FeedList(key: const PageStorageKey('following'), tab: 'following', reloadToken: _reload, emptyText: 'ยังไม่มีโพสต์จากคนที่คุณติดตาม\nค้นหาผู้ใช้แล้วกดติดตามเพื่อเห็นโพสต์ที่นี่'),
          FeedList(key: const PageStorageKey('trending'), tab: 'trending', reloadToken: _reload, emptyText: 'ยังไม่มีโพสต์ยอดนิยมใน 7 วันที่ผ่านมา'),
        ]),
    );
  }
}
