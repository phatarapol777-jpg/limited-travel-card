import 'package:flutter/material.dart';
import '../services/api_client.dart';

/// Bumped when something that appears inside posts changed (display name, picture, badge, a new post...), so every open feed reloads.
final ValueNotifier<int> communityRefresh = ValueNotifier<int>(0);

/// Who the signed-in user follows, as far as this session knows (username -> followed). A follow button anywhere updates it, so every
/// button for that person (on posts, comments, search, profile) shows the same state at once.
final ValueNotifier<Map<String, bool>> followState = ValueNotifier<Map<String, bool>>({});

/// True when a follow or unfollow happened and the "following" feed should be fetched again when it is opened.
bool followingFeedStale = false;

const reactionTypes = ['LIKE', 'LOVE', 'WOW', 'SAD', 'ANGRY'];
const reactionEmoji = {'LIKE': '👍', 'LOVE': '❤️', 'WOW': '😮', 'SAD': '😢', 'ANGRY': '😡'};
const reactionLabel = {'LIKE': 'ถูกใจ', 'LOVE': 'รักเลย', 'WOW': 'ว้าว', 'SAD': 'เศร้า', 'ANGRY': 'โกรธ'};

String postImageUrl(String imageId) => '$apiBaseUrl/media/post-image/$imageId';
String commentImageUrl(String commentId) => '$apiBaseUrl/media/comment-image/$commentId';
String avatarUrl(String username, int rev) => '$apiBaseUrl/media/avatar/${Uri.encodeComponent(username)}?v=$rev';
String coverUrl(String username, int rev) => '$apiBaseUrl/media/cover/${Uri.encodeComponent(username)}?v=$rev';

class AuthorBadge {
  final String badgeId;
  final String icon; // gold | silver | bronze | star
  final String title;
  final int rank;
  final String month;
  AuthorBadge({required this.badgeId, required this.icon, required this.title, required this.rank, required this.month});

  Color get color {
    switch (icon) {
      case 'gold':
        return const Color(0xFFD4AF37);
      case 'silver':
        return const Color(0xFF9AA5B1);
      case 'bronze':
        return const Color(0xFFB87333);
      default:
        return const Color(0xFF7A4F9E);
    }
  }

  factory AuthorBadge.fromJson(Map<String, dynamic> j) => AuthorBadge(
        badgeId: j['badge_id'],
        icon: j['icon'] ?? 'star',
        title: j['title'] ?? '',
        rank: (j['rank'] as num?)?.toInt() ?? 0,
        month: j['month'] ?? '',
      );
}

/// Who wrote something: only the display name, the picture and the badge they chose to show.
class Author {
  final String username;
  final String displayName;
  final bool hasAvatar;
  final int avatarRev;
  final AuthorBadge? badge;
  final bool isMe;
  final bool _isFollowing;
  Author({required this.username, required this.displayName, this.hasAvatar = false, this.avatarRev = 0, this.badge, this.isMe = false, bool isFollowing = false}) : _isFollowing = isFollowing;

  bool get isFollowing => followState.value[username] ?? _isFollowing;

  String? get avatar => hasAvatar ? avatarUrl(username, avatarRev) : null;

  factory Author.fromJson(Map<String, dynamic>? j) {
    if (j == null) return Author(username: '', displayName: 'ผู้ใช้');
    return Author(
      username: j['username'] ?? '',
      displayName: j['display_name'] ?? j['username'] ?? 'ผู้ใช้',
      hasAvatar: j['has_avatar'] == true,
      avatarRev: (j['avatar_rev'] as num?)?.toInt() ?? 0,
      badge: j['badge'] == null ? null : AuthorBadge.fromJson(j['badge'] as Map<String, dynamic>),
      isMe: j['is_me'] == true,
      isFollowing: j['is_following'] == true,
    );
  }
}

class PlaceRef {
  final String locationId;
  final String name;
  final String? province;
  PlaceRef({required this.locationId, required this.name, this.province});
  factory PlaceRef.fromJson(Map<String, dynamic> j) => PlaceRef(locationId: j['location_id'], name: j['name'], province: j['province']);
}

class FeedPost {
  final String postId;
  final Author author;
  final String content;
  final String? legacyEmoji;
  final List<String> imageIds;
  final PlaceRef? place;
  final List<String> hashtags;
  final String createdAt;
  final bool edited;
  Map<String, int> reactions;
  String? myReaction;
  int commentCount;
  final bool isMine;
  bool reportedByMe;

  FeedPost({
    required this.postId,
    required this.author,
    required this.content,
    this.legacyEmoji,
    this.imageIds = const [],
    this.place,
    this.hashtags = const [],
    required this.createdAt,
    this.edited = false,
    this.reactions = const {},
    this.myReaction,
    this.commentCount = 0,
    this.isMine = false,
    this.reportedByMe = false,
  });

  int get reactionCount => reactions.values.fold(0, (a, b) => a + b);

  /// The reaction kinds used on this post, most used first (for the little emoji stack).
  List<String> get topReactions {
    final entries = reactions.entries.where((e) => e.value > 0).toList()..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(3).map((e) => e.key).toList();
  }

  void applyReactions(Map<String, dynamic> j) {
    reactions = {for (final e in (j['reactions'] as Map<String, dynamic>).entries) e.key: (e.value as num).toInt()};
    myReaction = j['my_reaction'] as String?;
  }

  factory FeedPost.fromJson(Map<String, dynamic> j) => FeedPost(
        postId: j['post_id'],
        author: Author.fromJson(j['author'] as Map<String, dynamic>?),
        content: j['content'] ?? '',
        legacyEmoji: j['image_emoji'],
        imageIds: ((j['images'] as List?) ?? const []).map((e) => '$e').toList(),
        place: j['location'] == null ? null : PlaceRef.fromJson(j['location'] as Map<String, dynamic>),
        hashtags: ((j['hashtags'] as List?) ?? const []).map((e) => '$e').toList(),
        createdAt: j['created_at'] ?? j['timestamp'] ?? '',
        edited: j['updated_at'] != null && j['updated_at'] != j['created_at'],
        reactions: {for (final e in ((j['reactions'] as Map<String, dynamic>?) ?? const {}).entries) e.key: (e.value as num).toInt()},
        myReaction: j['my_reaction'] as String?,
        commentCount: (j['comment_count'] as num?)?.toInt() ?? 0,
        isMine: j['is_mine'] == true,
        reportedByMe: j['reported_by_me'] == true,
      );
}

class FeedComment {
  final String commentId;
  final Author author;
  final String content;
  final bool hasImage;
  final String createdAt;
  final bool edited;
  final bool isMine;
  FeedComment({required this.commentId, required this.author, required this.content, this.hasImage = false, required this.createdAt, this.edited = false, this.isMine = false});

  String get imageUrl => commentImageUrl(commentId);

  factory FeedComment.fromJson(Map<String, dynamic> j) => FeedComment(
        commentId: j['comment_id'],
        author: Author.fromJson(j['author'] as Map<String, dynamic>?),
        content: j['content'] ?? '',
        hasImage: j['has_image'] == true,
        createdAt: j['created_at'] ?? '',
        edited: j['edited'] == true,
        isMine: j['is_mine'] == true,
      );
}

class CommunityStats {
  final int posts;
  final int placesCheckedIn;
  final int followers;
  final int following;
  CommunityStats({this.posts = 0, this.placesCheckedIn = 0, this.followers = 0, this.following = 0});
  factory CommunityStats.fromJson(Map<String, dynamic> j) => CommunityStats(
        posts: (j['posts'] as num?)?.toInt() ?? 0,
        placesCheckedIn: (j['places_checked_in'] as num?)?.toInt() ?? 0,
        followers: (j['followers'] as num?)?.toInt() ?? 0,
        following: (j['following'] as num?)?.toInt() ?? 0,
      );
}

class CommunityProfile {
  final Author author;
  final String bio;
  final bool hasCover;
  final CommunityStats stats;
  final List<AuthorBadge> badges;
  bool isFollowing;
  final bool isMe;
  final bool badgeVisible;
  final String? selectedBadgeId;
  CommunityProfile({
    required this.author,
    this.bio = '',
    this.hasCover = false,
    required this.stats,
    this.badges = const [],
    this.isFollowing = false,
    this.isMe = false,
    this.badgeVisible = true,
    this.selectedBadgeId,
  });

  String? get cover => hasCover ? coverUrl(author.username, author.avatarRev) : null;

  factory CommunityProfile.fromJson(Map<String, dynamic> j) => CommunityProfile(
        author: Author.fromJson(j),
        bio: j['bio'] ?? '',
        hasCover: j['has_cover'] == true,
        stats: CommunityStats.fromJson(j['stats'] as Map<String, dynamic>),
        badges: ((j['badges'] as List?) ?? const []).map((e) => AuthorBadge.fromJson(e as Map<String, dynamic>)).toList(),
        isFollowing: j['is_following'] == true,
        isMe: j['is_me'] == true,
        badgeVisible: j['is_badge_visible'] != false,
        selectedBadgeId: j['selected_badge_id'] as String?,
      );
}

class LeaderRow {
  final int rank;
  final int uniqueCount;
  final Author author;
  final bool isMe;
  LeaderRow({required this.rank, required this.uniqueCount, required this.author, this.isMe = false});
  factory LeaderRow.fromJson(Map<String, dynamic> j) => LeaderRow(
        rank: (j['rank'] as num).toInt(),
        uniqueCount: (j['unique_count'] as num).toInt(),
        author: Author.fromJson(j['author'] as Map<String, dynamic>?),
        isMe: j['is_me'] == true,
      );
}

/// "5 นาทีที่แล้ว", "เมื่อวาน", or a date for older posts.
String timeAgo(String iso) {
  final t = DateTime.tryParse(iso);
  if (t == null) return '';
  final d = DateTime.now().difference(t.toLocal());
  if (d.inSeconds < 60) return 'เมื่อสักครู่';
  if (d.inMinutes < 60) return '${d.inMinutes} นาทีที่แล้ว';
  if (d.inHours < 24) return '${d.inHours} ชั่วโมงที่แล้ว';
  if (d.inDays < 7) return '${d.inDays} วันที่แล้ว';
  final l = t.toLocal();
  return '${l.day}/${l.month}/${l.year + 543}';
}
