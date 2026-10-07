import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../models/community_models.dart';
import '../services/api_client.dart';
import '../services/image_tools.dart';
import '../theme.dart';
import '../widgets/community_widgets.dart';

/// One post on its own page, with all its comments. Opened from the feed, a notification or a shared link.
class PostDetailScreen extends StatefulWidget {
  final String postId;
  const PostDetailScreen({super.key, required this.postId});

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  FeedPost? _post;
  List<FeedComment> _comments = [];
  String? _error;
  final _text = TextEditingController();
  final _focus = FocusNode();
  String? _newImage;
  FeedComment? _editing;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final p = await apiClient.get('/community/posts/${widget.postId}');
      final c = await apiClient.get('/community/posts/${widget.postId}/comments');
      if (!mounted) return;
      setState(() {
        _post = FeedPost.fromJson(p['post'] as Map<String, dynamic>);
        _comments = (c['comments'] as List).map((e) => FeedComment.fromJson(e)).toList();
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'โหลดโพสต์ไม่สำเร็จ: $e');
    }
  }

  Future<void> _pickImage() async {
    final url = await pickJpeg(maxSide: 640, maxChars: 34000);
    if (url != null && mounted) setState(() => _newImage = url);
  }

  Future<void> _send() async {
    final text = _text.text.trim();
    if (text.isEmpty && _newImage == null && !(_editing != null && _editing!.hasImage)) return;
    setState(() => _sending = true);
    try {
      if (_editing != null) {
        await apiClient.put('/community/comments/${_editing!.commentId}', {'content': text, if (_newImage != null) 'image': _newImage});
      } else {
        await apiClient.post('/community/posts/${widget.postId}/comments', {'content': text, if (_newImage != null) 'image': _newImage});
      }
      _text.clear();
      setState(() {
        _newImage = null;
        _editing = null;
      });
      await _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _deleteComment(FeedComment c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ลบความคิดเห็นนี้?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('ยกเลิก')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('ลบ', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await apiClient.delete('/community/comments/${c.commentId}');
      await _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  void _startEdit(FeedComment c) {
    setState(() {
      _editing = c;
      _newImage = null;
      _text.text = c.content;
    });
    _focus.requestFocus();
  }

  Uint8List _bytes(String dataUrl) => decodeDataUrl(dataUrl);

  Widget _comment(FeedComment c) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          GestureDetector(onTap: () => openProfile(context, c.author.username), child: AuthorAvatar(author: c.author, radius: 16)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(14)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(child: GestureDetector(onTap: () => openProfile(context, c.author.username), child: AuthorName(author: c.author, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)))),
                    if (!c.isMine && !c.author.isMe && !c.author.isFollowing) ...[const SizedBox(width: 6), GestureDetector(onTap: () => openProfile(context, c.author.username), child: const Text('ดูโปรไฟล์', style: TextStyle(fontSize: 11, color: AppColors.rareBlue)))],
                  ]),
                  if (c.content.isNotEmpty) HashtagText(text: c.content),
                  if (c.hasImage)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.network(c.imageUrl, height: 160, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const SizedBox(height: 60))),
                    ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 8, top: 2),
                child: Row(children: [
                  Text('${timeAgo(c.createdAt)}${c.edited ? ' · แก้ไขแล้ว' : ''}', style: const TextStyle(color: Colors.grey, fontSize: 11)),
                  if (c.isMine) ...[
                    const SizedBox(width: 12),
                    GestureDetector(onTap: () => _startEdit(c), child: const Text('แก้ไข', style: TextStyle(fontSize: 12, color: AppColors.rareBlue))),
                    const SizedBox(width: 12),
                    GestureDetector(onTap: () => _deleteComment(c), child: const Text('ลบ', style: TextStyle(fontSize: 12, color: Colors.red))),
                  ],
                ]),
              ),
            ]),
          ),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final post = _post;
    return Scaffold(
      appBar: AppBar(title: const Text('โพสต์')),
      body: _error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
          : post == null
              ? const Center(child: CircularProgressIndicator())
              : Column(children: [
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _load,
                      child: ListView(padding: const EdgeInsets.all(16), children: [
                        PostCard(post: post, detail: true, onChanged: () => setState(() {}), onDeleted: () => Navigator.of(context).pop(), onComment: _focus.requestFocus, onReload: _load),
                        Text('ความคิดเห็น (${_comments.length})', style: const TextStyle(fontWeight: FontWeight.bold)),
                        if (_comments.isEmpty) const Padding(padding: EdgeInsets.all(20), child: Center(child: Text('ยังไม่มีความคิดเห็น', style: TextStyle(color: Colors.grey)))),
                        ..._comments.map(_comment),
                      ]),
                    ),
                  ),
                  SafeArea(
                    top: false,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
                      decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: Color(0xFFE3E7EF)))),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        if (_editing != null) Row(children: [const Text('กำลังแก้ไขความคิดเห็น', style: TextStyle(color: Colors.grey, fontSize: 12)), const Spacer(), TextButton(onPressed: () => setState(() {
                              _editing = null;
                              _text.clear();
                              _newImage = null;
                            }), child: const Text('ยกเลิก'))]),
                        if (_newImage != null)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Stack(children: [
                              ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.memory(_bytes(_newImage!), height: 70)),
                              Positioned(top: 2, right: 2, child: GestureDetector(onTap: () => setState(() => _newImage = null), child: const CircleAvatar(radius: 10, backgroundColor: Colors.black54, child: Icon(Icons.close, size: 12, color: Colors.white)))),
                            ]),
                          ),
                        Row(children: [
                          IconButton(icon: const Icon(Icons.add_photo_alternate_outlined, color: AppColors.navy), tooltip: 'แนบรูป', onPressed: _pickImage),
                          Expanded(child: TextField(controller: _text, focusNode: _focus, maxLength: 1000, minLines: 1, maxLines: 3, decoration: const InputDecoration(hintText: 'แสดงความคิดเห็น...', counterText: '', border: InputBorder.none))),
                          IconButton(onPressed: _sending ? null : _send, icon: const Icon(Icons.send, color: AppColors.navy)),
                        ]),
                      ]),
                    ),
                  ),
                ]),
    );
  }
}
