class AppUser {
  final String userId;
  final String username;
  final String firstName;
  final String lastName;
  final String email;
  final String? phone;
  final bool isAdmin;

  AppUser({
    required this.userId,
    required this.username,
    required this.firstName,
    required this.lastName,
    required this.email,
    this.phone,
    this.isAdmin = false,
  });

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        userId: j['user_id'],
        username: j['username'],
        firstName: j['first_name'],
        lastName: j['last_name'],
        email: j['email'],
        phone: j['phone'],
        isAdmin: j['is_admin'] == 1 || j['is_admin'] == true,
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

  TravelLocation({
    required this.locationId,
    required this.name,
    this.description,
    required this.latitude,
    required this.longitude,
    required this.province,
    required this.icon,
  });

  factory TravelLocation.fromJson(Map<String, dynamic> j) => TravelLocation(
        locationId: j['location_id'],
        name: j['name'],
        description: j['description'],
        latitude: (j['latitude'] as num).toDouble(),
        longitude: (j['longitude'] as num).toDouble(),
        province: j['province'],
        icon: j['icon'] ?? 'place',
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

class TravelCard {
  final String cardInstanceId;
  final String templateId;
  final String name;
  final String icon;
  final String colorHex;
  final String rarity;
  final String type;
  final String? locationName;
  final String? acquiredAt;

  TravelCard({
    required this.cardInstanceId,
    required this.templateId,
    required this.name,
    required this.icon,
    required this.colorHex,
    required this.rarity,
    required this.type,
    this.locationName,
    this.acquiredAt,
  });

  factory TravelCard.fromJson(Map<String, dynamic> j) => TravelCard(
        cardInstanceId: j['card_instance_id'],
        templateId: j['template_id'],
        name: j['name'],
        icon: j['icon'] ?? 'style',
        colorHex: j['color_hex'] ?? '#4C6B8A',
        rarity: j['rarity'] ?? 'common',
        type: j['type'] ?? 'mission',
        locationName: j['location_name'],
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
  final String hotelName;
  final double? priceAmount;
  final String? priceCurrency;
  final String? roomDescription;

  HotelOffer({
    required this.offerId,
    required this.hotelName,
    this.priceAmount,
    this.priceCurrency,
    this.roomDescription,
  });

  factory HotelOffer.fromJson(Map<String, dynamic> j) => HotelOffer(
        offerId: j['offer_id'],
        hotelName: j['hotel_name'],
        priceAmount: (j['price_amount'] as num?)?.toDouble(),
        priceCurrency: j['price_currency'],
        roomDescription: j['room_description'],
      );
}

class CheckinKiosk {
  final String kioskId;
  final String locationId;
  final String locationName;
  final String province;
  final String status;

  CheckinKiosk({
    required this.kioskId,
    required this.locationId,
    required this.locationName,
    required this.province,
    required this.status,
  });

  factory CheckinKiosk.fromJson(Map<String, dynamic> j) => CheckinKiosk(
        kioskId: j['kiosk_id'],
        locationId: j['location_id'],
        locationName: j['location_name'],
        province: j['province'],
        status: j['status'] ?? 'online',
      );
}
