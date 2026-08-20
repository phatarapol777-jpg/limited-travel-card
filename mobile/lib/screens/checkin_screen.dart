import 'dart:async';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../models/models.dart';
import '../services/api_client.dart';
import '../theme.dart';
import '../widgets/countdown_ring.dart';
import '../widgets/status_chip.dart';
import '../widgets/travel_card_tile.dart';

class CheckinScreen extends StatefulWidget {
  final TravelLocation location;
  const CheckinScreen({super.key, required this.location});

  @override
  State<CheckinScreen> createState() => _CheckinScreenState();
}

class _CheckinScreenState extends State<CheckinScreen> {
  String? _qrPayload;
  int _totalSeconds = 180;
  int _secondsRemaining = 180;
  Timer? _timer;

  bool _deviceSecure = false;
  bool _gpsVerified = false;
  bool _bluetoothActive = false;
  bool _confirming = false;
  bool _cancelled = false;

  @override
  void initState() {
    super.initState();
    _loadQr();
  }

  Future<void> _loadQr() async {
    try {
      final data = await apiClient.get('/checkin/qr/${widget.location.locationId}');
      setState(() {
        _qrPayload = data['qr_payload'];
        _totalSeconds = data['expires_in'];
        _secondsRemaining = _totalSeconds;
      });
      _startTimer();
      _runVerificationSequence();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('สร้าง QR ไม่สำเร็จ: $e')));
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() {
        if (_secondsRemaining > 0) {
          _secondsRemaining--;
        } else {
          t.cancel();
        }
      });
    });
  }

  Future<void> _runVerificationSequence() async {
    await Future.delayed(const Duration(milliseconds: 600));
    if (!mounted || _cancelled) return;
    setState(() => _deviceSecure = true);
    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted || _cancelled) return;
    setState(() => _gpsVerified = true);
    await Future.delayed(const Duration(milliseconds: 700));
    if (!mounted || _cancelled) return;
    setState(() => _bluetoothActive = true);
  }

  bool get _allVerified => _deviceSecure && _gpsVerified && _bluetoothActive;

  Future<void> _confirmCheckin() async {
    setState(() => _confirming = true);
    try {
      final data = await apiClient.post('/checkin/confirm', {'location_id': widget.location.locationId});
      if (!mounted) return;
      final awarded = (data['awarded_cards'] as List).map((e) => TravelCard.fromJson({...e, 'card_instance_id': e['card_instance_id']})).toList();
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(children: const [Icon(Icons.check_circle, color: AppColors.success), SizedBox(width: 8), Text('เช็คอินสำเร็จ')]),
          content: SizedBox(
            width: 280,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('คุณเช็คอินที่ ${widget.location.name} สำเร็จ'),
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
              ],
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('ปิด'))],
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('เช็คอินไม่สำเร็จ: $e')));
    } finally {
      if (mounted) setState(() => _confirming = false);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Travel Check-in')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Text(widget.location.name, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                Text(widget.location.province, style: const TextStyle(color: Colors.grey)),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), boxShadow: const [
                    BoxShadow(color: Colors.black12, blurRadius: 10),
                  ]),
                  child: _qrPayload == null
                      ? const SizedBox(height: 220, width: 220, child: Center(child: CircularProgressIndicator()))
                      : QrImageView(data: _qrPayload!, size: 220, backgroundColor: Colors.white),
                ),
                const SizedBox(height: 20),
                CountdownRing(secondsRemaining: _secondsRemaining, totalSeconds: _totalSeconds),
                const SizedBox(height: 24),
                StatusChip(label: 'Device Secure', active: _deviceSecure),
                StatusChip(label: 'GPS Verified', active: _gpsVerified),
                StatusChip(label: 'Bluetooth Active', active: _bluetoothActive),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  icon: _confirming
                      ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.check),
                  label: const Text('Confirm Check-in'),
                  onPressed: (_allVerified && !_confirming && _secondsRemaining > 0) ? _confirmCheckin : null,
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: () {
                    _cancelled = true;
                    Navigator.of(context).pop();
                  },
                  child: const Text('Cancel Check-in'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
