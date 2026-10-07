import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../services/api_client.dart';

/// Shop categories: the API value, the Thai label and the pin colour/icon.
class ShopCategory {
  final String id;
  final String label;
  final IconData icon;
  final Color color;
  const ShopCategory(this.id, this.label, this.icon, this.color);
}

const shopCategories = <ShopCategory>[
  ShopCategory('RESTAURANT', 'ร้านอาหาร', Icons.restaurant, Color(0xFFD9534F)),
  ShopCategory('CAFE', 'คาเฟ่', Icons.local_cafe, Color(0xFF8D6E63)),
  ShopCategory('SOUVENIR', 'ของฝาก', Icons.shopping_bag, Color(0xFF7A4F9E)),
  ShopCategory('ACCOMMODATION', 'ที่พัก', Icons.hotel, Color(0xFF2E86AB)),
  ShopCategory('ACTIVITY', 'กิจกรรม', Icons.directions_bike, Color(0xFF2FBF71)),
];

ShopCategory categoryOf(String id) => shopCategories.firstWhere((c) => c.id == id, orElse: () => shopCategories.first);

const dayKeys = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
const dayNames = {'mon': 'จันทร์', 'tue': 'อังคาร', 'wed': 'พุธ', 'thu': 'พฤหัสบดี', 'fri': 'ศุกร์', 'sat': 'เสาร์', 'sun': 'อาทิตย์'};

/// What the map needs about a shop (no big data): position, category, open/gift flags and where to fetch the cover.
class ShopPin {
  final String merchantId;
  final String nameTh;
  final String nameEn;
  final String category;
  final double latitude;
  final double longitude;
  final String? nearbyLocationId;
  final bool hasCover;
  final String rev;
  final bool openNow;
  final bool hasPrivilege;

  ShopPin({
    required this.merchantId,
    required this.nameTh,
    required this.nameEn,
    required this.category,
    required this.latitude,
    required this.longitude,
    this.nearbyLocationId,
    this.hasCover = false,
    this.rev = '',
    this.openNow = false,
    this.hasPrivilege = false,
  });

  ShopCategory get cat => categoryOf(category);
  String? get coverUrl => hasCover ? '$apiBaseUrl/media/merchant/$merchantId/cover?v=${Uri.encodeQueryComponent(rev)}' : null;

  factory ShopPin.fromJson(Map<String, dynamic> j) => ShopPin(
        merchantId: j['merchant_id'],
        nameTh: j['shop_name_th'],
        nameEn: j['shop_name_en'] ?? '',
        category: j['category'],
        latitude: (j['latitude'] as num).toDouble(),
        longitude: (j['longitude'] as num).toDouble(),
        nearbyLocationId: j['nearby_location_id'],
        hasCover: j['has_cover'] == true,
        rev: '${j['rev'] ?? ''}',
        openNow: j['open_now'] == true,
        hasPrivilege: j['has_privilege'] == true,
      );
}

/// Straight-line distance in kilometres (haversine), used on the phone to sort shops without sending the position anywhere.
double distanceKm(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371.0;
  double rad(double d) => d * math.pi / 180;
  final dLat = rad(lat2 - lat1);
  final dLng = rad(lng2 - lng1);
  final a = math.pow(math.sin(dLat / 2), 2) + math.cos(rad(lat1)) * math.cos(rad(lat2)) * math.pow(math.sin(dLng / 2), 2);
  return 2 * r * math.asin(math.min(1, math.sqrt(a)));
}

String distanceText(double km) => km < 1 ? '${(km * 1000).round()} ม.' : '${km.toStringAsFixed(km < 10 ? 1 : 0)} กม.';

class ShopItem {
  final String itemId;
  final String name;
  final double? price;
  final bool signature;
  ShopItem({required this.itemId, required this.name, this.price, this.signature = false});
  String get imageUrl => '$apiBaseUrl/media/merchant-item/$itemId';
  factory ShopItem.fromJson(Map<String, dynamic> j) => ShopItem(
        itemId: j['item_id'],
        name: j['name'],
        price: (j['price'] as num?)?.toDouble(),
        signature: j['is_signature'] == true,
      );
}

class ShopPrivilege {
  final String templateId;
  final String description;
  final String? startDate;
  final String? endDate;
  final bool validNow;
  final String cardName;
  final String cardRarity;
  ShopPrivilege({required this.templateId, required this.description, this.startDate, this.endDate, this.validNow = true, this.cardName = '', this.cardRarity = 'normal'});

  String get period => (startDate == null || endDate == null) ? 'ไม่มีวันหมดอายุ' : '$startDate ถึง $endDate';

  factory ShopPrivilege.fromJson(Map<String, dynamic> j) {
    final card = (j['card'] as Map<String, dynamic>?) ?? const {};
    return ShopPrivilege(
      templateId: j['template_id'],
      description: j['description'],
      startDate: j['start_date'],
      endDate: j['end_date'],
      validNow: j['valid_now'] != false,
      cardName: '${card['name'] ?? ''}',
      cardRarity: '${card['rarity'] ?? 'normal'}',
    );
  }
}

class ShopDetail {
  final ShopPin pin;
  final String description;
  final String address;
  final Map<String, List<List<String>>> hours;
  final String todayHours;
  final String phone;
  final String? facebook;
  final String? instagram;
  final String? line;
  final String? nearbyName;
  final List<String> galleryUrls;
  final List<ShopItem> items;
  final List<ShopPrivilege> privileges;

  ShopDetail({
    required this.pin,
    required this.description,
    required this.address,
    required this.hours,
    required this.todayHours,
    required this.phone,
    this.facebook,
    this.instagram,
    this.line,
    this.nearbyName,
    this.galleryUrls = const [],
    this.items = const [],
    this.privileges = const [],
  });

  factory ShopDetail.fromJson(Map<String, dynamic> j, {bool hasPrivilege = false}) {
    final m = j['merchant'] as Map<String, dynamic>;
    final rawHours = (m['opening_hours'] as Map<String, dynamic>? ?? {});
    final hours = <String, List<List<String>>>{
      for (final d in dayKeys) d: ((rawHours[d] as List?) ?? const []).map((r) => (r as List).map((x) => '$x').toList()).toList(),
    };
    final privileges = (j['privileges'] as List).map((e) => ShopPrivilege.fromJson(e)).toList();
    final pin = ShopPin(
      merchantId: m['merchant_id'],
      nameTh: m['shop_name_th'],
      nameEn: m['shop_name_en'] ?? '',
      category: m['category'],
      latitude: (m['latitude'] as num).toDouble(),
      longitude: (m['longitude'] as num).toDouble(),
      nearbyLocationId: (m['nearby_location'] as Map?)?['location_id'],
      hasCover: m['has_cover'] == true,
      rev: '${m['rev'] ?? ''}',
      openNow: m['open_now'] == true,
      hasPrivilege: privileges.any((p) => p.validNow),
    );
    return ShopDetail(
      pin: pin,
      description: m['description'] ?? '',
      address: m['address_detail'] ?? '',
      hours: hours,
      todayHours: m['today_hours'] ?? '',
      phone: m['phone'] ?? '',
      facebook: m['facebook'],
      instagram: m['instagram'],
      line: m['line'],
      nearbyName: (m['nearby_location'] as Map?)?['name'],
      galleryUrls: (j['gallery'] as List).map((g) => '$apiBaseUrl/media/merchant-gallery/${g['image_id']}').toList(),
      items: (j['items'] as List).map((e) => ShopItem.fromJson(e)).toList(),
      privileges: privileges,
    );
  }
}

/// A row of "my shops": status and what the admin said.
class MyShop {
  final String merchantId;
  final String nameTh;
  final String nameEn;
  final String category;
  final String status; // PENDING | APPROVED | REJECTED | SUSPENDED
  final String? rejectReason;
  final bool hasPendingRevision;
  final String? revisionNote;
  final bool hasCover;
  final String rev;
  MyShop({
    required this.merchantId,
    required this.nameTh,
    required this.nameEn,
    required this.category,
    required this.status,
    this.rejectReason,
    this.hasPendingRevision = false,
    this.revisionNote,
    this.hasCover = false,
    this.rev = '',
  });

  ShopCategory get cat => categoryOf(category);
  String? get coverUrl => (hasCover && status == 'APPROVED') ? '$apiBaseUrl/media/merchant/$merchantId/cover?v=${Uri.encodeQueryComponent(rev)}' : null;

  factory MyShop.fromJson(Map<String, dynamic> j) => MyShop(
        merchantId: j['merchant_id'],
        nameTh: j['shop_name_th'],
        nameEn: j['shop_name_en'] ?? '',
        category: j['category'],
        status: j['status'],
        rejectReason: j['reject_reason'],
        hasPendingRevision: j['has_pending_revision'] == true,
        revisionNote: j['revision_note'],
        hasCover: j['has_cover'] == true,
        rev: '${j['rev'] ?? ''}',
      );
}

/// A card a perk can be attached to (from the card picker).
class CardOption {
  final String templateId;
  final String name;
  final String rarity;
  final String? locationName;
  CardOption({required this.templateId, required this.name, required this.rarity, this.locationName});
  factory CardOption.fromJson(Map<String, dynamic> j) =>
      CardOption(templateId: j['template_id'], name: j['name'], rarity: '${j['rarity'] ?? 'normal'}', locationName: j['location_name']);
}
