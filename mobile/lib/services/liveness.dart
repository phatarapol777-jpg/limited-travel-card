import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'face_analysis.dart';
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

// Nose position across the jaw: ~0.5 facing the camera, drifts toward 0 or 1 when the head turns.
const _frontalTolerance = 0.09;
const _turnedDistance = 0.12;
const _sameFaceDistance = 0.6;

double _distance(List<double> a, List<double> b) {
  var sum = 0.0;
  for (var i = 0; i < a.length; i++) {
    sum += (a[i] - b[i]) * (a[i] - b[i]);
  }
  return sqrt(sum);
}

Future<(Uint8List, FaceAnalysis)> _grab(CameraController controller) async {
  final shot = await controller.takePicture();
  final bytes = await shot.readAsBytes();
  return (bytes, await analyzeFace('data:image/jpeg;base64,${base64Encode(bytes)}'));
}

/// Active liveness check: the person must face the camera and then turn their head to the side,
/// and both frames must show the same single face. A still photo or a non-face cannot do this.
/// Returns the frontal frame and its descriptor. [onPrompt] receives instructions to show the user.
Future<LivenessResult> runLivenessCheck(
  CameraController controller, {
  required void Function(String message) onPrompt,
  required bool Function() isActive,
}) async {
  Uint8List? frontalPhoto;
  List<double>? frontal;

  onPrompt('มองตรงที่กล้อง');
  var deadline = DateTime.now().add(const Duration(seconds: 15));
  while (frontal == null) {
    if (!isActive()) throw LivenessException('ยกเลิก');
    if (DateTime.now().isAfter(deadline)) throw LivenessException('ไม่พบใบหน้าที่ชัดเจน กรุณาลองใหม่');
    final (bytes, a) = await _grab(controller);
    if (a.problem != null) {
      onPrompt(a.problemMessage);
    } else if ((a.yaw - 0.5).abs() <= _frontalTolerance) {
      frontalPhoto = bytes;
      frontal = a.descriptor;
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
    final (_, a) = await _grab(controller);
    if (a.problem != null) {
      onPrompt(a.problemMessage);
      continue;
    }
    if ((a.yaw - 0.5).abs() >= _turnedDistance) {
      if (_distance(frontal, a.descriptor!) > _sameFaceDistance) {
        throw LivenessException('ใบหน้าไม่ตรงกันระหว่างการตรวจ กรุณาลองใหม่');
      }
      return LivenessResult(frontalPhoto!, frontal);
    }
    onPrompt('หันหน้าไปทางซ้ายหรือขวาเล็กน้อย');
  }
}
