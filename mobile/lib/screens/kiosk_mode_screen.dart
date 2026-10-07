import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../models/models.dart';
import '../services/api_client.dart';
import '../services/edge_decision.dart';
import '../services/face_service.dart';
import '../services/geo_service.dart';
import '../services/live_camera.dart';
import '../services/liveness.dart';
import '../theme.dart';

enum _Stage { setup, idle, session, result }

/// Browser simulation of the check-in kiosk: shows the static QR, receives a session from the server, reads the
/// traveler's dynamic QR and scans their face, decides on the device, then reports the evidence to the server.
class KioskModeScreen extends StatefulWidget {
  const KioskModeScreen({super.key});

  @override
  State<KioskModeScreen> createState() => _KioskModeScreenState();
}

class _KioskModeScreenState extends State<KioskModeScreen> {
  // setup
  List<CheckinKiosk> _kiosks = [];
  bool _loadingKiosks = true;
  CheckinKiosk? _selected;
  final _keyController = TextEditingController();
  final _codeController = TextEditingController();
  String? _kioskListError;
  Timer? _retryList;
  bool _separateQrCamera = false;
  bool _starting = false;
  String? _setupError;

  // running kiosk
  _Stage _stage = _Stage.setup;
  String _code = '';
  String _key = '';
  String _locationName = '';
  bool _online = false;
  Timer? _heartbeat;
  Timer? _rotate;
  Timer? _backToIdle;
  final _random = Random.secure();
  String _bleToken = '';
  final List<String> _recentTokens = [];
  GeoPoint? _geo;
  bool _busy = false;
  String? _handledSessionId;
  bool? _environmentOk;

  // current session (the stored face vector lives only here, in memory, until the decision is made)
  Map<String, dynamic>? _session;
  LiveCamera? _faceCamera;
  LiveCamera? _qrCamera;
  String? _qrLabel;
  String? _latestQr;
  String _prompt = '';
  String? _failure;
  EdgeDecision? _decision;
  int? _decisionMs;
  String _userName = '';
  String? _serverVerdict;
  bool _doorOpen = false;

  Map<String, String> get _kioskHeaders => {'x-kiosk-key': _key};

  @override
  void initState() {
    super.initState();
    preloadFaceModels();
    _loadKiosks();
  }

  @override
  void dispose() {
    _heartbeat?.cancel();
    _rotate?.cancel();
    _backToIdle?.cancel();
    _faceCamera?.close();
    _qrCamera?.close();
    _keyController.dispose();
    _codeController.dispose();
    _retryList?.cancel();
    super.dispose();
  }

  Future<void> _loadKiosks() async {
    try {
      final data = await apiClient.get('/catalog/kiosks');
      _retryList?.cancel();
      if (!mounted) return;
      setState(() {
        _kiosks = (data['kiosks'] as List).map((e) => CheckinKiosk.fromJson(e)).toList();
        _loadingKiosks = false;
        _kioskListError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingKiosks = false;
        _kioskListError = 'โหลดรายการตู้ไม่สำเร็จ (เซิร์ฟเวอร์อาจกำลังตื่น) กำลังลองใหม่...';
      });
      // the server may still be waking up: keep retrying until the list arrives
      _retryList?.cancel();
      _retryList = Timer(const Duration(seconds: 4), _loadKiosks);
    }
  }

  // ---- kiosk lifecycle ------------------------------------------------------

  void _rotateToken() {
    _bleToken = (100000 + _random.nextInt(900000)).toString();
    _recentTokens.add(_bleToken);
    if (_recentTokens.length > 12) _recentTokens.removeAt(0);
  }

  Future<void> _start() async {
    final kiosk = _selected;
    final typedCode = _codeController.text.trim().toUpperCase();
    if ((kiosk == null && typedCode.isEmpty) || _keyController.text.trim().isEmpty) {
      setState(() => _setupError = 'เลือกตู้ (หรือพิมพ์รหัสตู้) และกรอกคีย์ตู้');
      return;
    }
    setState(() {
      _starting = true;
      _setupError = null;
    });
    _code = kiosk?.kioskCode ?? typedCode;
    _key = _keyController.text.trim();
    _locationName = kiosk != null ? '${kiosk.locationName} (${kiosk.province})' : _code;
    _geo = await currentPosition();
    // Ask for camera permission now (and release the camera), so it is not first requested when a traveler is waiting.
    try {
      final test = await openLiveCamera(front: true);
      await test.close();
    } catch (e) {
      if (mounted) {
        setState(() {
          _setupError = 'เปิดกล้องของเครื่องนี้ไม่ได้ ($e) กรุณาอนุญาตการใช้กล้องในเบราว์เซอร์แล้วกดเริ่มทำงานอีกครั้ง';
          _starting = false;
        });
      }
      return;
    }
    _recentTokens.clear();
    _rotateToken();
    try {
      await _beat(first: true);
    } on ApiException catch (e) {
      if (mounted) setState(() => _setupError = e.message);
      if (mounted) setState(() => _starting = false);
      return;
    } catch (e) {
      if (mounted) setState(() => _setupError = 'เชื่อมต่อเซิร์ฟเวอร์ไม่ได้');
      if (mounted) setState(() => _starting = false);
      return;
    }
    _heartbeat = Timer.periodic(const Duration(milliseconds: 1500), (_) => _beat());
    _rotate = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) setState(_rotateToken);
    });
    if (mounted) {
      setState(() {
        _starting = false;
        _stage = _Stage.idle;
      });
    }
  }

  Future<void> _beat({bool first = false}) async {
    try {
      final data = await apiClient.post('/kiosk/$_code/heartbeat', {
        'ble_token': _bleToken,
        if (_geo != null) 'lat': _geo!.lat,
        if (_geo != null) 'lng': _geo!.lng,
      }, _kioskHeaders, false);
      if (!mounted) return;
      final session = data['session'] as Map<String, dynamic>?;
      if (session != null && session['session_id'] == _session?['session_id']) {
        _environmentOk = session['environment_ok'] as bool?;
      }
      final serverLocation = (data['kiosk']?['location']?['name']) as String?;
      if (serverLocation != null && serverLocation != _locationName && _stage != _Stage.setup) {
        _locationName = serverLocation;
      }
      if (!_online) setState(() => _online = true);
      if (session != null && _stage == _Stage.idle && !_busy && session['session_id'] != _handledSessionId) {
        _startSession(session);
      }
    } on ApiException catch (e) {
      if (first) rethrow;
      if (e.message.contains('คีย์')) _stop('คีย์ตู้ไม่ถูกต้อง');
    } catch (_) {
      if (first) rethrow;
      if (mounted && _online) setState(() => _online = false);
    }
  }

  void _stop([String? error]) {
    _heartbeat?.cancel();
    _rotate?.cancel();
    _backToIdle?.cancel();
    _closeCameras();
    if (!mounted) return;
    setState(() {
      _stage = _Stage.setup;
      _online = false;
      _busy = false;
      _session = null;
      _setupError = error;
    });
  }

  // ---- one check-in session ---------------------------------------------------

  Future<void> _startSession(Map<String, dynamic> session) async {
    _busy = true;
    _handledSessionId = session['session_id'] as String;
    _session = session;
    _environmentOk = session['environment_ok'] as bool?;
    _latestQr = null;
    _decision = null;
    _decisionMs = null;
    _serverVerdict = null;
    _doorOpen = false;
    _failure = null;
    _userName = session['user_name'] as String? ?? '';
    setState(() {
      _stage = _Stage.session;
      _prompt = 'กำลังเปิดกล้อง...';
    });

    final userId = session['user_id'] as String;
    final sessionKey = session['session_key'] as String;
    final stored = (session['stored_face_vector'] as List?)?.map((e) => (e as num).toDouble()).toList();
    LivenessResult? live;
    try {
      await _openCameras();
      live = await runLivenessCheck(
        _faceCamera!,
        onPrompt: (m) {
          if (mounted) setState(() => _prompt = m);
        },
        isActive: () => mounted && _stage == _Stage.session,
        tick: () => _readQr(userId),
      );
      final qrDeadline = DateTime.now().add(const Duration(seconds: 30));
      while (_latestQr == null && DateTime.now().isBefore(qrDeadline) && mounted) {
        if (mounted) setState(() => _prompt = 'วางมือถือที่แสดง QR ให้กล้องเห็น');
        await _readQr(userId);
        await Future.delayed(const Duration(milliseconds: 200));
      }
      final envDeadline = DateTime.now().add(const Duration(seconds: 6));
      while (_environmentOk == null && DateTime.now().isBefore(envDeadline) && mounted) {
        if (mounted) setState(() => _prompt = 'กำลังรอสถานะสภาพแวดล้อมจากเซิร์ฟเวอร์...');
        await Future.delayed(const Duration(milliseconds: 300));
      }
    } on LivenessException catch (e) {
      _failure = e.message;
    } catch (e) {
      debugPrint('kiosk session error: $e');
      _failure = 'เปิดกล้องหรืออ่านภาพไม่สำเร็จ: $e';
    }
    await _closeCameras();
    if (!mounted) return;

    final watch = Stopwatch()..start();
    final decision = decideEdge(
      qrPayload: _latestQr,
      sessionKey: sessionKey,
      userId: userId,
      now: DateTime.now(),
      recentBleTokens: List.of(_recentTokens),
      storedFaceVector: stored ?? const [],
      liveFaceVector: live?.descriptor,
      environmentOk: _environmentOk,
    );
    watch.stop();
    final ms = max(1, watch.elapsedMilliseconds);
    final code = _code;
    final sessionId = _handledSessionId!;
    final evidenceQr = _latestQr;
    _session = null; // drop the stored face vector from memory
    setState(() {
      _decision = decision;
      _decisionMs = ms;
      _doorOpen = decision.passed;
      _serverVerdict = 'กำลังบันทึกผลที่เซิร์ฟเวอร์...';
      _stage = _Stage.result;
    });
    _backToIdle?.cancel();
    _backToIdle = Timer(const Duration(seconds: 12), _finishSession);
    unawaited(_report(code, sessionId, decision, ms, live, evidenceQr));
  }

  Future<void> _readQr(String userId) async {
    final text = readQrFromCamera(label: _qrLabel);
    if (text.isNotEmpty) {
      final parts = text.split('|');
      if (parts.length == 4 && parts[0] == userId && _latestQr != text) {
        _latestQr = text;
        if (mounted) setState(() {});
      }
    }
    await Future.delayed(const Duration(milliseconds: 40));
  }

  Future<void> _report(String code, String sessionId, EdgeDecision d, int ms, LivenessResult? live, String? qr) async {
    try {
      final res = await apiClient.post('/kiosk/$code/session/$sessionId/result', {
        'edge_passed': d.passed,
        'edge_ms': ms,
        if (live != null) 'live_descriptor': live.descriptor,
        if (live != null) 'photo_base64': 'data:image/jpeg;base64,${base64Encode(live.photo)}',
        if (qr != null) 'qr_payload': qr,
      }, {'x-kiosk-key': _key}, false);
      if (!mounted) return;
      final ok = res['verified'] == true;
      setState(() => _serverVerdict = ok
          ? 'เซิร์ฟเวอร์ยืนยันและบันทึกแล้ว'
          : 'เซิร์ฟเวอร์ไม่ยืนยัน: ${((res['reasons'] as List?) ?? []).join(', ')}');
    } on ApiException catch (e) {
      if (mounted) setState(() => _serverVerdict = 'บันทึกผลไม่สำเร็จ: ${e.message}');
    } catch (_) {
      if (mounted) setState(() => _serverVerdict = 'บันทึกผลไม่สำเร็จ (เครือข่าย)');
    }
  }

  void _finishSession() {
    if (!mounted) return;
    setState(() {
      _stage = _Stage.idle;
      _busy = false;
      _decision = null;
      _doorOpen = false;
      _latestQr = null;
    });
  }

  Future<void> _openCameras() async {
    // One getUserMedia per camera, so the browser asks for permission only once.
    final face = await openLiveCamera(front: true);
    _faceCamera = face;
    LiveCamera? qr;
    if (_separateQrCamera) {
      final others = (await listCameras()).where((c) => c.deviceId != face.deviceId).toList();
      if (others.isNotEmpty) qr = await openLiveCamera(deviceId: others.first.deviceId);
    }
    _qrCamera = qr;
    _qrLabel = (qr ?? face).label;
    if (mounted) setState(() {});
  }

  Future<void> _closeCameras() async {
    final face = _faceCamera;
    final qr = _qrCamera;
    _faceCamera = null;
    _qrCamera = null;
    _qrLabel = null;
    await face?.close();
    await qr?.close();
  }

  // ---- UI ---------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.navy,
      appBar: AppBar(
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        title: Text(_stage == _Stage.setup ? 'ตั้งค่าตู้เช็คอิน (Kiosk Simulator)' : 'ตู้เช็คอิน $_code'),
        actions: [if (_stage != _Stage.setup) TextButton(onPressed: () => _stop(), child: const Text('ปิดตู้', style: TextStyle(color: Colors.white70)))],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 480), child: _buildStage()),
          ),
        ),
      ),
    );
  }

  Widget _text(String s, {double size = 14, bool bold = false, Color color = Colors.white, TextAlign align = TextAlign.center}) =>
      Text(s, textAlign: align, style: TextStyle(color: color, fontSize: size, fontWeight: bold ? FontWeight.bold : FontWeight.normal));

  Widget _buildStage() {
    switch (_stage) {
      case _Stage.setup:
        return _loadingKiosks
            ? const Center(child: CircularProgressIndicator(color: Colors.white))
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.point_of_sale, color: AppColors.gold, size: 56),
                  const SizedBox(height: 12),
                  _text('เลือกตู้ที่เครื่องนี้ทำหน้าที่เป็น', size: 16, bold: true),
                  const SizedBox(height: 16),
                  Container(
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                    child: DropdownButtonHideUnderline(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: DropdownButton<CheckinKiosk>(
                          isExpanded: true,
                          value: _selected,
                          hint: const Padding(padding: EdgeInsets.symmetric(vertical: 14), child: Text('เลือกตู้ / สถานที่')),
                          items: _kiosks.map((k) => DropdownMenuItem(value: k, child: Text('${k.kioskCode} · ${k.locationName}'))).toList(),
                          onChanged: (v) => setState(() => _selected = v),
                        ),
                      ),
                    ),
                  ),
                  if (_kioskListError != null) ...[
                    const SizedBox(height: 8),
                    _text(_kioskListError!, size: 12, color: Colors.orangeAccent),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: _codeController,
                    textCapitalization: TextCapitalization.characters,
                    style: const TextStyle(color: AppColors.navy),
                    decoration: const InputDecoration(
                      labelText: 'หรือพิมพ์รหัสตู้ เช่น KSK-001 (ใช้เมื่อเลือกจากรายการไม่ได้)',
                      labelStyle: TextStyle(color: Colors.black54),
                      enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white38)),
                      focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.gold)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _keyController,
                    obscureText: true,
                    style: const TextStyle(color: AppColors.navy),
                    decoration: const InputDecoration(
                      labelText: 'คีย์ตู้ (ดูได้จากหน้าแอดมิน > ตู้เช็คอิน)',
                      labelStyle: TextStyle(color: Colors.black54),
                      enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white38)),
                      focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: AppColors.gold)),
                    ),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _separateQrCamera,
                    activeThumbColor: AppColors.gold,
                    onChanged: (v) => setState(() => _separateQrCamera = v),
                    title: _text('ใช้กล้องตัวที่ 2 อ่าน QR (กล้องล่าง)', align: TextAlign.left),
                    subtitle: _text('ปิด = ใช้กล้องเดียวอ่านทั้ง QR และใบหน้า (แนะนำสำหรับโน้ตบุ๊ก)', size: 12, color: Colors.white54, align: TextAlign.left),
                  ),
                  if (_setupError != null) ...[
                    const SizedBox(height: 8),
                    _text(_setupError!, color: Colors.redAccent),
                  ],
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    icon: _starting
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.play_arrow),
                    label: const Text('เริ่มทำงาน'),
                    onPressed: _starting ? null : _start,
                  ),
                  const SizedBox(height: 10),
                  _text('เครื่องนี้จะขอใช้ตำแหน่ง (GPS) เพื่อใช้ตรวจว่ามือถืออยู่ใกล้ตู้', size: 12, color: Colors.white54),
                ],
              );

      case _Stage.idle:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _text(_locationName, size: 16, bold: true),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
              child: QrImageView(data: 'TRVKIOSK|$_code', size: 240, backgroundColor: Colors.white, errorCorrectionLevel: QrErrorCorrectLevel.M),
            ),
            const SizedBox(height: 14),
            _text(_code, size: 22, bold: true, color: AppColors.gold),
            const SizedBox(height: 6),
            _text('สแกน QR ประจำตู้นี้ด้วยแอปในมือถือเพื่อเริ่มเช็คอิน', color: Colors.white70),
            const SizedBox(height: 16),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.circle, size: 10, color: _online ? Colors.greenAccent : Colors.redAccent),
              const SizedBox(width: 6),
              _text(_online ? 'ออนไลน์' : 'ขาดการเชื่อมต่อเซิร์ฟเวอร์', size: 12, color: Colors.white70),
            ]),
            const SizedBox(height: 4),
            _text('สัญญาณ BLE (จำลอง): $_bleToken', size: 12, color: Colors.white38),
          ],
        );

      case _Stage.session:
        final face = _faceCamera;
        final qr = _qrCamera;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _text('สวัสดีคุณ $_userName', size: 16, bold: true),
            const SizedBox(height: 12),
            _CameraBox(camera: face, caption: qr == null ? 'กล้องตู้ (ใบหน้า + QR)' : 'กล้องบน (ใบหน้า)'),
            if (qr != null) ...[const SizedBox(height: 8), _CameraBox(camera: qr, caption: 'กล้องล่าง (QR)', height: 130)],
            const SizedBox(height: 12),
            _text(_prompt, size: 16, bold: true, color: AppColors.gold),
            const SizedBox(height: 10),
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(_latestQr != null ? Icons.check_circle : Icons.qr_code_scanner, size: 16, color: _latestQr != null ? Colors.greenAccent : Colors.white54),
              const SizedBox(width: 6),
              _text(_latestQr != null ? 'อ่าน QR จากมือถือแล้ว' : 'ยังไม่พบ QR จากมือถือ', size: 12, color: Colors.white70),
            ]),
          ],
        );

      case _Stage.result:
        final d = _decision!;
        final rows = <(String, bool)>[
          ('QR ถูกต้อง (HMAC)', d.hmac),
          ('เวลา (ไม่เกิน 3 นาที)', d.time),
          ('รหัส BLE ตรงกับที่ตู้ปล่อย', d.ble),
          (d.score == null ? 'ใบหน้าตรงกัน (≥ 85%)' : 'ใบหน้าตรงกัน ${d.score}% (ต้อง ≥ 85%)', d.face),
          ('สภาพแวดล้อม (มือถืออยู่ใกล้ตู้)', d.environment),
        ];
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(d.passed ? Icons.check_circle : Icons.cancel, color: d.passed ? AppColors.success : Colors.redAccent, size: 64),
            const SizedBox(height: 8),
            _text(d.passed ? 'เช็คอินสำเร็จ! คุณ$_userName' : 'เช็คอินไม่สำเร็จ', size: 20, bold: true),
            const SizedBox(height: 4),
            _text(_doorOpen ? '🔓 ประตูปลดล็อก' : '🔒 ประตูยังล็อก', size: 16, color: _doorOpen ? Colors.greenAccent : Colors.white70),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(12)),
              child: Column(children: [
                for (final r in rows)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(children: [
                      Icon(r.$2 ? Icons.check_circle : Icons.cancel, size: 18, color: r.$2 ? Colors.greenAccent : Colors.redAccent),
                      const SizedBox(width: 8),
                      Expanded(child: _text(r.$1, size: 13, align: TextAlign.left)),
                    ]),
                  ),
              ]),
            ),
            if (_failure != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.18), borderRadius: BorderRadius.circular(10)),
                child: _text('สาเหตุที่ตู้หยุดทำงาน: $_failure', size: 13, color: Colors.orangeAccent),
              ),
            ],
            if (!d.passed && d.reasons.isNotEmpty) ...[
              const SizedBox(height: 10),
              _text(d.reasons.join('\n'), size: 12, color: Colors.redAccent),
            ],
            const SizedBox(height: 10),
            _text('ตู้ตัดสินใจภายใน $_decisionMs มิลลิวินาที', size: 12, color: Colors.white54),
            if (_serverVerdict != null) _text(_serverVerdict!, size: 12, color: Colors.white54),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: () {
              _backToIdle?.cancel();
              _finishSession();
            }, child: const Text('พร้อมสำหรับผู้ใช้คนถัดไป')),
          ],
        );
    }
  }
}

class _CameraBox extends StatelessWidget {
  final LiveCamera? camera;
  final String caption;
  final double height;
  const _CameraBox({required this.camera, required this.caption, this.height = 240});

  @override
  Widget build(BuildContext context) {
    final c = camera;
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            width: double.infinity,
            height: height,
            child: c != null
                ? liveCameraView(c)
                : const ColoredBox(color: Colors.black26, child: Center(child: CircularProgressIndicator(color: Colors.white))),
          ),
        ),
        const SizedBox(height: 4),
        Text(caption, style: const TextStyle(color: Colors.white54, fontSize: 11)),
      ],
    );
  }
}
