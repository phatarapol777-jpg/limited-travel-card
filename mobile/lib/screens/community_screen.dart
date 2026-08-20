import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/api_client.dart';
import '../theme.dart';

class CommunityScreen extends StatefulWidget {
  const CommunityScreen({super.key});

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  List<CommunityPost> _posts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final data = await apiClient.get('/community/posts');
      setState(() {
        _posts = (data['posts'] as List).map((e) => CommunityPost.fromJson(e)).toList();
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Future<void> _toggleLike(CommunityPost post) async {
    try {
      await apiClient.post('/community/posts/${post.postId}/like');
      _load();
    } catch (_) {}
  }

  void _openComposer() {
    final ctrl = TextEditingController();
    final emojis = ['🛕', '⛰️', '🏖️', '🚉', '🏯', '🗺️', '📸'];
    String selectedEmoji = emojis.first;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Padding(
          padding: EdgeInsets.only(left: 20, right: 20, top: 20, bottom: MediaQuery.of(ctx).viewInsets.bottom + 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('แชร์ประสบการณ์การเดินทาง', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: emojis
                    .map((e) => ChoiceChip(
                          label: Text(e, style: const TextStyle(fontSize: 18)),
                          selected: selectedEmoji == e,
                          onSelected: (_) => setDialogState(() => selectedEmoji = e),
                        ))
                    .toList(),
              ),
              const SizedBox(height: 12),
              TextField(controller: ctrl, maxLines: 3, decoration: const InputDecoration(hintText: 'เล่าประสบการณ์ของคุณ...')),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () async {
                  if (ctrl.text.trim().isEmpty) return;
                  try {
                    await apiClient.post('/community/posts', {'content': ctrl.text.trim(), 'image_emoji': selectedEmoji});
                    if (!mounted) return;
                    Navigator.of(ctx).pop();
                    _load();
                  } catch (e) {
                    ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text('โพสต์ไม่สำเร็จ: $e')));
                  }
                },
                child: const Text('โพสต์'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openComments(CommunityPost post) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _CommentsSheet(post: post),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Community')),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.navy,
        onPressed: _openComposer,
        child: const Icon(Icons.edit, color: Colors.white),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _posts.isEmpty
                  ? ListView(children: const [Padding(padding: EdgeInsets.all(40), child: Text('ยังไม่มีโพสต์ เป็นคนแรกที่แชร์ประสบการณ์!', textAlign: TextAlign.center))])
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _posts.length,
                      itemBuilder: (ctx, i) {
                        final post = _posts[i];
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(children: [
                                  CircleAvatar(backgroundColor: AppColors.navy, child: Text(post.username.substring(0, 1).toUpperCase(), style: const TextStyle(color: Colors.white))),
                                  const SizedBox(width: 10),
                                  Text(post.username, style: const TextStyle(fontWeight: FontWeight.bold)),
                                ]),
                                const SizedBox(height: 10),
                                if (post.imageEmoji != null)
                                  Container(
                                    height: 100,
                                    width: double.infinity,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(12)),
                                    child: Text(post.imageEmoji!, style: const TextStyle(fontSize: 40)),
                                  ),
                                const SizedBox(height: 10),
                                Text(post.content),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    InkWell(
                                      onTap: () => _toggleLike(post),
                                      child: Row(children: [
                                        Icon(post.likedByMe ? Icons.favorite : Icons.favorite_border,
                                            size: 18, color: post.likedByMe ? Colors.redAccent : Colors.grey),
                                        const SizedBox(width: 4),
                                        Text('${post.likeCount}'),
                                      ]),
                                    ),
                                    const SizedBox(width: 20),
                                    InkWell(
                                      onTap: () => _openComments(post),
                                      child: Row(children: [
                                        const Icon(Icons.mode_comment_outlined, size: 18, color: Colors.grey),
                                        const SizedBox(width: 4),
                                        Text('${post.commentCount}'),
                                      ]),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}

class _CommentsSheet extends StatefulWidget {
  final CommunityPost post;
  const _CommentsSheet({required this.post});

  @override
  State<_CommentsSheet> createState() => _CommentsSheetState();
}

class _CommentsSheetState extends State<_CommentsSheet> {
  List<Comment> _comments = [];
  bool _loading = true;
  final _ctrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await apiClient.get('/community/posts/${widget.post.postId}/comments');
    setState(() {
      _comments = (data['comments'] as List).map((e) => Comment.fromJson(e)).toList();
      _loading = false;
    });
  }

  Future<void> _send() async {
    if (_ctrl.text.trim().isEmpty) return;
    await apiClient.post('/community/posts/${widget.post.postId}/comments', {'content': _ctrl.text.trim()});
    _ctrl.clear();
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: MediaQuery.of(context).viewInsets.bottom + 16),
      child: SizedBox(
        height: 420,
        child: Column(
          children: [
            const Text('ความคิดเห็น', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      itemCount: _comments.length,
                      itemBuilder: (ctx, i) => ListTile(
                        dense: true,
                        title: Text(_comments[i].username, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        subtitle: Text(_comments[i].content),
                      ),
                    ),
            ),
            Row(
              children: [
                Expanded(child: TextField(controller: _ctrl, decoration: const InputDecoration(hintText: 'แสดงความคิดเห็น...'))),
                IconButton(onPressed: _send, icon: const Icon(Icons.send, color: AppColors.navy)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
