import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../models/models.dart';
import '../services/api_client.dart';
import '../services/geo_service.dart';
import '../services/kiosk_crypto.dart';
import '../theme.dart';
import '../widgets/travel_card_tile.dart';
import 'face_enroll_screen.dart';

enum _ScanStage { scanning, connecting, docking, success, error }

class ScanKioskScreen extends StatefulWidget {
  final TravelLocation? location;

  /// When given (the main scan button already read the kiosk's QR) the session opens straight away.
  final String? kioskCode;
  const ScanKioskScreen({super.key, this.location, this.kioskCode});

  @override
  State<ScanKioskScreen> createState() => _ScanKioskScreenState();
}

class _ScanKioskScreenState extends State<ScanKioskScreen> {
  final MobileScannerController _controller = MobileScannerController(formats: [BarcodeFormat.qrCode]);
  _ScanStage _stage = _ScanStage.scanning;
  String? _sessionId;
  String? _sessionKey;
  String? _userId;
  String? _kioskCode;
  String? _errorMessage;
  bool _needsFace = false;
  Map<String, dynamic>? _result;
  String? _locationName;
  String? _qrPayload;
  Timer? _pollTimer;
  Timer? _qrTimer;
  bool _handledDetection = false;

  @override
  void initState() {
    super.initState();
    final code = widget.kioskCode;
    if (code != null) {
      _handledDetection = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _open(code));
    }
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _qrTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _fail(String message, {bool needsFace = false}) {
    _pollTimer?.cancel();
    _qrTimer?.cancel();
    if (!mounted) return;
    setState(() {
      _stage = _ScanStage.error;
      _errorMessage = message;
      _needsFace = needsFace;
    });
  }

  // Step 1: scan the static QR on the kiosk and open a session.
  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handledDetection) return;
    final value = capture.barcodes.isNotEmpty ? capture.barcodes.first.rawValue : null;
    if (value == null || !value.startsWith('TRVKIOSK|')) return;
    _handledDetection = true;
    await _open(value.substring('TRVKIOSK|'.length));
  }

  Future<void> _open(String code) async {
    setState(() {
      _stage = _ScanStage.connecting;
      _kioskCode = code;
    });
    try {
      final data = await apiClient.post('/kiosk/open', {'kiosk_code': code});
      _sessionId = data['session_id'];
      _sessionKey = data['session_key'];
      _userId = data['user_id'];
      _locationName = (data['location'] as Map?)?['name'] as String?;
      if (!mounted) return;
      setState(() => _stage = _ScanStage.docking);
      unawaited(_sendTelemetry());
      _refreshQr();
      _qrTimer = Timer.periodic(const Duration(seconds: 2), (_) => _refreshQr());
      _pollTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) => _poll());
    } on ApiException catch (e) {
      _fail(e.message, needsFace: e.code == 'no_face_enrolled');
    } catch (e) {
      _fail('เชื่อมต่อไม่สำเร็จ: $e');
    }
  }

  // Step 2: tell the server what the phone can observe nearby (browsers cannot list Wi-Fi/BLE, so GPS + network are used).
  Future<void> _sendTelemetry() async {
    final position = await currentPosition();
    try {
      await apiClient.post('/kiosk/session/$_sessionId/telemetry', {
        if (position != null) 'lat': position.lat,
        if (position != null) 'lng': position.lng,
      });
    } catch (_) {
      // the kiosk will report the missing environment status; nothing to do here
    }
  }

  // Step 3: build the dynamic QR (User_ID | BLE token | timestamp | HMAC) from the kiosk's current token.
  Future<void> _refreshQr() async {
    if (_sessionId == null) return;
    try {
      final data = await apiClient.get('/kiosk/session/$_sessionId/ble');
      final payload = buildQrPayload(sessionKey: _sessionKey!, userId: _userId!, bleToken: data['token'], now: DateTime.now());
      if (mounted) setState(() => _qrPayload = payload);
    } catch (_) {
      // keep the previous QR; the next tick tries again
    }
  }

  Future<void> _poll() async {
    if (_sessionId == null) return;
    try {
      final data = await apiClient.get('/kiosk/session/$_sessionId');
      final status = data['status'];
      if (status == 'completed') {
        _pollTimer?.cancel();
        _qrTimer?.cancel();
        setState(() {
          _stage = _ScanStage.success;
          _result = data['result'];
        });
      } else if (status == 'rejected') {
        final reasons = ((data['result']?['reasons']) as List?)?.join('\n') ?? '';
        _fail('เช็คอินไม่สำเร็จ\n$reasons');
      } else if (status == 'expired') {
        _fail('เซสชันหมดอายุ กรุณาลองใหม่');
      }
    } catch (_) {
      // transient network hiccup, keep polling
    }
  }

  void _retry() {
    _pollTimer?.cancel();
    _qrTimer?.cancel();
    setState(() {
      _stage = _ScanStage.scanning;
      _sessionId = null;
      _sessionKey = null;
      _qrPayload = null;
      _errorMessage = null;
      _needsFace = false;
      _result = null;
      _handledDetection = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.location != null ? 'เช็คอินที่ ${widget.location!.name}' : 'เช็คอินที่ตู้')),
      body: SafeArea(child: _buildStage()),
    );
  }

  Widget _buildStage() {
    switch (_stage) {
      case _ScanStage.scanning:
        return Stack(
          children: [
            MobileScanner(controller: _controller, onDetect: _onDetect),
            Center(
              child: Container(
                width: 240,
                height: 240,
                decoration: BoxDecoration(border: Border.all(color: AppColors.gold, width: 3), borderRadius: BorderRadius.circular(16)),
              ),
            ),
            Positioned(
              bottom: 40,
              left: 24,
              right: 24,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(12)),
                child: const Text(
                  'สแกน QR ประจำตู้ที่ติดอยู่หน้าตู้เช็คอิน',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
          ],
        );

      case _ScanStage.connecting:
        return const Center(child: CircularProgressIndicator());

      case _ScanStage.docking:
        return LayoutBuilder(builder: (context, box) {
          final size = (box.maxWidth - 48).clamp(200.0, 340.0);
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Text('ตู้ $_kioskCode${_locationName != null ? ' · $_locationName' : ''}', style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 14),
                const Text('วางมือถือนิ่ง ๆ บนแท่นวาง\nแล้วเงยหน้ามองกล้องที่ตู้', textAlign: TextAlign.center, style: TextStyle(fontSize: 16)),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: const Color(0xFFE3E7EF))),
                  child: _qrPayload == null
                      ? SizedBox(height: size, width: size, child: const Center(child: CircularProgressIndicator()))
                      : QrImageView(
                          data: _qrPayload!,
                          size: size,
                          backgroundColor: Colors.white,
                          eyeStyle: const QrEyeStyle(color: Colors.black, eyeShape: QrEyeShape.square),
                          dataModuleStyle: const QrDataModuleStyle(color: Colors.black, dataModuleShape: QrDataModuleShape.square),
                          errorCorrectionLevel: QrErrorCorrectLevel.L,
                          gapless: true,
                        ),
                ),
                const SizedBox(height: 14),
                const Text('QR นี้เปลี่ยนทุกไม่กี่วินาที เพิ่มความสว่างหน้าจอให้สุดเพื่อให้ตู้อ่านได้ง่าย',
                    textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 12)),
                const SizedBox(height: 12),
                const CircularProgressIndicator(strokeWidth: 2),
                const SizedBox(height: 8),
                const Text('กำลังรอตู้ตรวจสอบ...', style: TextStyle(color: Colors.grey)),
              ],
            ),
          );
        });

      case _ScanStage.success:
        final awarded = ((_result?['awarded_cards'] as List?) ?? []).map((e) => TravelCard.fromJson(e)).toList();
        final name = (_result?['location'] as Map?)?['name'] ?? widget.location?.name ?? 'สถานที่นี้';
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle, color: AppColors.success, size: 64),
                const SizedBox(height: 12),
                Text('เช็คอินที่ $name สำเร็จ', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                if (awarded.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  const Text('ได้รับการ์ดใหม่:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 120,
                    child: GridView.count(
                      crossAxisCount: 2,
                      mainAxisSpacing: 8,
                      crossAxisSpacing: 8,
                      children: awarded.map((c) => TravelCardTile(card: c)).toList(),
                    ),
                  ),
                ] else
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      ((_result?['sold_out_cards'] as List?) ?? []).isNotEmpty
                          ? 'เช็คอินสำเร็จ แต่การ์ดของสถานที่นี้แจกครบจำนวนแล้ว'
                          : 'ภารกิจนี้เคยสำเร็จแล้ว ไม่มีการ์ดใหม่',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ),
                const SizedBox(height: 20),
                ElevatedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('เสร็จสิ้น')),
              ],
            ),
          ),
        );

      case _ScanStage.error:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, color: Colors.redAccent, size: 56),
                const SizedBox(height: 12),
                Text(_errorMessage ?? 'เกิดข้อผิดพลาด', textAlign: TextAlign.center),
                const SizedBox(height: 20),
                if (_needsFace) ...[
                  ElevatedButton.icon(
                    icon: const Icon(Icons.face),
                    label: const Text('ลงทะเบียนใบหน้า'),
                    onPressed: () async {
                      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FaceEnrollScreen()));
                      if (mounted) _retry();
                    },
                  ),
                  const SizedBox(height: 8),
                ],
                ElevatedButton(onPressed: _retry, child: const Text('ลองใหม่')),
              ],
            ),
          ),
        );
    }
  }
}
