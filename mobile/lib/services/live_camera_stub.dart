import 'dart:typed_data';
import 'package:flutter/widgets.dart';

class CameraDevice {
  final String deviceId;
  final String label;
  const CameraDevice(this.deviceId, this.label);
}

class LiveCamera {
  final String id;
  final String label;
  final String deviceId;
  LiveCamera(this.id, this.label, this.deviceId);

  Future<Uint8List> snapshot() async => throw UnsupportedError('กล้องรองรับเฉพาะบนเว็บ');
  Future<void> close() async {}
}

Future<LiveCamera> openLiveCamera({bool front = true, String? deviceId}) async =>
    throw UnsupportedError('กล้องรองรับเฉพาะบนเว็บ');

Future<List<CameraDevice>> listCameras() async => const [];

Widget liveCameraView(LiveCamera camera) => const SizedBox.shrink();
