import 'dart:convert';
import 'package:crypto/crypto.dart';

/// Length of the (truncated) HMAC inside the phone's QR code; short keeps the QR sparse and easy for a webcam to read.
const qrHmacLength = 12;

/// HMAC-SHA256 keyed with the session key the server gave the phone, over "user|ble|timestamp".
String qrHmac(String sessionKey, String userId, String bleToken, String timestamp) {
  final mac = Hmac(sha256, utf8.encode(sessionKey)).convert(utf8.encode('$userId|$bleToken|$timestamp'));
  return mac.toString().substring(0, qrHmacLength);
}

/// The dynamic QR payload: User_ID | BLE_Dynamic_Token | Timestamp (epoch seconds) | HMAC_Hash.
String buildQrPayload({required String sessionKey, required String userId, required String bleToken, required DateTime now}) {
  final ts = (now.millisecondsSinceEpoch ~/ 1000).toString();
  return '$userId|$bleToken|$ts|${qrHmac(sessionKey, userId, bleToken, ts)}';
}
