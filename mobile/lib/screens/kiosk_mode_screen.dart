import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../models/models.dart';
import '../services/api_client.dart';
import '../theme.dart';
import '../widgets/travel_card_tile.dart';

enum _KioskStage { pickLocation, awaitingScan, awaitingFace, capturing, verifying, success, error }

class KioskModeScreen extends StatefulWidget {
  const KioskModeScreen({super.key});

  @override
  State<KioskModeScreen> createState() => _KioskModeScreenState();
}

class _KioskModeScreenState extends State<KioskModeScreen> {
  List<CheckinKiosk> _kiosks = [];
  bool _loadingKiosks = true;
  CheckinKiosk? _selectedKiosk;

  _KioskStage _stage = _KioskStage.pickLocation;
  String? _sessionId;
  String? _qrPayload;
  String? _travelerName;
  String? _errorMessage;
  Map<String, dynamic>? _result;
  Timer? _pollTimer;

  CameraController? _cameraController;
  Uint8List? _capturedPhotoBytes;

  @override
  void initState() {
    super.initState();
    _loadKiosks();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _cameraController?.dispose();
    super.dispose();
  }

  Future<void> _loadKiosks() async {
    try {
      final data = await apiClient.get('/catalog/kiosks');
      setState(() {
        _kiosks = (data['kiosks'] as List).map((e) => CheckinKiosk.fromJson(e)).toList();
        _loadingKiosks = false;
      });
    } catch (e) {
      setState(() => _loadingKiosks = false);
    }
  }

  Future<void> _startSession() async {
    if (_selectedKiosk == null) return;
    setState(() {
      _stage = _KioskStage.awaitingScan;
      _errorMessage = null;
      _travelerName = null;
      _result = null;
      _capturedPhotoBytes = null;
    });
    try {
      final data = await apiClient.post('/kiosk/session', {'kiosk_id': _selectedKiosk!.kioskId});
      setState(() {
        _sessionId = data['session_id'];
        _qrPayload = data['qr_payload'];
      });
      _pollTimer?.cancel();
      _pollTimer = Timer.periodic(const Duration(milliseconds: 1500), (_) => _poll());
    } catch (e) {
      setState(() {
        _stage = _KioskStage.error;
        _errorMessage = 'สร้างเซสชันไม่สำเร็จ: $e';
      });
    }
  }

  Future<void> _poll() async {
    if (_sessionId == null) return;
    try {
      final data = await apiClient.get('/kiosk/session/$_sessionId');
      final status = data['status'];
      if (status == 'awaiting_face' && _stage == _KioskStage.awaitingScan) {
        _pollTimer?.cancel();
        setState(() {
          _stage = _KioskStage.awaitingFace;
          _travelerName = data['user'] != null ? '${data['user']['first_name']} ${data['user']['last_name']}' : null;
        });
        _runFaceCapture();
      } else if (status == 'expired') {
        _pollTimer?.cancel();
        setState(() {
          _stage = _KioskStage.error;
          _errorMessage = 'เซสชันหมดอายุ กรุณาเริ่มใหม่';
        });
      }
    } catch (_) {
      // keep polling silently; transient network hiccup
    }
  }

  Future<void> _runFaceCapture() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() {
          _stage = _KioskStage.error;
          _errorMessage = 'ไม่พบกล้องบนอุปกรณ์นี้ ไม่สามารถสแกนใบหน้าได้';
        });
        return;
      }
      final camera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final controller = CameraController(camera, ResolutionPreset.medium, enableAudio: false);
      await controller.initialize();
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() {
        _cameraController = controller;
      });

      // Give the traveler a moment to position their face in frame.
      await Future.delayed(const Duration(seconds: 3));
      if (!mounted) return;

      setState(() => _stage = _KioskStage.capturing);
      final photo = await controller.takePicture();
      final bytes = await photo.readAsBytes();
      await controller.dispose();
      if (!mounted) return;
      setState(() {
        _cameraController = null;
        _capturedPhotoBytes = bytes;
        _stage = _KioskStage.verifying;
      });

      final base64Photo = 'data:image/jpeg;base64,${base64Encode(bytes)}';
      await apiClient.post('/kiosk/session/$_sessionId/verify-face', {'photo_base64': base64Photo});
      final data = await apiClient.post('/kiosk/session/$_sessionId/complete');
      if (!mounted) return;
      setState(() {
        _stage = _KioskStage.success;
        _result = data;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _stage = _KioskStage.error;
        _errorMessage = 'เปิดกล้องหรือยืนยันตัวตนไม่สำเร็จ: $e';
      });
    }
  }

  void _reset() {
    _pollTimer?.cancel();
    _cameraController?.dispose();
    setState(() {
      _stage = _KioskStage.pickLocation;
      _sessionId = null;
      _qrPayload = null;
      _travelerName = null;
      _errorMessage = null;
      _result = null;
      _cameraController = null;
      _capturedPhotoBytes = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy,
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        title: const Text('เครื่องยืนยันตัวตน (Kiosk Simulator)'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: _buildStage(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStage() {
    switch (_stage) {
      case _KioskStage.pickLocation:
        return _loadingKiosks
            ? const Center(child: CircularProgressIndicator(color: Colors.white))
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.point_of_sale, color: AppColors.gold, size: 56),
                  const SizedBox(height: 16),
                  const Text('เลือกสถานที่ติดตั้งเครื่องนี้', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 20),
                  Container(
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                    child: DropdownButtonHideUnderline(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: DropdownButton<CheckinKiosk>(
                          isExpanded: true,
                          value: _selectedKiosk,
                          hint: const Padding(padding: EdgeInsets.symmetric(vertical: 14), child: Text('เลือกเครื่อง / สถานที่')),
                          items: _kiosks
                              .map((k) => DropdownMenuItem(value: k, child: Text('${k.locationName} (${k.province})')))
                              .toList(),
                          onChanged: (v) => setState(() => _selectedKiosk = v),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('เริ่มเซสชันยืนยันตัวตน'),
                    onPressed: _selectedKiosk == null ? null : _startSession,
                  ),
                ],
              );

      case _KioskStage.awaitingScan:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_selectedKiosk?.locationName ?? '', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
              child: _qrPayload == null
                  ? const SizedBox(height: 220, width: 220, child: Center(child: CircularProgressIndicator()))
                  : QrImageView(data: _qrPayload!, size: 220, backgroundColor: Colors.white),
            ),
            const SizedBox(height: 20),
            const Text('สแกน QR นี้ด้วยแอปในมือถือของคุณ\nเพื่อเริ่มเช็คอิน', textAlign: TextAlign.center, style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 20),
            TextButton(onPressed: _reset, child: const Text('ยกเลิก', style: TextStyle(color: Colors.white70))),
          ],
        );

      case _KioskStage.awaitingFace:
      case _KioskStage.capturing:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_travelerName != null) ...[
              Text('สวัสดีคุณ $_travelerName', style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
            ],
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                width: 260,
                height: 260,
                child: _cameraController != null && _cameraController!.value.isInitialized
                    ? CameraPreview(_cameraController!)
                    : const ColoredBox(color: Colors.black26, child: Center(child: CircularProgressIndicator(color: Colors.white))),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _stage == _KioskStage.capturing ? 'กำลังถ่ายภาพ...' : 'กำลังเปิดกล้องเพื่อสแกนใบหน้า จัดตำแหน่งใบหน้าให้อยู่ในกรอบ',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        );

      case _KioskStage.verifying:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_capturedPhotoBytes != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.memory(_capturedPhotoBytes!, width: 220, height: 220, fit: BoxFit.cover),
              ),
            const SizedBox(height: 16),
            const CircularProgressIndicator(color: Colors.white),
            const SizedBox(height: 12),
            const Text('กำลังยืนยันตัวตนกับฐานข้อมูล...', style: TextStyle(color: Colors.white70)),
          ],
        );

      case _KioskStage.success:
        final awarded = ((_result?['awarded_cards'] as List?) ?? []).map((e) => TravelCard.fromJson(e)).toList();
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_capturedPhotoBytes != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(50),
                child: Image.memory(_capturedPhotoBytes!, width: 72, height: 72, fit: BoxFit.cover),
              ),
            const SizedBox(height: 12),
            const Icon(Icons.check_circle, color: AppColors.success, size: 48),
            const SizedBox(height: 8),
            Text('เช็คอินสำเร็จ${_travelerName != null ? ' คุณ$_travelerName' : ''}',
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            if (awarded.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text('ได้รับการ์ดใหม่', style: TextStyle(color: Colors.white70)),
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
            ],
            const SizedBox(height: 24),
            ElevatedButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('พร้อมสำหรับนักท่องเที่ยวคนถัดไป'),
              onPressed: _reset,
            ),
          ],
        );

      case _KioskStage.error:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.redAccent, size: 56),
            const SizedBox(height: 12),
            Text(_errorMessage ?? 'เกิดข้อผิดพลาด', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
            const SizedBox(height: 20),
            ElevatedButton(onPressed: _reset, child: const Text('เริ่มใหม่')),
          ],
        );
    }
  }
}
