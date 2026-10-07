import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/community_models.dart';
import '../services/api_client.dart';
import '../theme.dart';
import '../screens/community_feed_screen.dart';
import '../screens/community_profile_screen.dart';
import '../screens/post_composer_screen.dart';
import '../screens/post_detail_screen.dart';
import 'place_detail.dart';

class AuthorAvatar extends StatelessWidget {
  final Author author;
  final double radius;
  const AuthorAvatar({super.key, required this.author, this.radius = 20});

  @override
  Widget build(BuildContext context) {
    final url = author.avatar;
    final letter = author.displayName.isEmpty ? '?' : author.displayName.characters.first.toUpperCase();
    return CircleAvatar(
      radius: radius,
      backgroundColor: AppColors.navy,
      foregroundImage: url != null ? NetworkImage(url) : null,
      child: Text(letter, style: TextStyle(color: Colors.white, fontSize: radius * 0.9)),
    );
  }
}

class BadgeIcon extends StatelessWidget {
  final AuthorBadge badge;
  final double size;
  const BadgeIcon({super.key, required this.badge, this.size = 16});

  @override
  Widget build(BuildContext context) => Tooltip(message: badge.title, child: Icon(Icons.workspace_premium, color: badge.color, size: size));
}

/// The display name with the chosen badge right after it (hidden when the person switched it off).
class AuthorName extends StatelessWidget {
  final Author author;
  final TextStyle? style;
  const AuthorName({super.key, required this.author, this.style});

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Flexible(child: Text(author.displayName, overflow: TextOverflow.ellipsis, style: style ?? const TextStyle(fontWeight: FontWeight.bold))),
      if (author.badge != null) ...[const SizedBox(width: 4), BadgeIcon(badge: author.badge!)],
    ]);
  }
}

void openProfile(BuildContext context, String username) {
  if (username.isEmpty || username == 'deleted') return;
  Navigator.of(context).push(MaterialPageRoute(builder: (_) => CommunityProfileScreen(username: username)));
}

/// Up to ten pictures of a post: one big, two side by side, or a grid; tap to view full screen.
class PostImages extends StatelessWidget {
  final List<String> imageIds;
  const PostImages({super.key, required this.imageIds});

  void _view(BuildContext context, int index) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(children: [
          PageView(
            controller: PageController(initialPage: index),
            children: imageIds.map((id) => InteractiveViewer(child: Center(child: Image.network(postImageUrl(id), fit: BoxFit.contain)))).toList(),
          ),
          Positioned(top: 8, right: 8, child: IconButton(icon: const Icon(Icons.close, color: Colors.white), onPressed: () => Navigator.of(ctx).pop())),
        ]),
      ),
    );
  }

  Widget _tile(BuildContext context, int i, {double? height}) => GestureDetector(
        onTap: () => _view(context, i),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            height: height,
            width: double.infinity,
            child: Image.network(postImageUrl(imageIds[i]), fit: BoxFit.cover, errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFFE3E7EF), child: Icon(Icons.image_not_supported_outlined, color: Colors.grey))),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final n = imageIds.length;
    if (n == 0) return const SizedBox.shrink();
    if (n == 1) return AspectRatio(aspectRatio: 4 / 3, child: _tile(context, 0));
    if (n == 2) return SizedBox(height: 180, child: Row(children: [Expanded(child: _tile(context, 0)), const SizedBox(width: 4), Expanded(child: _tile(context, 1))]));
    final shown = n > 6 ? 6 : n;
    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 3,
      mainAxisSpacing: 4,
      crossAxisSpacing: 4,
      children: [
        for (var i = 0; i < shown; i++)
          Stack(fit: StackFit.expand, children: [
            _tile(context, i),
            if (i == shown - 1 && n > shown)
              IgnorePointer(child: ClipRRect(borderRadius: BorderRadius.circular(10), child: ColoredBox(color: Colors.black54, child: Center(child: Text('+${n - shown}', style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)))))),
          ]),
      ],
    );
  }
}

/// Text with #hashtags that open the feed for that tag.
class HashtagText extends StatelessWidget {
  final String text;
  const HashtagText({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in RegExp(r'#[\p{L}\p{M}\p{N}_]{1,40}', unicode: true).allMatches(text)) {
      if (m.start > last) spans.add(TextSpan(text: text.substring(last, m.start)));
      final tag = m.group(0)!;
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: GestureDetector(
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => CommunityFeedScreen(tag: tag.substring(1), title: tag))),
          child: Text(tag, style: const TextStyle(color: AppColors.rareBlue, fontWeight: FontWeight.w600)),
        ),
      ));
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return Text.rich(TextSpan(style: DefaultTextStyle.of(context).style, children: spans));
  }
}

class PlaceChip extends StatelessWidget {
  final PlaceRef place;
  const PlaceChip({super.key, required this.place});

  @override
  Widget build(BuildContext context) => ActionChip(
        avatar: const Icon(Icons.place, size: 16, color: Colors.redAccent),
        label: Text(place.province == null ? place.name : '${place.name} · ${place.province}'),
        visualDensity: VisualDensity.compact,
        onPressed: () => openPlace(context, place.locationId),
      );
}

const _reportReasons = ['สแปมหรือโฆษณา', 'คำพูดหยาบคาย/ก้าวร้าว', 'ข้อมูลเท็จ', 'เนื้อหาไม่เหมาะสม', 'ละเมิดความเป็นส่วนตัว'];

/// One post in a list or on its own page: author, text, pictures, place tag, reactions, comments, share and the ... menu.
class PostCard extends StatefulWidget {
  final FeedPost post;
  final VoidCallback? onChanged;
  final VoidCallback? onDeleted;

  /// On the post's own page the comment button does not open another page.
  final bool detail;
  final VoidCallback? onComment;

  /// Called after the post was edited, so the owner of the list can fetch it again.
  final VoidCallback? onReload;
  const PostCard({super.key, required this.post, this.onChanged, this.onDeleted, this.detail = false, this.onComment, this.onReload});

  @override
  State<PostCard> createState() => _PostCardState();
}

class _PostCardState extends State<PostCard> {
  bool _busy = false;
  FeedPost get post => widget.post;

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _react(String? type) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final data = type == null ? await apiClient.delete('/community/posts/${post.postId}/reaction') : await apiClient.put('/community/posts/${post.postId}/reaction', {'type': type});
      post.applyReactions(data as Map<String, dynamic>);
      widget.onChanged?.call();
    } on ApiException catch (e) {
      _snack(e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _picker() {
    showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: reactionTypes
                .map((t) => InkWell(
                      borderRadius: BorderRadius.circular(30),
                      onTap: () {
                        Navigator.of(ctx).pop();
                        _react(post.myReaction == t ? null : t);
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Text(reactionEmoji[t]!, style: TextStyle(fontSize: post.myReaction == t ? 40 : 32)),
                          Text(reactionLabel[t]!, style: TextStyle(fontSize: 11, fontWeight: post.myReaction == t ? FontWeight.bold : FontWeight.normal)),
                        ]),
                      ),
                    ))
                .toList(),
          ),
        ),
      ),
    );
  }

  Future<void> _share() async {
    final link = '${Uri.base.origin}/?post=${post.postId}';
    await Clipboard.setData(ClipboardData(text: link));
    _snack('คัดลอกลิงก์โพสต์แล้ว');
  }

  Future<void> _report() async {
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('รายงานโพสต์นี้เพราะ...'),
        children: _reportReasons.map((r) => SimpleDialogOption(onPressed: () => Navigator.of(ctx).pop(r), child: Text(r))).toList(),
      ),
    );
    if (reason == null) return;
    try {
      await apiClient.post('/community/posts/${post.postId}/report', {'reason': reason});
      post.reportedByMe = true;
      widget.onChanged?.call();
      _snack('ส่งรายงานแล้ว แอดมินจะตรวจสอบ');
    } on ApiException catch (e) {
      _snack(e.message);
    }
  }

  Future<void> _edit() async {
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => PostComposerScreen(existingPostId: post.postId)));
    if (changed == true) widget.onReload?.call();
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ลบโพสต์นี้?'),
        content: const Text('โพสต์ รูปภาพ และความคิดเห็นทั้งหมดจะถูกลบถาวร'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('ยกเลิก')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('ลบ', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await apiClient.delete('/community/posts/${post.postId}');
      widget.onDeleted?.call();
    } on ApiException catch (e) {
      _snack(e.message);
    }
  }

  void _open() {
    if (widget.detail) return;
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => PostDetailScreen(postId: post.postId))).then((_) => widget.onChanged?.call());
  }

  @override
  Widget build(BuildContext context) {
    final mine = post.myReaction;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 6, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            GestureDetector(onTap: () => openProfile(context, post.author.username), child: AuthorAvatar(author: post.author)),
            const SizedBox(width: 10),
            Expanded(
              child: GestureDetector(
                onTap: () => openProfile(context, post.author.username),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  AuthorName(author: post.author),
                  Text('${timeAgo(post.createdAt)}${post.edited ? ' · แก้ไขแล้ว' : ''}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                ]),
              ),
            ),
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'edit') _edit();
                if (v == 'delete') _delete();
                if (v == 'report') _report();
                if (v == 'share') _share();
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'share', child: Text('คัดลอกลิงก์โพสต์')),
                if (post.isMine) ...[const PopupMenuItem(value: 'edit', child: Text('แก้ไขโพสต์')), const PopupMenuItem(value: 'delete', child: Text('ลบโพสต์', style: TextStyle(color: Colors.red)))],
                if (!post.isMine) PopupMenuItem(value: 'report', enabled: !post.reportedByMe, child: Text(post.reportedByMe ? 'รายงานแล้ว' : 'รายงานโพสต์')),
              ],
            ),
          ]),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _open,
            child: Padding(
              padding: const EdgeInsets.only(right: 8, top: 4),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (post.content.isNotEmpty) HashtagText(text: post.content),
                if (post.legacyEmoji != null)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    height: 90,
                    width: double.infinity,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: AppColors.bg, borderRadius: BorderRadius.circular(12)),
                    child: Text(post.legacyEmoji!, style: const TextStyle(fontSize: 38)),
                  ),
                if (post.imageIds.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: PostImages(imageIds: post.imageIds)),
              ]),
            ),
          ),
          if (post.place != null) Padding(padding: const EdgeInsets.only(top: 8), child: PlaceChip(place: post.place!)),
          const SizedBox(height: 6),
          if (post.reactionCount > 0 || post.commentCount > 0)
            Padding(
              padding: const EdgeInsets.only(right: 8, bottom: 2),
              child: Row(children: [
                if (post.reactionCount > 0) ...[Text(post.topReactions.map((t) => reactionEmoji[t]).join(), style: const TextStyle(fontSize: 14)), const SizedBox(width: 4), Text('${post.reactionCount}', style: const TextStyle(color: Colors.grey))],
                const Spacer(),
                if (post.commentCount > 0) GestureDetector(onTap: widget.onComment ?? _open, child: Text('${post.commentCount} ความคิดเห็น', style: const TextStyle(color: Colors.grey))),
              ]),
            ),
          const Divider(height: 8),
          Row(children: [
            Expanded(
              child: TextButton.icon(
                icon: mine == null ? const Icon(Icons.thumb_up_alt_outlined, size: 18) : Text(reactionEmoji[mine]!, style: const TextStyle(fontSize: 16)),
                label: Text(mine == null ? 'ถูกใจ' : reactionLabel[mine]!, style: TextStyle(color: mine == null ? Colors.grey.shade700 : AppColors.navy, fontWeight: mine == null ? null : FontWeight.bold)),
                onPressed: () => _react(mine == null ? 'LIKE' : null),
              ),
            ),
            IconButton(tooltip: 'เลือกอารมณ์ความรู้สึก', icon: const Icon(Icons.add_reaction_outlined, size: 20), onPressed: _picker),
            Expanded(child: TextButton.icon(icon: const Icon(Icons.mode_comment_outlined, size: 18), label: Text('คอมเมนต์', style: TextStyle(color: Colors.grey.shade700)), onPressed: widget.onComment ?? _open)),
            IconButton(tooltip: 'คัดลอกลิงก์', icon: const Icon(Icons.share_outlined, size: 20), onPressed: _share),
          ]),
        ]),
      ),
    );
  }
}
