import '../services/api_client.dart' show apiBaseUrl;

class AppUser {
  final String userId;
  final String username;
  final String firstName;
  final String lastName;
  final String email;
  final String? phone;
  final bool isAdmin;
  final bool hasFace;

  AppUser({
    required this.userId,
    required this.username,
    required this.firstName,
    required this.lastName,
    required this.email,
    this.phone,
    this.isAdmin = false,
    this.hasFace = false,
  });

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        userId: j['user_id'],
        username: j['username'],
        firstName: j['first_name'],
        lastName: j['last_name'],
        email: j['email'],
        phone: j['phone'],
        isAdmin: j['is_admin'] == 1 || j['is_admin'] == true,
        hasFace: j['has_face'] == true,
      );
}

class UserStats {
  final int cards;
  final int placesVisited;
  final int missionsCompleted;
  UserStats({required this.cards, required this.placesVisited, required this.missionsCompleted});

  factory UserStats.fromJson(Map<String, dynamic> j) => UserStats(
        cards: j['cards'] ?? 0,
        placesVisited: j['places_visited'] ?? 0,
        missionsCompleted: j['missions_completed'] ?? 0,
      );
}

class TravelLocation {
  final String locationId;
  final String name;
  final String? description;
  final double latitude;
  final double longitude;
  final String province;
  final String icon;
  final String? cardTemplateId;
  final bool cardHasImage;
  final int cardImageRev;

  TravelLocation({
    required this.locationId,
    required this.name,
    this.description,
    required this.latitude,
    required this.longitude,
    required this.province,
    required this.icon,
    this.cardTemplateId,
    this.cardHasImage = false,
    this.cardImageRev = 0,
  });

  /// The picture the admin uploaded for this place's card (shown on the map pin), or null.
  String? get pinImageUrl => (cardHasImage && cardTemplateId != null) ? '$apiBaseUrl/media/card/$cardTemplateId?v=$cardImageRev' : null;

  factory TravelLocation.fromJson(Map<String, dynamic> j) => TravelLocation(
        locationId: j['location_id'],
        name: j['name'],
        description: j['description'],
        latitude: (j['latitude'] as num).toDouble(),
        longitude: (j['longitude'] as num).toDouble(),
        province: j['province'],
        icon: j['icon'] ?? 'place',
        cardTemplateId: j['card_template_id'],
        cardHasImage: j['card_has_image'] == true,
        cardImageRev: (j['card_image_rev'] as num?)?.toInt() ?? 0,
      );
}

class Shop {
  final String shopId;
  final String shopName;
  final double rating;
  final String icon;
  final String? locationName;

  Shop({required this.shopId, required this.shopName, required this.rating, required this.icon, this.locationName});

  factory Shop.fromJson(Map<String, dynamic> j) => Shop(
        shopId: j['shop_id'],
        shopName: j['shop_name'],
        rating: (j['rating'] as num?)?.toDouble() ?? 0,
        icon: j['icon'] ?? 'store',
        locationName: j['location_name'],
      );
}

class Mission {
  final String missionId;
  final String locationId;
  final String title;
  final String description;
  final String status;
  final bool completed;
  final String? locationName;

  Mission({
    required this.missionId,
    required this.locationId,
    required this.title,
    required this.description,
    required this.status,
    required this.completed,
    this.locationName,
  });

  factory Mission.fromJson(Map<String, dynamic> j) => Mission(
        missionId: j['mission_id'],
        locationId: j['location_id'],
        title: j['title'],
        description: j['description'],
        status: j['status'],
        completed: j['completed'] == true,
        locationName: j['location_name'],
      );
}

/// Rarity names changed from common/epic to normal/special; accept both from older data.
String normalizeRarity(String? r) {
  switch ((r ?? '').toLowerCase()) {
    case 'common':
    case 'normal':
      return 'normal';
    case 'epic':
    case 'special':
      return 'special';
    case 'rare':
      return 'rare';
    default:
      return 'normal';
  }
}

class TravelCard {
  final String cardInstanceId;
  final String templateId;
  final String name;
  final String icon;
  final String colorHex;
  final String rarity;
  final String type;
  final String cardType; // QUEST_LOCATION | PHYSICAL_BLIND_PACK
  final String activationStatus; // UNCLAIMED | CLAIMED | LOCKED_IN_TRADE
  final String? serialLabel;
  final String? lore;
  final int? mintLimit;
  final int mintedCount;
  final bool hasImage;
  final String? questId;
  final String? locationName;
  final String? province;
  final String? acquiredAt;

  TravelCard({
    required this.cardInstanceId,
    required this.templateId,
    required this.name,
    required this.icon,
    required this.colorHex,
    required this.rarity,
    required this.type,
    this.cardType = 'QUEST_LOCATION',
    this.activationStatus = 'CLAIMED',
    this.serialLabel,
    this.lore,
    this.mintLimit,
    this.mintedCount = 0,
    this.hasImage = false,
    this.questId,
    this.locationName,
    this.province,
    this.acquiredAt,
  });

  bool get isLocked => activationStatus == 'LOCKED_IN_TRADE';
  bool get isPhysicalPack => cardType == 'PHYSICAL_BLIND_PACK';
  String get rarityLabel => rarity == 'special' ? 'Special' : (rarity == 'rare' ? 'Rare' : 'Normal');

  /// Public artwork URL (only served for approved quests and seeded cards).
  String? get imageUrl => hasImage ? '$apiBaseUrl/media/card/$templateId' : null;

  factory TravelCard.fromJson(Map<String, dynamic> j) => TravelCard(
        cardInstanceId: j['card_instance_id'],
        templateId: j['template_id'],
        name: j['name'],
        icon: j['icon'] ?? 'style',
        colorHex: j['color_hex'] ?? '#4C6B8A',
        rarity: normalizeRarity(j['rarity']),
        type: j['type'] ?? 'mission',
        cardType: j['card_type'] ?? 'QUEST_LOCATION',
        activationStatus: j['activation_status'] ?? 'CLAIMED',
        serialLabel: j['serial_label'],
        lore: j['lore'],
        mintLimit: j['mint_limit'],
        mintedCount: j['minted_count'] ?? 0,
        hasImage: j['has_image'] == true,
        questId: j['quest_id'],
        locationName: j['location_name'],
        province: j['province'],
        acquiredAt: j['acquired_at'],
      );
}

class CommunityPost {
  final String postId;
  final String username;
  final String content;
  final String? imageEmoji;
  final String timestamp;
  final int likeCount;
  final int commentCount;
  final bool likedByMe;

  CommunityPost({
    required this.postId,
    required this.username,
    required this.content,
    this.imageEmoji,
    required this.timestamp,
    required this.likeCount,
    required this.commentCount,
    required this.likedByMe,
  });

  factory CommunityPost.fromJson(Map<String, dynamic> j) => CommunityPost(
        postId: j['post_id'],
        username: j['username'],
        content: j['content'] ?? '',
        imageEmoji: j['image_emoji'],
        timestamp: j['timestamp'],
        likeCount: j['like_count'] ?? 0,
        commentCount: j['comment_count'] ?? 0,
        likedByMe: j['liked_by_me'] == true,
      );
}

class Comment {
  final String commentId;
  final String username;
  final String content;
  final String timestamp;
  Comment({required this.commentId, required this.username, required this.content, required this.timestamp});

  factory Comment.fromJson(Map<String, dynamic> j) => Comment(
        commentId: j['comment_id'],
        username: j['username'],
        content: j['content'],
        timestamp: j['timestamp'],
      );
}

class TravelHistoryEntry {
  final String locationName;
  final String province;
  final String timestamp;
  final String status;
  TravelHistoryEntry({required this.locationName, required this.province, required this.timestamp, required this.status});

  factory TravelHistoryEntry.fromJson(Map<String, dynamic> j) => TravelHistoryEntry(
        locationName: j['location_name'],
        province: j['province'],
        timestamp: j['timestamp'],
        status: j['status'],
      );
}

class HotelOffer {
  final String offerId;
  final String? externalHotelId;
  final String hotelName;
  final double? priceAmount;
  final String? priceCurrency;
  final String? roomDescription;
  final String? photoUrl;
  final String? largePhotoUrl;
  final String? address;
  final int? starClass;
  final double? reviewScore;
  final String? reviewScoreWord;
  final int? reviewCount;
  final String? distanceToCenter;
  final String? bookingUrl;
  final bool hasFreeParking;
  final bool hasSwimmingPool;
  final bool includeBreakfast;

  HotelOffer({
    required this.offerId,
    this.externalHotelId,
    required this.hotelName,
    this.priceAmount,
    this.priceCurrency,
    this.roomDescription,
    this.photoUrl,
    this.largePhotoUrl,
    this.address,
    this.starClass,
    this.reviewScore,
    this.reviewScoreWord,
    this.reviewCount,
    this.distanceToCenter,
    this.bookingUrl,
    this.hasFreeParking = false,
    this.hasSwimmingPool = false,
    this.includeBreakfast = false,
  });

  factory HotelOffer.fromJson(Map<String, dynamic> j) => HotelOffer(
        offerId: j['offer_id'],
        externalHotelId: j['external_hotel_id']?.toString(),
        hotelName: j['hotel_name'],
        priceAmount: (j['price_amount'] as num?)?.toDouble(),
        priceCurrency: j['price_currency'],
        roomDescription: j['room_description'],
        photoUrl: j['photo_url'],
        largePhotoUrl: j['large_photo_url'],
        address: j['address'],
        starClass: (j['star_class'] as num?)?.toInt(),
        reviewScore: (j['review_score'] as num?)?.toDouble(),
        reviewScoreWord: j['review_score_word'],
        reviewCount: (j['review_count'] as num?)?.toInt(),
        distanceToCenter: j['distance_to_center'],
        bookingUrl: j['booking_url'],
        hasFreeParking: j['has_free_parking'] == true,
        hasSwimmingPool: j['has_swimming_pool'] == true,
        includeBreakfast: j['include_breakfast'] == true,
      );
}

class HotelPhoto {
  final String? thumbUrl;
  final String? largeUrl;
  HotelPhoto({this.thumbUrl, this.largeUrl});

  factory HotelPhoto.fromJson(Map<String, dynamic> j) => HotelPhoto(
        thumbUrl: j['thumb_url'],
        largeUrl: j['large_url'],
      );
}

class HotelReview {
  final String? title;
  final String? pros;
  final String? cons;
  final String? authorName;
  final String? authorType;
  final String? authorCountry;
  final String? date;

  HotelReview({this.title, this.pros, this.cons, this.authorName, this.authorType, this.authorCountry, this.date});

  factory HotelReview.fromJson(Map<String, dynamic> j) => HotelReview(
        title: j['title'],
        pros: j['pros'],
        cons: j['cons'],
        authorName: j['author_name'],
        authorType: j['author_type'],
        authorCountry: j['author_country'],
        date: j['date'],
      );
}

class CheckinKiosk {
  final String kioskId;
  final String kioskCode;
  final String locationId;
  final String locationName;
  final String province;
  final String status;

  CheckinKiosk({
    required this.kioskId,
    required this.kioskCode,
    required this.locationId,
    required this.locationName,
    required this.province,
    required this.status,
  });

  factory CheckinKiosk.fromJson(Map<String, dynamic> j) => CheckinKiosk(
        kioskId: j['kiosk_id'],
        kioskCode: j['kiosk_code'] ?? '',
        locationId: j['location_id'],
        locationName: j['location_name'],
        province: j['province'],
        status: j['status'] ?? 'online',
      );
}
