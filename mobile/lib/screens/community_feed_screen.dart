import 'package:flutter/material.dart';
import '../models/community_models.dart';
import '../services/api_client.dart';
import '../widgets/community_widgets.dart';

/// A page of posts that loads more as you scroll. The filters pick which posts: a tab (all, following, trending), a tag,
/// a place, one person, or search text.
class FeedList extends StatefulWidget {
  final String tab;
  final String? tag;
  final String? locationId;
  final String? user;
  final String? query;
  final Widget? header;
  final String emptyText;
  final EdgeInsets padding;

  /// Bumping this reloads from the top (the composer finished, a post was deleted elsewhere...).
  final int reloadToken;
  const FeedList({
    super.key,
    this.tab = 'all',
    this.tag,
    this.locationId,
    this.user,
    this.query,
    this.header,
    this.emptyText = 'ยังไม่มีโพสต์',
    this.padding = const EdgeInsets.all(16),
    this.reloadToken = 0,
  });

  @override
  State<FeedList> createState() => _FeedListState();
}

class _FeedListState extends State<FeedList> {
  final _scroll = ScrollController();
  final List<FeedPost> _posts = [];
  String? _next;
  bool _loading = true;
  bool _more = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 400) _loadMore();
    });
    _load();
  }

  @override
  void didUpdateWidget(FeedList old) {
    super.didUpdateWidget(old);
    if (old.reloadToken != widget.reloadToken || old.query != widget.query || old.tab != widget.tab) _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  String _path(String? cursor) {
    final q = <String, String>{'tab': widget.tab, 'limit': '20'};
    if (widget.tag != null) q['tag'] = widget.tag!;
    if (widget.locationId != null) q['location'] = widget.locationId!;
    if (widget.user != null) q['user'] = widget.user!;
    if (widget.query != null && widget.query!.isNotEmpty) q['q'] = widget.query!;
    if (cursor != null) q[widget.tab == 'trending' ? 'offset' : 'before'] = cursor;
    return '/community/posts?${q.entries.map((e) => '${e.key}=${Uri.encodeQueryComponent(e.value)}').join('&')}';
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await apiClient.get(_path(null));
      if (!mounted) return;
      setState(() {
        _posts
          ..clear()
          ..addAll((data['posts'] as List).map((e) => FeedPost.fromJson(e)));
        _next = data['next'] as String?;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e is ApiException ? e.message : 'โหลดโพสต์ไม่สำเร็จ: $e';
        });
      }
    }
  }

  Future<void> _loadMore() async {
    if (_next == null || _more || _loading) return;
    setState(() => _more = true);
    try {
      final data = await apiClient.get(_path(_next));
      if (!mounted) return;
      setState(() {
        final known = _posts.map((p) => p.postId).toSet();
        _posts.addAll((data['posts'] as List).map((e) => FeedPost.fromJson(e)).where((p) => !known.contains(p.postId)));
        _next = data['next'] as String?;
      });
    } catch (_) {
      // the next scroll tries again
    } finally {
      if (mounted) setState(() => _more = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        controller: _scroll,
        padding: widget.padding,
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          if (widget.header != null) widget.header!,
          if (_error != null) Padding(padding: const EdgeInsets.all(30), child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey))),
          if (_error == null && _posts.isEmpty) Padding(padding: const EdgeInsets.all(40), child: Text(widget.emptyText, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey))),
          for (final p in _posts)
            PostCard(
              key: ValueKey(p.postId),
              post: p,
              onChanged: () => setState(() {}),
              onDeleted: () => setState(() => _posts.removeWhere((x) => x.postId == p.postId)),
              onReload: _load,
            ),
          if (_more) const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
        ],
      ),
    );
  }
}

/// A feed narrowed to one tag, place or person, as its own page.
class CommunityFeedScreen extends StatelessWidget {
  final String? tag;
  final String? locationId;
  final String? user;
  final String title;
  const CommunityFeedScreen({super.key, this.tag, this.locationId, this.user, required this.title});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: FeedList(tag: tag, locationId: locationId, user: user, emptyText: 'ยังไม่มีโพสต์ที่นี่ เป็นคนแรกที่แชร์!'),
    );
  }
}
