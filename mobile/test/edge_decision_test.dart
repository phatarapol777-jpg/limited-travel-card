import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:travel_card/services/edge_decision.dart';
import 'package:travel_card/services/kiosk_crypto.dart';

void main() {
  final rnd = Random(7);
  final stored = List<double>.generate(128, (_) => rnd.nextDouble());
  List<double> near(double amount) => stored.map((x) => x + (rnd.nextDouble() - 0.5) * amount).toList();
  const key = 'abc123sessionkey';
  const uid = 'usr-0123456789abcdef';
  final now = DateTime.utc(2026, 10, 7, 12);

  String qr({String user = uid, String ble = '482913', DateTime? at, String sessionKey = key}) =>
      buildQrPayload(sessionKey: sessionKey, userId: user, bleToken: ble, now: at ?? now);

  EdgeDecision decide({String? payload, List<double>? live, bool? env = true, List<String> tokens = const ['482913', '111111']}) => decideEdge(
        qrPayload: payload ?? qr(),
        sessionKey: key,
        userId: uid,
        now: now,
        recentBleTokens: tokens,
        storedFaceVector: stored,
        liveFaceVector: live ?? near(0.02),
        environmentOk: env,
      );

  test('genuine attempt passes every check', () {
    final d = decide();
    expect(d.passed, isTrue);
    expect(d.score, greaterThan(85));
    expect(d.reasons, isEmpty);
  });

  test('QR from a different session key fails HMAC', () {
    final d = decide(payload: qr(sessionKey: 'other'));
    expect(d.hmac, isFalse);
    expect(d.passed, isFalse);
  });

  test("QR carrying another user's id fails", () {
    expect(decide(payload: qr(user: 'usr-someoneelse')).hmac, isFalse);
  });

  test('QR older than 3 minutes fails the time check', () {
    final d = decide(payload: qr(at: now.subtract(const Duration(minutes: 4))));
    expect(d.time, isFalse);
    expect(d.hmac, isTrue);
    expect(d.passed, isFalse);
  });

  test('unknown BLE token fails', () {
    expect(decide(tokens: const ['000000']).ble, isFalse);
  });

  test('a different face fails and scores below 85', () {
    final other = List<double>.generate(128, (_) => rnd.nextDouble());
    final d = decide(live: other);
    expect(d.face, isFalse);
    expect(d.score, lessThan(85));
    expect(d.passed, isFalse);
  });

  test('environment must be true; unknown counts as a failure', () {
    expect(decide(env: false).passed, isFalse);
    expect(decide(env: null).passed, isFalse);
  });

  test('score mapping: distance 0.5 is exactly 85%', () {
    expect(similarityScore(0.5), closeTo(85, 1e-9));
    expect(similarityScore(0), 100);
    expect(similarityScore(10), 0);
  });

  test('missing QR reports a reason', () {
    final d = decideEdge(
      qrPayload: null,
      sessionKey: key,
      userId: uid,
      now: now,
      recentBleTokens: const [],
      storedFaceVector: stored,
      liveFaceVector: stored,
      environmentOk: true,
    );
    expect(d.passed, isFalse);
    expect(d.reasons, isNotEmpty);
  });

  test('QR payload matches the format the server verifies', () {
    final p = qr().split('|');
    expect(p.length, 4);
    expect(p[3].length, qrHmacLength);
    expect(p[3], qrHmac(key, uid, '482913', p[2]));
  });

  test('Dart HMAC equals the Node server HMAC for a fixed vector', () {
    // Computed with: crypto.createHmac('sha256', key).update('uid|ble|ts').digest('hex').slice(0, 12)
    expect(qrHmac(key, uid, '482913', '1790000000'), '91c389528ad5');
  });
}
