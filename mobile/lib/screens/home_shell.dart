import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../theme.dart';
import 'card_inventory_screen.dart';
import 'community_screen.dart';
import 'main_scan_screen.dart';
import 'map_missions_screen.dart';
import 'post_detail_screen.dart';
import 'profile_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => HomeShellState();
}

// A shared link looks like /?post=<id>; it is opened once, right after the first sign-in of this page load.
bool _linkHandled = false;

class HomeShellState extends State<HomeShell> {
  int _index = 0;
  int _unread = 0;
  Timer? _poll;

  final _mapKey = GlobalKey<MapMissionsScreenState>();
  late final List<Widget> _screens = [
    MapMissionsScreen(key: _mapKey),
    const CardInventoryScreen(),
    const CommunityScreen(),
    const ProfileScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _checkUnread();
    if (!_linkHandled) {
      _linkHandled = true;
      final postId = Uri.base.queryParameters['post'];
      if (postId != null && postId.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).push(MaterialPageRoute(builder: (_) => PostDetailScreen(postId: postId)));
        });
      }
    }
    _poll = Timer.periodic(const Duration(seconds: 30), (_) => _checkUnread());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _checkUnread() async {
    try {
      final data = await apiClient.get('/notifications');
      if (mounted) setState(() => _unread = data['unread'] as int? ?? 0);
    } catch (_) {
      // offline or the server is waking up: try again next tick
    }
  }

  void goToTab(int i) {
    setState(() => _index = i);
    if (i == 0) _mapKey.currentState?.reload(silent: true);
  }

  Future<void> _scan() async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MainScanScreen()));
    _checkUnread();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _index, children: _screens),
      floatingActionButton: FloatingActionButton(
        onPressed: _scan,
        backgroundColor: AppColors.gold,
        foregroundColor: Colors.black,
        tooltip: 'สแกน',
        child: const Icon(Icons.qr_code_scanner, size: 30),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      bottomNavigationBar: BottomAppBar(
        color: Colors.white,
        shape: const CircularNotchedRectangle(),
        notchMargin: 6,
        padding: EdgeInsets.zero,
        child: SizedBox(
          height: 62,
          child: Row(
            children: [
              _tab(0, Icons.map_outlined, Icons.map, 'Map'),
              _tab(1, Icons.style_outlined, Icons.style, 'Cards'),
              const SizedBox(width: 64), // room for the scan button
              _tab(2, Icons.groups_outlined, Icons.groups, 'Community'),
              _tab(3, Icons.person_outline, Icons.person, 'Profile', badge: _unread),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tab(int i, IconData icon, IconData activeIcon, String label, {int badge = 0}) {
    final selected = _index == i;
    return Expanded(
      child: InkWell(
        onTap: () => goToTab(i),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Badge(
              isLabelVisible: badge > 0,
              label: Text('$badge'),
              child: Icon(selected ? activeIcon : icon, color: selected ? AppColors.navy : Colors.grey),
            ),
            const SizedBox(height: 2),
            Text(label, style: TextStyle(fontSize: 11, color: selected ? AppColors.navy : Colors.grey, fontWeight: selected ? FontWeight.w600 : FontWeight.normal)),
          ],
        ),
      ),
    );
  }
}
