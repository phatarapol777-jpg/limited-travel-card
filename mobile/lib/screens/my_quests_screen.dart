import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../models/collection_models.dart';
import '../services/api_client.dart';
import '../services/image_tools.dart';
import '../theme.dart';
import 'quest_create_screen.dart';

/// Your quest requests: status, why one was rejected, and the QR code to print for the approved ones.
class MyQuestsScreen extends StatefulWidget {
  const MyQuestsScreen({super.key});

  @override
  State<MyQuestsScreen> createState() => _MyQuestsScreenState();
}

class _MyQuestsScreenState extends State<MyQuestsScreen> {
  List<Quest> _quests = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await apiClient.get('/quests/mine');
      if (!mounted) return;
      setState(() {
        _quests = (data['quests'] as List).map((e) => Quest.fromJson(e)).toList();
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() {
        _loading = false;
        _error = 'โหลดไม่สำเร็จ: $e';
      });
    }
  }

  Future<void> _create() async {
    final created = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const QuestCreateScreen()));
    if (created == true) _load();
  }

  (String, Color) _status(Quest q) {
    switch (q.status) {
      case 'pending':
        return ('รอแอดมินอนุมัติ', Colors.orange);
      case 'approved':
        return (q.phase == 'upcoming' ? 'อนุมัติแล้ว (ยังไม่เริ่ม)' : (q.phase == 'ended' ? 'หมดเวลา' : 'เปิดอยู่'), AppColors.success);
      case 'rejected':
        return ('ไม่อนุมัติ', Colors.red);
      default:
        return ('ปิดแล้ว', Colors.grey);
    }
  }

  Future<void> _edit(Quest q) async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => QuestCreateScreen(existing: q)));
    if (saved == true) _load();
  }

  Future<void> _close(Quest q) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(q.status == 'pending' ? 'ถอนคำร้อง?' : 'ปิดภารกิจนี้?'),
        content: Text(q.status == 'pending'
            ? 'คำร้องจะถูกยกเลิก'
            : 'ผู้ใช้จะสแกน QR รับการ์ดเพิ่มไม่ได้ ส่วนคนที่รับไปแล้วยังมีการ์ดอยู่ และเปิดภารกิจนี้อีกครั้งไม่ได้'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('ยกเลิก')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('ยืนยัน', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await apiClient.post('/quests/${q.questId}/close', {});
      _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  Future<void> _showQr(Quest q) async {
    try {
      final data = await apiClient.get('/quests/${q.questId}/qr');
      if (!mounted) return;
      await showDialog<void>(context: context, builder: (_) => _QrDialog(title: q.title, payload: data['payload'] as String));
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ภารกิจของฉัน')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        backgroundColor: AppColors.navy,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('สร้างภารกิจ'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _quests.isEmpty
                  ? ListView(children: [Padding(padding: const EdgeInsets.all(40), child: Center(child: Text(_error ?? 'ยังไม่มีภารกิจ กดปุ่ม "สร้างภารกิจ" เพื่อเริ่ม', textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey))))])
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                      itemCount: _quests.length,
                      itemBuilder: (_, i) {
                        final q = _quests[i];
                        final (label, color) = _status(q);
                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Row(children: [
                                Expanded(child: Text(q.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
                                  child: Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
                                ),
                              ]),
                              const SizedBox(height: 4),
                              Text('${q.locationName} · ${q.period}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                              if (q.card != null) ...[
                                const SizedBox(height: 6),
                                Text('การ์ด: ${q.card!.name} · ${q.card!.rarity.toUpperCase()} · แจกแล้ว ${q.card!.mintedCount}/${q.card!.mintLimit}', style: const TextStyle(fontSize: 13)),
                              ],
                              if (q.rejectReason != null) ...[
                                const SizedBox(height: 8),
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
                                  child: Text('เหตุผลที่ไม่อนุมัติ: ${q.rejectReason}', style: const TextStyle(color: Colors.red)),
                                ),
                              ],
                              if (q.status == 'approved') ...[
                                const SizedBox(height: 10),
                                OutlinedButton.icon(
                                  icon: const Icon(Icons.qr_code_2),
                                  label: const Text('ดู / ดาวน์โหลด QR Code'),
                                  onPressed: () => _showQr(q),
                                ),
                              ],
                              if (q.status == 'pending' || q.status == 'rejected' || q.status == 'approved') ...[
                                const SizedBox(height: 6),
                                Row(children: [
                                  if (q.status != 'approved')
                                    Expanded(child: TextButton.icon(icon: const Icon(Icons.edit_outlined), label: Text(q.status == 'rejected' ? 'แก้ไขแล้วส่งใหม่' : 'แก้ไข'), onPressed: () => _edit(q))),
                                  if (q.status != 'rejected')
                                    Expanded(child: TextButton.icon(
                                      icon: const Icon(Icons.stop_circle_outlined, color: Colors.red),
                                      label: Text(q.status == 'pending' ? 'ถอนคำร้อง' : 'ปิดภารกิจ', style: const TextStyle(color: Colors.red)),
                                      onPressed: () => _close(q),
                                    )),
                                ]),
                              ],
                            ]),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}

class _QrDialog extends StatelessWidget {
  final String title;
  final String payload;
  const _QrDialog({required this.title, required this.payload});

  Future<String> _png() async {
    final painter = QrPainter(
      data: payload,
      version: QrVersions.auto,
      errorCorrectionLevel: QrErrorCorrectLevel.M,
      eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.square, color: Colors.black),
      dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.square, color: Colors.black),
      gapless: true,
    );
    // a white frame around the code, so it scans when printed
    final data = await painter.toImageData(900, format: ui.ImageByteFormat.png);
    final codec = await ui.instantiateImageCodec(data!.buffer.asUint8List());
    final qr = (await codec.getNextFrame()).image;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const margin = 90.0;
    canvas.drawRect(const Rect.fromLTWH(0, 0, 900 + 2 * margin, 900 + 2 * margin), Paint()..color = Colors.white);
    canvas.drawImage(qr, const Offset(margin, margin), Paint());
    final framed = await recorder.endRecording().toImage(900 + 2 * 90, 900 + 2 * 90);
    final bytes = await framed.toByteData(format: ui.ImageByteFormat.png);
    return 'data:image/png;base64,${_b64(bytes!.buffer.asUint8List())}';
  }

  static String _b64(List<int> bytes) => Uri.dataFromBytes(bytes).toString().split(',').last;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(8),
            child: QrImageView(data: payload, size: 240, backgroundColor: Colors.white, errorCorrectionLevel: QrErrorCorrectLevel.M),
          ),
          const SizedBox(height: 12),
          const Text('พิมพ์ QR นี้ไปติดหรือตั้งแสดงที่สถานที่จริง ผู้ใช้สแกนด้วยปุ่มสแกนหลักในแอปเพื่อรับการ์ด', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.grey)),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('ปิด')),
        TextButton(
          onPressed: () async {
            downloadDataUrl(await _png(), 'quest-qr.png');
          },
          child: const Text('ดาวน์โหลด PNG'),
        ),
        TextButton(
          onPressed: () async {
            // iOS Safari ignores downloads: open the picture so it can be long-pressed and saved
            openDataUrl(await _png());
          },
          child: const Text('เปิดรูป (iPhone: กดค้างเพื่อบันทึก)'),
        ),
      ],
    );
  }
}
