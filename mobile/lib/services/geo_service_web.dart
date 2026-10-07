import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

class GeoPoint {
  final double lat;
  final double lng;
  const GeoPoint(this.lat, this.lng);
}

/// Asks the browser for the current position (prompts the user once). Null when denied or unavailable.
Future<GeoPoint?> currentPosition() async {
  try {
    final geo = globalContext['travelGeo'] as JSObject;
    final result = await geo.callMethod<JSPromise<JSAny?>>('get'.toJS).toDart;
    final text = (result as JSString).toDart;
    if (text.isEmpty) return null;
    final json = jsonDecode(text) as Map<String, dynamic>;
    return GeoPoint((json['lat'] as num).toDouble(), (json['lng'] as num).toDouble());
  } catch (_) {
    return null;
  }
}
