import '../services/api_client.dart' show apiBaseUrlOf;
import 'models.dart';

/// A quest proposed by a user (status: pending | approved | rejected | closed).
class Quest {
  final String questId;
  final String title;
  final String description;
  final String locationId;
  final String locationName;
  final String province;
  final String? startDate;
  final String? endDate;
  final bool permanent;
  final String status;
  final String? rejectReason;
  final String? phase; // upcoming | active | ended (approved quests only)
  final bool hasCover;
  final bool claimedByMe;
  final String? creatorUsername;
  final QuestCard? card;

  Quest({
    required this.questId,
    required this.title,
    required this.description,
    required this.locationId,
    required this.locationName,
    required this.province,
    this.startDate,
    this.endDate,
    required this.permanent,
    required this.status,
    this.rejectReason,
    this.phase,
    required this.hasCover,
    this.claimedByMe = false,
    this.creatorUsername,
    this.card,
  });

  String? get coverUrl => hasCover ? '${apiBaseUrlOf()}/media/quest/$questId/cover' : null;

  String get period => permanent ? 'ภารกิจถาวร' : '$startDate ถึง $endDate';

  factory Quest.fromJson(Map<String, dynamic> j) => Quest(
        questId: j['quest_id'],
        title: j['title'],
        description: j['description'] ?? '',
        locationId: j['location_id'],
        locationName: j['location_name'] ?? '',
        province: j['province'] ?? '',
        startDate: j['start_date'],
        endDate: j['end_date'],
        permanent: j['permanent'] == true,
        status: j['status'],
        rejectReason: j['reject_reason'],
        phase: j['phase'],
        hasCover: j['has_cover'] == true,
        claimedByMe: j['claimed_by_me'] == true,
        creatorUsername: j['creator_username'],
        card: j['card'] == null ? null : QuestCard.fromJson(j['card']),
      );
}

class QuestCard {
  final String templateId;
  final String name;
  final String rarity;
  final String? lore;
  final int? mintLimit;
  final int mintedCount;
  final int? remaining;
  final bool hasImage;

  QuestCard({
    required this.templateId,
    required this.name,
    required this.rarity,
    this.lore,
    this.mintLimit,
    required this.mintedCount,
    this.remaining,
    required this.hasImage,
  });

  String? get imageUrl => hasImage ? '${apiBaseUrlOf()}/media/card/$templateId' : null;

  factory QuestCard.fromJson(Map<String, dynamic> j) => QuestCard(
        templateId: j['template_id'],
        name: j['name'],
        rarity: normalizeRarity(j['rarity']),
        lore: j['lore'],
        mintLimit: j['mint_limit'],
        mintedCount: j['minted_count'] ?? 0,
        remaining: j['remaining'],
        hasImage: j['has_image'] == true,
      );
}

class TradeParty {
  final String userId;
  final String username;
  final String name;
  TradeParty(this.userId, this.username, this.name);
  factory TradeParty.fromJson(Map<String, dynamic> j) => TradeParty(j['user_id'], j['username'], j['name'] ?? '');
}

class Trade {
  final String tradeId;
  final String mode; // gift | swap
  final String status; // pending | accepted | rejected | cancelled | expired
  final String createdAt;
  final String expiresAt;
  final TradeParty from;
  final TradeParty to;
  final TravelCard offered;
  final TravelCard? requested;

  Trade({
    required this.tradeId,
    required this.mode,
    required this.status,
    required this.createdAt,
    required this.expiresAt,
    required this.from,
    required this.to,
    required this.offered,
    this.requested,
  });

  factory Trade.fromJson(Map<String, dynamic> j) => Trade(
        tradeId: j['trade_id'],
        mode: j['mode'],
        status: j['status'],
        createdAt: j['created_at'],
        expiresAt: j['expires_at'],
        from: TradeParty.fromJson(j['from']),
        to: TradeParty.fromJson(j['to']),
        offered: TravelCard.fromJson(j['offered_card']),
        requested: j['requested_card'] == null ? null : TravelCard.fromJson(j['requested_card']),
      );
}

class AppNotification {
  final String id;
  final String type;
  final String text;
  final bool read;
  final String createdAt;
  final Map<String, dynamic>? data;
  AppNotification({required this.id, required this.type, required this.text, required this.read, required this.createdAt, this.data});

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
        id: j['notification_id'],
        type: j['type'],
        text: j['text'],
        read: j['read_at'] != null,
        createdAt: j['created_at'],
        data: j['data'] as Map<String, dynamic>?,
      );
}

class RankInfo {
  final String name;
  final int level;
  final int min;
  final String? nextName;
  final int? nextMin;
  RankInfo({required this.name, required this.level, required this.min, this.nextName, this.nextMin});
  factory RankInfo.fromJson(Map<String, dynamic> j) =>
      RankInfo(name: j['name'], level: j['level'], min: j['min'], nextName: j['next_name'], nextMin: j['next_min']);
}

class RegionProgress {
  final String region;
  final int collected;
  final int total;
  final int percent;
  RegionProgress(this.region, this.collected, this.total, this.percent);
  factory RegionProgress.fromJson(Map<String, dynamic> j) => RegionProgress(j['region'], j['collected'], j['total'], j['percent']);
}

class ShowcaseStats {
  final int placesConquered;
  final int totalCards;
  final int points;
  final RankInfo rank;
  final Map<String, int> byRarity;
  final List<RegionProgress> regions;
  ShowcaseStats({
    required this.placesConquered,
    required this.totalCards,
    required this.points,
    required this.rank,
    required this.byRarity,
    required this.regions,
  });
  factory ShowcaseStats.fromJson(Map<String, dynamic> j) => ShowcaseStats(
        placesConquered: j['places_conquered'] ?? 0,
        totalCards: j['total_cards'] ?? 0,
        points: j['collector_points'] ?? 0,
        rank: RankInfo.fromJson(j['rank']),
        byRarity: (j['by_rarity'] as Map<String, dynamic>).map((k, v) => MapEntry(k, v as int)),
        regions: (j['regions'] as List).map((e) => RegionProgress.fromJson(e)).toList(),
      );
}

class ProfileData {
  final String userId;
  final String username;
  final String name;
  final List<TravelCard> pins;
  final ShowcaseStats stats;
  ProfileData({required this.userId, required this.username, required this.name, required this.pins, required this.stats});
  factory ProfileData.fromJson(Map<String, dynamic> j) => ProfileData(
        userId: j['user']['user_id'],
        username: j['user']['username'],
        name: j['user']['name'] ?? '',
        pins: (j['pins'] as List).map((e) => TravelCard.fromJson(e)).toList(),
        stats: ShowcaseStats.fromJson(j['stats']),
      );
}
