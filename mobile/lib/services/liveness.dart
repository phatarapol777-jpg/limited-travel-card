import 'dart:math';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'face_service.dart';

class LivenessException implements Exception {
  final String message;
  LivenessException(this.message);
  @override
  String toString() => message;
}

class LivenessResult {
  final Uint8List photo;
  final List<double> descriptor;
  LivenessResult(this.photo, this.descriptor);
}

// Same-face limit between the facing-camera frame and the turned frame (looser than the match threshold
// because a turned face changes the descriptor).
const _sameFaceDistance = 0.6;

double _distance(List<double> a, List<double> b) {
  var sum = 0.0;
  for (var i = 0; i < a.length; i++) {
    sum += (a[i] - b[i]) * (a[i] - b[i]);
  }
  return sqrt(sum);
}

/// Active liveness check: the person must face the camera and then turn their head to the side,
/// and both frames must show the same single face. A still photo or a non-face cannot do this.
/// Frames are read straight from the live video, so each check takes a fraction of a second.
/// Returns a photo of the facing-camera frame and its descriptor. [onPrompt] receives instructions for the user;
/// [cameraLabel] picks the camera when several are open and [tick] runs once per frame (the kiosk reads the phone's QR there).
Future<LivenessResult> runLivenessCheck(
  CameraController controller, {
  required void Function(String message) onPrompt,
  required bool Function() isActive,
  String? cameraLabel,
  Future<void> Function()? tick,
}) async {
  Uint8List? photo;
  List<double>? frontal;

  onPrompt('มองตรงที่กล้อง');
  var deadline = DateTime.now().add(const Duration(seconds: 20));
  while (frontal == null) {
    if (!isActive()) throw LivenessException('ยกเลิก');
    if (DateTime.now().isAfter(deadline)) throw LivenessException('ไม่พบใบหน้าที่ชัดเจน กรุณาลองใหม่');
    await tick?.call();
    final a = await analyzeLiveFrame('frontal', label: cameraLabel);
    if (a.problem != null) {
      onPrompt(a.problemMessage);
    } else if (a.descriptor != null) {
      frontal = a.descriptor;
      photo = await (await controller.takePicture()).readAsBytes();
    } else {
      onPrompt('มองตรงที่กล้อง');
    }
  }

  onPrompt('ตรวจพบใบหน้าแล้ว กรุณาหันหน้าไปทางซ้ายหรือขวาเล็กน้อย');
  deadline = DateTime.now().add(const Duration(seconds: 10));
  while (true) {
    if (!isActive()) throw LivenessException('ยกเลิก');
    if (DateTime.now().isAfter(deadline)) {
      throw LivenessException('ไม่พบการหันหน้า กรุณาลองใหม่ (ต้องเป็นใบหน้าจริง ไม่ใช่รูปภาพ)');
    }
    await tick?.call();
    final a = await analyzeLiveFrame('turned', label: cameraLabel);
    if (a.problem != null) {
      onPrompt(a.problemMessage);
      continue;
    }
    if (a.descriptor != null) {
      if (_distance(frontal, a.descriptor!) > _sameFaceDistance) {
        throw LivenessException('ใบหน้าไม่ตรงกันระหว่างการตรวจ กรุณาลองใหม่');
      }
      return LivenessResult(photo!, frontal);
    }
    onPrompt('หันหน้าไปทางซ้ายหรือขวาเล็กน้อย');
  }
}
