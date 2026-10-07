import 'dart:async';
import 'package:flutter/material.dart';
import '../models/community_models.dart';
import '../services/api_client.dart';
import '../widgets/community_widgets.dart';
import 'community_feed_screen.dart';

/// Search people, #hashtags and text in posts. A tag result opens the feed for that tag; a person opens their profile.
class CommunitySearchScreen extends StatefulWidget {
  const CommunitySearchScreen({super.key});

  @override
  State<CommunitySearchScreen> createState() => _CommunitySearchScreenState();
}

class _CommunitySearchScreenState extends State<CommunitySearchScreen> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  List<Author> _users = [];
  List<Map<String, dynamic>> _tags = [];
  List<FeedPost> _posts = [];
  bool _searching = false;
  bool _searched = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _changed(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(v.trim()));
  }

  Future<void> _search(String q) async {
    if (q.isEmpty) {
      setState(() {
        _users = [];
        _tags = [];
        _posts = [];
        _searched = false;
      });
      return;
    }
    setState(() => _searching = true);
    try {
      final data = await apiClient.get('/community/search?q=${Uri.encodeQueryComponent(q)}');
      if (!mounted || _ctrl.text.trim() != q) return;
      setState(() {
        _users = (data['users'] as List).map((e) => Author.fromJson(e as Map<String, dynamic>)).toList();
        _tags = (data['tags'] as List).map((e) => e as Map<String, dynamic>).toList();
        _posts = (data['posts'] as List).map((e) => FeedPost.fromJson(e)).toList();
        _searched = true;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = 'ค้นหาไม่สำเร็จ: $e');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final nothing = _searched && _users.isEmpty && _tags.isEmpty && _posts.isEmpty;
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _ctrl,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          cursorColor: Colors.white,
          decoration: const InputDecoration(hintText: 'ค้นหาผู้ใช้ #แฮชแท็ก หรือข้อความ', hintStyle: TextStyle(color: Colors.white60), border: InputBorder.none, filled: false),
          onChanged: _changed,
          onSubmitted: (v) => _search(v.trim()),
        ),
        actions: [if (_searching) const Padding(padding: EdgeInsets.all(16), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)))],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
        if (!_searched && _error == null) const Padding(padding: EdgeInsets.all(30), child: Text('พิมพ์ชื่อผู้ใช้ เช่น somchai หรือแฮชแท็ก เช่น #ดอยสุเทพ', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey))),
        if (nothing) const Padding(padding: EdgeInsets.all(30), child: Text('ไม่พบผลการค้นหา', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey))),
        if (_users.isNotEmpty) ...[
          const Text('ผู้ใช้', style: TextStyle(fontWeight: FontWeight.bold)),
          ..._users.map((u) => ListTile(contentPadding: EdgeInsets.zero, leading: AuthorAvatar(author: u), title: AuthorName(author: u), subtitle: Text('@${u.username}'), trailing: FollowButton(author: u), onTap: () => openProfile(context, u.username))),
        ],
        if (_tags.isNotEmpty) ...[
          const Text('แฮชแท็ก', style: TextStyle(fontWeight: FontWeight.bold)),
          ..._tags.map((t) => ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(child: Icon(Icons.tag)),
                title: Text('#${t['tag']}'),
                subtitle: Text('${t['posts']} โพสต์'),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CommunityFeedScreen(tag: '${t['tag']}', title: '#${t['tag']}'))),
              )),
        ],
        if (_posts.isNotEmpty) ...[
          const Padding(padding: EdgeInsets.only(top: 8, bottom: 8), child: Text('โพสต์', style: TextStyle(fontWeight: FontWeight.bold))),
          ..._posts.map((p) => PostCard(key: ValueKey(p.postId), post: p, onChanged: () => setState(() {}), onDeleted: () => setState(() => _posts.removeWhere((x) => x.postId == p.postId)))),
        ],
      ]),
    );
  }
}
