import 'package:flutter/material.dart';
import '../models/collection_models.dart';
import '../models/community_models.dart';
import '../models/models.dart';
import '../services/api_client.dart';
import '../theme.dart';
import '../widgets/card_widgets.dart';
import '../widgets/community_widgets.dart';
import '../widgets/profile_widgets.dart';
import 'community_feed_screen.dart';
import 'edit_community_profile_screen.dart';
import 'trade_composer_screen.dart';

/// A traveler's public page: cover, picture, display name with their badge, bio, travel statistics, follow button,
/// and two views: their posts (timeline) and their card showcase.
class CommunityProfileScreen extends StatefulWidget {
  final String username;

  /// Open on the card showcase (where the trade button is) instead of the posts.
  final bool initialShowCards;
  const CommunityProfileScreen({super.key, required this.username, this.initialShowCards = false});

  @override
  State<CommunityProfileScreen> createState() => _CommunityProfileScreenState();
}

class _CommunityProfileScreenState extends State<CommunityProfileScreen> {
  CommunityProfile? _p;
  String? _error;
  bool _showCards = false;
  bool _busy = false;
  int _reload = 0;

  @override
  void initState() {
    super.initState();
    _showCards = widget.initialShowCards;
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await apiClient.get('/community/users/${Uri.encodeComponent(widget.username)}');
      if (mounted) {
        setState(() {
          _p = CommunityProfile.fromJson(data['profile'] as Map<String, dynamic>);
          _error = null;
        });
      }
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'โหลดโปรไฟล์ไม่สำเร็จ: $e');
    }
  }

  Future<void> _toggleFollow() async {
    final p = _p!;
    setState(() => _busy = true);
    try {
      if (p.isFollowing) {
        await apiClient.delete('/community/users/${p.author.username}/follow');
      } else {
        await apiClient.post('/community/users/${p.author.username}/follow');
      }
      followState.value = {...followState.value, p.author.username: !p.isFollowing};
      followingFeedStale = true;
      await _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit() async {
    final changed = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const EditCommunityProfileScreen()));
    if (changed == true) {
      await _load();
      if (mounted) setState(() => _reload++);
    }
  }

  void _people(String kind, String title) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _PeopleSheet(username: widget.username, kind: kind, title: title),
    );
  }

  Widget _stat(String label, int value, {VoidCallback? onTap}) => Expanded(
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(children: [
              Text('$value', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.navy)),
              Text(label, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ]),
          ),
        ),
      );

  Widget _header(CommunityProfile p) {
    final cover = p.cover;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Stack(clipBehavior: Clip.none, children: [
        LayoutBuilder(
          builder: (context, box) => ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: SizedBox(
              height: (box.maxWidth * 6 / 16).clamp(100.0, 190.0),
              child: cover != null
                  ? Image.network(cover, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const ColoredBox(color: AppColors.navy))
                  : const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(colors: [AppColors.navy, AppColors.rareBlue]))),
            ),
          ),
        ),
        Positioned(left: 16, bottom: -36, child: Container(padding: const EdgeInsets.all(3), decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle), child: AuthorAvatar(author: p.author, radius: 38))),
      ]),
      const SizedBox(height: 44),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            AuthorName(author: p.author, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            Text('@${p.author.username}', style: const TextStyle(color: Colors.grey)),
          ]),
        ),
        if (p.isMe)
          OutlinedButton.icon(icon: const Icon(Icons.edit, size: 18), label: const Text('แก้ไขโปรไฟล์'), onPressed: _edit)
        else
          p.isFollowing
              ? OutlinedButton(onPressed: _busy ? null : _toggleFollow, child: const Text('กำลังติดตาม'))
              : ElevatedButton(style: ElevatedButton.styleFrom(minimumSize: const Size(100, 40)), onPressed: _busy ? null : _toggleFollow, child: const Text('ติดตาม')),
      ]),
      if (p.bio.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(p.bio)),
      const SizedBox(height: 8),
      Card(
        margin: EdgeInsets.zero,
        child: Row(children: [
          _stat('โพสต์', p.stats.posts),
          _stat('สถานที่ที่เช็กอิน', p.stats.placesCheckedIn),
          _stat('ผู้ติดตาม', p.stats.followers, onTap: () => _people('followers', 'ผู้ติดตาม')),
          _stat('กำลังติดตาม', p.stats.following, onTap: () => _people('following', 'กำลังติดตาม')),
        ]),
      ),
      if (p.badges.isNotEmpty) ...[
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 4, children: p.badges.map((b) => Chip(avatar: Icon(Icons.workspace_premium, color: b.color, size: 18), label: Text(b.title, style: const TextStyle(fontSize: 11)), visualDensity: VisualDensity.compact)).toList()),
      ],
      const SizedBox(height: 12),
      SegmentedButton<bool>(
        segments: const [ButtonSegment(value: false, label: Text('โพสต์'), icon: Icon(Icons.article_outlined)), ButtonSegment(value: true, label: Text('ตู้โชว์การ์ด'), icon: Icon(Icons.style_outlined))],
        selected: {_showCards},
        onSelectionChanged: (v) => setState(() => _showCards = v.first),
      ),
      const SizedBox(height: 12),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    return Scaffold(
      appBar: AppBar(title: Text(p?.author.displayName ?? '@${widget.username}', overflow: TextOverflow.ellipsis)),
      body: _error != null
          ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
          : p == null
              ? const Center(child: CircularProgressIndicator())
              : _showCards
                  ? ListView(padding: const EdgeInsets.all(16), children: [_header(p), ProfileCardsSection(username: p.author.username, isMe: p.isMe)])
                  : FeedList(
                      key: ValueKey('timeline-$_reload'),
                      user: p.author.username,
                      header: _header(p),
                      emptyText: p.isMe ? 'คุณยังไม่มีโพสต์' : 'ยังไม่มีโพสต์',
                      reloadToken: _reload,
                    ),
    );
  }
}

class _PeopleSheet extends StatefulWidget {
  final String username;
  final String kind;
  final String title;
  const _PeopleSheet({required this.username, required this.kind, required this.title});

  @override
  State<_PeopleSheet> createState() => _PeopleSheetState();
}

class _PeopleSheetState extends State<_PeopleSheet> {
  List<Author>? _people;

  @override
  void initState() {
    super.initState();
    apiClient.get('/community/users/${Uri.encodeComponent(widget.username)}/${widget.kind}').then((d) {
      if (mounted) setState(() => _people = (d['users'] as List).map((e) => Author.fromJson(e as Map<String, dynamic>)).toList());
    }).catchError((_) {
      if (mounted) setState(() => _people = []);
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(children: [
          Padding(padding: const EdgeInsets.all(16), child: Text(widget.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
          Expanded(
            child: _people == null
                ? const Center(child: CircularProgressIndicator())
                : _people!.isEmpty
                    ? const Center(child: Text('ยังไม่มีรายชื่อ', style: TextStyle(color: Colors.grey)))
                    : ListView(
                        children: _people!
                            .map((a) => ListTile(
                                  leading: AuthorAvatar(author: a),
                                  title: AuthorName(author: a),
                                  subtitle: Text('@${a.username}'),
                                  trailing: FollowButton(author: a),
                                  onTap: () {
                                    Navigator.of(context).pop();
                                    openProfile(context, a.username);
                                  },
                                ))
                            .toList(),
                      ),
          ),
        ]),
      ),
    );
  }
}

/// Rank, statistics, pinned cards and region progress of a traveler, plus the button to start a trade with them.
class ProfileCardsSection extends StatefulWidget {
  final String username;
  final bool isMe;
  const ProfileCardsSection({super.key, required this.username, this.isMe = false});

  @override
  State<ProfileCardsSection> createState() => _ProfileCardsSectionState();
}

class _ProfileCardsSectionState extends State<ProfileCardsSection> {
  ProfileData? _profile;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await apiClient.get('/profile/${Uri.encodeComponent(widget.username)}');
      if (mounted) setState(() => _profile = ProfileData.fromJson(data));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'โหลดข้อมูลการ์ดไม่สำเร็จ: $e');
    }
  }

  // Start a trade by picking one of your own cards first.
  Future<void> _startTrade() async {
    TravelCard? mine;
    try {
      final data = await apiClient.get('/cards');
      final cards = (data['cards'] as List).map((e) => TravelCard.fromJson(e)).where((c) => c.activationStatus == 'CLAIMED').toList();
      if (!mounted) return;
      if (cards.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('คุณยังไม่มีการ์ดที่แลกเปลี่ยนได้')));
        return;
      }
      mine = await showModalBottomSheet<TravelCard>(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (ctx) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          builder: (ctx, controller) => Column(children: [
            const Padding(padding: EdgeInsets.all(16), child: Text('เลือกการ์ดของคุณที่จะส่ง', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
            Expanded(
              child: GridView.builder(
                controller: controller,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 120, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 0.71),
                itemCount: cards.length,
                itemBuilder: (_, i) => InkWell(onTap: () => Navigator.of(ctx).pop(cards[i]), child: CardFace(card: cards[i])),
              ),
            ),
          ]),
        ),
      );
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('โหลดการ์ดไม่สำเร็จ: $e')));
    }
    if (mine != null && mounted) {
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => TradeComposerScreen(card: mine!, recipientUsername: widget.username)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _profile;
    if (_error != null) return Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center));
    if (p == null) return const Padding(padding: EdgeInsets.all(30), child: Center(child: CircularProgressIndicator()));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      RankCard(stats: p.stats),
      const SizedBox(height: 14),
      StatBoxes(stats: p.stats),
      const SizedBox(height: 20),
      const Text('ตู้โชว์การ์ดเด่น', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      const SizedBox(height: 10),
      Showcase(pins: p.pins, empty: 'ยังไม่ได้ปักหมุดการ์ด'),
      const SizedBox(height: 20),
      RegionProgressList(regions: p.stats.regions),
      if (!widget.isMe) ...[
        const SizedBox(height: 22),
        ElevatedButton.icon(icon: const Icon(Icons.swap_horiz), label: const Text('เทรด / ส่งการ์ดให้คนนี้'), onPressed: _startTrade),
      ],
      const SizedBox(height: 30),
    ]);
  }
}
