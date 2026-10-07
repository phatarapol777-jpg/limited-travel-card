import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../services/face_service.dart';
import '../services/live_camera.dart';
import '../services/liveness.dart';
import '../theme.dart';

/// A face photo plus the 128-number descriptor computed from it.
class FaceCapture {
  final Uint8List bytes;
  final List<double> descriptor;
  FaceCapture(this.bytes, this.descriptor);
}

/// Live camera preview with a scan button. Reports the captured face (or null after "retake").
class FaceCaptureWidget extends StatefulWidget {
  final ValueChanged<FaceCapture?> onChanged;
  const FaceCaptureWidget({super.key, required this.onChanged});

  @override
  State<FaceCaptureWidget> createState() => _FaceCaptureWidgetState();
}

class _FaceCaptureWidgetState extends State<FaceCaptureWidget> {
  static const double _size = 240;
  LiveCamera? _camera;
  FaceCapture? _capture;
  bool _busy = false;
  bool _disposed = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    preloadFaceModels();
    _openCamera();
  }

  @override
  void dispose() {
    _disposed = true;
    _camera?.close();
    super.dispose();
  }

  Future<void> _openCamera() async {
    try {
      final camera = await openLiveCamera(front: true);
      if (_disposed) {
        camera.close();
        return;
      }
      setState(() {
        _camera = camera;
        _message = null;
      });
    } catch (e) {
      if (!_disposed) setState(() => _message = 'เปิดกล้องไม่สำเร็จ กรุณาอนุญาตการใช้กล้องแล้วกด "เปิดกล้องอีกครั้ง"');
    }
  }

  Future<void> _capturePhoto() async {
    final camera = _camera;
    if (camera == null || _busy) return;
    setState(() {
      _busy = true;
      _message = 'มองตรงที่กล้อง';
    });
    try {
      final result = await runLivenessCheck(
        camera,
        onPrompt: (m) {
          if (mounted) setState(() => _message = m);
        },
        isActive: () => mounted,
      );
      if (!mounted) return;
      final capture = FaceCapture(result.photo, result.descriptor);
      setState(() {
        _capture = capture;
        _message = null;
      });
      widget.onChanged(capture);
    } on LivenessException catch (e) {
      if (mounted) setState(() => _message = e.message);
    } catch (e) {
      if (mounted) setState(() => _message = 'สแกนใบหน้าไม่สำเร็จ กรุณาลองใหม่ ($e)');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _retake() {
    setState(() {
      _capture = null;
      _message = null;
    });
    widget.onChanged(null);
  }

  @override
  Widget build(BuildContext context) {
    final camera = _camera;
    final captured = _capture;
    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(_size / 2),
          child: SizedBox(
            width: _size,
            height: _size,
            child: captured != null
                ? Image.memory(captured.bytes, fit: BoxFit.cover)
                : (camera != null
                    ? liveCameraView(camera)
                    : const ColoredBox(color: Colors.black12, child: Center(child: Icon(Icons.face, size: 64, color: Colors.grey)))),
          ),
        ),
        const SizedBox(height: 10),
        if (captured != null) ...[
          const Text('สแกนใบหน้าสำเร็จ', style: TextStyle(color: AppColors.success, fontWeight: FontWeight.w600)),
          TextButton.icon(onPressed: _retake, icon: const Icon(Icons.refresh), label: const Text('ถ่ายใหม่')),
        ] else ...[
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(_message!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _busy ? AppColors.navy : Colors.red, fontSize: 14, fontWeight: _busy ? FontWeight.w600 : FontWeight.normal)),
            ),
          if (camera == null && _message != null && _message!.contains('เปิดกล้องอีกครั้ง'))
            ElevatedButton.icon(onPressed: _openCamera, icon: const Icon(Icons.videocam), label: const Text('เปิดกล้องอีกครั้ง'))
          else
            ElevatedButton.icon(
              onPressed: (camera == null || _busy) ? null : _capturePhoto,
              icon: _busy
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.camera_alt),
              label: const Text('สแกนใบหน้า'),
            ),
        ],
      ],
    );
  }
}
