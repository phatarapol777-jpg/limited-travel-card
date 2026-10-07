import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_client.dart';
import '../services/app_state.dart';
import '../widgets/face_capture_widget.dart';

/// Lets a signed-in traveler register (or replace) the face used for kiosk check-in.
class FaceEnrollScreen extends StatefulWidget {
  const FaceEnrollScreen({super.key});

  @override
  State<FaceEnrollScreen> createState() => _FaceEnrollScreenState();
}

class _FaceEnrollScreenState extends State<FaceEnrollScreen> {
  FaceCapture? _capture;
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    final capture = _capture;
    if (capture == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await context.read<AppState>().saveFace(capture.photoDataUrl, capture.descriptor);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('บันทึกใบหน้าเรียบร้อยแล้ว')));
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'เชื่อมต่อเซิร์ฟเวอร์ไม่ได้');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ลงทะเบียนใบหน้า')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'ใบหน้าที่ลงทะเบียนไว้จะใช้ยืนยันตัวตนที่เครื่อง Kiosk ทุกครั้งที่เช็คอิน',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 20),
              Center(child: FaceCaptureWidget(onChanged: (c) => setState(() => _capture = c))),
              const SizedBox(height: 16),
              const Text(
                'ระบบจัดเก็บภาพใบหน้าและข้อมูลลักษณะใบหน้าของคุณเพื่อการยืนยันตัวตนเท่านั้น (ข้อมูลส่วนบุคคลที่อ่อนไหว) โดยการกดบันทึกถือว่าคุณยินยอม',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red)),
              ],
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: (_capture == null || _saving) ? null : _save,
                child: _saving
                    ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('บันทึกใบหน้า'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
