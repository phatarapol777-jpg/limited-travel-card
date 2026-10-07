import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../models/models.dart';
import '../services/api_client.dart';
import '../services/geo_service.dart';
import '../theme.dart';
import 'profile_view_screen.dart';
import 'scan_kiosk_screen.dart';
import 'scan_result_screen.dart';

/// The one scan button: reads any QR the app uses and routes by its prefix.
///   TRVKIOSK|code            check-in kiosk
///   TRVQUEST|id|signature    quest reward
///   TRVCARD|code             physical card activation
///   TRVUSER|username         a friend's profile
/// With [pickUser] it only accepts a friend's profile QR and returns the username (used to pick a trade recipient).
class MainScanScreen extends StatefulWidget {
  final bool pickUser;
  const MainScanScreen({super.key, this.pickUser = false});

  @override
  State<MainScanScreen> createState() => _MainScanScreenState();
}

class _MainScanScreenState extends State<MainScanScreen> {
  final MobileScannerController _controller = MobileScannerController(formats: [BarcodeFormat.qrCode]);
  bool _handling = false;
  String? _hint;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handling) return;
    final value = capture.barcodes.isNotEmpty ? capture.barcodes.first.rawValue : null;
    if (value == null) return;
    _handling = true;
    try {
      await _route(value);
    } finally {
      if (mounted) setState(() => _handling = false);
    }
  }

  Future<void> _route(String value) async {
    if (value.startsWith('TRVUSER|')) {
      final username = value.substring('TRVUSER|'.length);
      if (!RegExp(r'^[A-Za-z0-9_.-]{1,40}$').hasMatch(username)) return _unknown();
      if (widget.pickUser) {
        Navigator.of(context).pop(username);
      } else {
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ProfileViewScreen(username: username)));
      }
      return;
    }
    if (widget.pickUser) {
      setState(() => _hint = 'ต้องเป็น QR โปรไฟล์ของเพื่อน (หน้าโปรไฟล์ → QR ของฉัน)');
      return;
    }
    if (value.startsWith('TRVKIOSK|')) {
      final code = value.substring('TRVKIOSK|'.length);
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ScanKioskScreen(kioskCode: code)));
    } else if (value.startsWith('TRVQUEST|')) {
      // the printed QR works from anywhere, so the server also checks that this phone is near the place
      setState(() => _hint = 'กำลังหาตำแหน่งของคุณ...');
      final here = await currentPosition();
      if (mounted) setState(() => _hint = null);
      await _claim('/quests/claim', value, title: 'รับการ์ดภารกิจ', extra: here == null ? {} : {'lat': here.lat, 'lng': here.lng});
    } else if (value.startsWith('TRVCARD|')) {
      await _claim('/cards/activate', value, title: 'เปิดใช้งานการ์ด');
    } else {
      _unknown();
    }
  }

  void _unknown() => setState(() => _hint = 'ไม่รู้จัก QR นี้ ลองสแกน QR ของตู้เช็คอิน ภารกิจ การ์ด หรือโปรไฟล์เพื่อน');

  Future<void> _claim(String path, String payload, {required String title, Map<String, dynamic> extra = const {}}) async {
    String? error;
    TravelCard? card;
    try {
      final data = await apiClient.post(path, {'payload': payload, ...extra});
      card = TravelCard.fromJson(data['card']);
    } on ApiException catch (e) {
      error = e.message;
    } catch (_) {
      error = 'เชื่อมต่อเซิร์ฟเวอร์ไม่ได้';
    }
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => ScanResultScreen(title: title, card: card, error: error)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.pickUser ? 'สแกน QR โปรไฟล์เพื่อน' : 'สแกน')),
      body: Stack(
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(border: Border.all(color: AppColors.gold, width: 3), borderRadius: BorderRadius.circular(18)),
            ),
          ),
          Positioned(
            bottom: 36,
            left: 24,
            right: 24,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.65), borderRadius: BorderRadius.circular(12)),
              child: Text(
                _hint ??
                    (widget.pickUser
                        ? 'สแกน QR โปรไฟล์ของเพื่อนเพื่อเลือกเป็นผู้รับ'
                        : 'สแกน QR ตู้เช็คอิน, QR ภารกิจ, QR หลังการ์ดจริง หรือ QR โปรไฟล์เพื่อน'),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
