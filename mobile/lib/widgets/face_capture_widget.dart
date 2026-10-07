import 'dart:convert';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../services/face_service.dart';
import '../theme.dart';

/// A face photo plus the 128-number descriptor computed from it.
class FaceCapture {
  final Uint8List bytes;
  final List<double> descriptor;
  FaceCapture(this.bytes, this.descriptor);
}

/// Live camera preview with a capture button. Reports the captured face (or null after "retake").
class FaceCaptureWidget extends StatefulWidget {
  final ValueChanged<FaceCapture?> onChanged;
  const FaceCaptureWidget({super.key, required this.onChanged});

  @override
  State<FaceCaptureWidget> createState() => _FaceCaptureWidgetState();
}

class _FaceCaptureWidgetState extends State<FaceCaptureWidget> {
  static const double _size = 240;
  CameraController? _controller;
  FaceCapture? _capture;
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    preloadFaceModels();
    _openCamera();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _openCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        if (mounted) setState(() => _message = 'ไม่พบกล้องบนอุปกรณ์นี้');
        return;
      }
      final camera = cameras.firstWhere((c) => c.lensDirection == CameraLensDirection.front, orElse: () => cameras.first);
      final controller = CameraController(camera, ResolutionPreset.medium, enableAudio: false);
      await controller.initialize();
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _message = null;
      });
    } catch (e) {
      if (mounted) setState(() => _message = 'เปิดกล้องไม่สำเร็จ กรุณาอนุญาตการใช้กล้องแล้วลองใหม่');
    }
  }

  Future<void> _capturePhoto() async {
    final controller = _controller;
    if (controller == null || _busy) return;
    setState(() {
      _busy = true;
      _message = 'กำลังตรวจจับใบหน้า...';
    });
    try {
      final photo = await controller.takePicture();
      final bytes = await photo.readAsBytes();
      final descriptor = await faceDescriptorFromDataUrl('data:image/jpeg;base64,${base64Encode(bytes)}');
      if (!mounted) return;
      if (descriptor == null) {
        setState(() => _message = 'ไม่พบใบหน้าในภาพ กรุณาจัดใบหน้าให้อยู่ในกรอบและมีแสงสว่างพอ แล้วลองใหม่');
        return;
      }
      final capture = FaceCapture(bytes, descriptor);
      setState(() {
        _capture = capture;
        _message = null;
      });
      widget.onChanged(capture);
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
    final controller = _controller;
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
                : (controller != null && controller.value.isInitialized
                    ? FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(
                          width: controller.value.previewSize?.height ?? _size,
                          height: controller.value.previewSize?.width ?? _size,
                          child: CameraPreview(controller),
                        ),
                      )
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
              child: Text(_message!, textAlign: TextAlign.center, style: TextStyle(color: _busy ? Colors.grey : Colors.red, fontSize: 13)),
            ),
          ElevatedButton.icon(
            onPressed: (controller == null || _busy) ? null : _capturePhoto,
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
