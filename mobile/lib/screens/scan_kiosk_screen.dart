import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../models/models.dart';
import '../services/api_client.dart';
import '../theme.dart';
import '../widgets/travel_card_tile.dart';

enum _ScanStage { scanning, connecting, waitingKiosk, success, error }

class ScanKioskScreen extends StatefulWidget {
  final TravelLocation location;
  const ScanKioskScreen({super.key, required this.location});

  @override
  State<ScanKioskScreen> createState() => _ScanKioskScreenState();
}

class _ScanKioskScreenState extends State<ScanKioskScreen> {
  final MobileScannerController _controller = MobileScannerController(formats: [BarcodeFormat.qrCode]);
  _ScanStage _stage = _ScanStage.scanning;
  String? _sessionId;
  String? _errorMessage;
  Map<String, dynamic>? _result;
  Timer? _pollTimer;
  bool _handledDetection = false;

  @override
  void dispose() {
    _pollTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handledDetection) return;
    final value = capture.barcodes.isNotEmpty ? capture.barcodes.first.rawValue : null;
    if (value == null || !value.startsWith('TRVKIOSK|')) return;
    _handledDetection = true;
    final sessionId = value.substring('TRVKIOSK|'.length);
    setState(() {
      _stage = _ScanStage.connecting;
      _sessionId = sessionId;
    });
    try {
      await apiClient.post('/kiosk/session/$sessionId/scan');
      setState(() => _stage = _ScanStage.waitingKiosk);
      _pollTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) => _poll());
    } on ApiException catch (e) {
      setState(() {
        _stage = _ScanStage.error;
        _errorMessage = e.message;
      });
    } catch (e) {
      setState(() {
        _stage = _ScanStage.error;
        _errorMessage = 'เชื่อมต่อไม่สำเร็จ: $e';
      });
    }
  }

  Future<void> _poll() async {
    if (_sessionId == null) return;
    try {
      final data = await apiClient.get('/kiosk/session/$_sessionId');
      final status = data['status'];
      if (status == 'completed') {
        _pollTimer?.cancel();
        setState(() {
          _stage = _ScanStage.success;
          _result = data['result'];
        });
      } else if (status == 'expired') {
        _pollTimer?.cancel();
        setState(() {
          _stage = _ScanStage.error;
          _errorMessage = 'เซสชันหมดอายุ กรุณาลองใหม่';
        });
      }
    } catch (_) {
      // transient network hiccup, keep polling
    }
  }

  void _retry() {
    _pollTimer?.cancel();
    setState(() {
      _stage = _ScanStage.scanning;
      _sessionId = null;
      _errorMessage = null;
      _result = null;
      _handledDetection = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('เช็คอินที่ ${widget.location.name}')),
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
                  'สแกน QR ที่แสดงบนเครื่องยืนยันตัวตน (Kiosk) ที่สถานที่นี้',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
          ],
        );

      case _ScanStage.connecting:
        return const Center(child: CircularProgressIndicator());

      case _ScanStage.waitingKiosk:
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 20),
                const Icon(Icons.face_retouching_natural, size: 56, color: AppColors.navy),
                const SizedBox(height: 12),
                const Text('สแกนสำเร็จ กำลังรอเครื่องยืนยันตัวตนสแกนใบหน้าของคุณ...', textAlign: TextAlign.center),
              ],
            ),
          ),
        );

      case _ScanStage.success:
        final awarded = ((_result?['awarded_cards'] as List?) ?? []).map((e) => TravelCard.fromJson(e)).toList();
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle, color: AppColors.success, size: 64),
                const SizedBox(height: 12),
                Text('เช็คอินที่ ${widget.location.name} สำเร็จ', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('ภารกิจนี้เคยสำเร็จแล้ว ไม่มีการ์ดใหม่', style: TextStyle(color: Colors.grey)),
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
                ElevatedButton(onPressed: _retry, child: const Text('ลองใหม่')),
              ],
            ),
          ),
        );
    }
  }
}
