import 'dart:math';
import 'kiosk_crypto.dart';

const edgeTimeWindowSeconds = 180;
/// Euclidean distance limit between 128-number face descriptors (the value tested on real faces).
const edgeFaceThreshold = 0.5;
/// Similarity % = 100 - 30 * distance, so the 85% pass mark is exactly distance 0.5. A linear rescale for display, not a probability.
const edgeScoreSlope = 30.0;
const edgePassScore = 100 - edgeScoreSlope * edgeFaceThreshold;

enum CheckState { pending, pass, fail }

class EdgeDecision {
  final bool hmac;
  final bool time;
  final bool ble;
  final bool face;
  final bool environment;
  final double? score;
  final List<String> reasons;
  const EdgeDecision({
    required this.hmac,
    required this.time,
    required this.ble,
    required this.face,
    required this.environment,
    required this.score,
    required this.reasons,
  });

  bool get passed => hmac && time && ble && face && environment;
}

double faceDistance(List<double> a, List<double> b) {
  var sum = 0.0;
  for (var i = 0; i < a.length; i++) {
    sum += (a[i] - b[i]) * (a[i] - b[i]);
  }
  return sqrt(sum);
}

double similarityScore(double distance) => (100 - edgeScoreSlope * distance).clamp(0.0, 100.0);

/// The kiosk's on-device decision (pure and instant): QR integrity, QR age, BLE token, 1:1 face match, environment flag.
/// The server repeats all of these from the raw evidence before anything is awarded.
EdgeDecision decideEdge({
  required String? qrPayload,
  required String sessionKey,
  required String userId,
  required DateTime now,
  required List<String> recentBleTokens,
  required List<double> storedFaceVector,
  required List<double>? liveFaceVector,
  required bool? environmentOk,
}) {
  var hmac = false;
  var time = false;
  var ble = false;
  final reasons = <String>[];

  final parts = qrPayload?.split('|');
  if (parts == null || parts.length != 4) {
    reasons.add('ยังไม่ได้อ่าน QR จากมือถือ');
  } else {
    final tsValue = int.tryParse(parts[2]);
    hmac = parts[0] == userId && parts[3] == qrHmac(sessionKey, parts[0], parts[1], parts[2]);
    time = tsValue != null && (now.millisecondsSinceEpoch / 1000 - tsValue).abs() <= edgeTimeWindowSeconds;
    ble = recentBleTokens.contains(parts[1]);
    if (!hmac) reasons.add('QR ไม่ถูกต้องหรือไม่ใช่ของผู้ใช้นี้ (HMAC)');
    if (!time) reasons.add('QR หมดเวลา (เกิน 3 นาที)');
    if (!ble) reasons.add('รหัส BLE ไม่ตรงกับที่ตู้ปล่อย');
  }

  var face = false;
  double? score;
  if (liveFaceVector == null || liveFaceVector.length != storedFaceVector.length) {
    reasons.add('ยังไม่ได้ใบหน้าสดสำหรับเทียบ');
  } else {
    final d = faceDistance(storedFaceVector, liveFaceVector);
    score = (similarityScore(d) * 10).round() / 10;
    face = d <= edgeFaceThreshold;
    if (!face) reasons.add('ใบหน้าไม่ตรง (ความเหมือน $score% ต่ำกว่า ${edgePassScore.toStringAsFixed(0)}%)');
  }

  final environment = environmentOk == true;
  if (!environment) reasons.add(environmentOk == null ? 'ยังไม่ได้รับสถานะสภาพแวดล้อมจากเซิร์ฟเวอร์' : 'ตรวจสภาพแวดล้อมไม่ผ่าน (มือถือไม่ได้อยู่ใกล้ตู้)');

  return EdgeDecision(hmac: hmac, time: time, ble: ble, face: face, environment: environment, score: score, reasons: reasons);
}
