class GeoPoint {
  final double lat;
  final double lng;
  const GeoPoint(this.lat, this.lng);
}

Future<GeoPoint?> currentPosition() async => null;
