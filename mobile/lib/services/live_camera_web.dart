import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';
import 'package:flutter/widgets.dart';

JSObject get _cam => globalContext['travelCam'] as JSObject;

class CameraDevice {
  final String deviceId;
  final String label;
  const CameraDevice(this.deviceId, this.label);
}

/// One open browser camera. Opened with a single getUserMedia call (see `travelCam` in web/index.html).
class LiveCamera {
  final String id;
  final String label;
  final String deviceId;
  LiveCamera(this.id, this.label, this.deviceId);

  /// The current frame as JPEG bytes.
  Future<Uint8List> snapshot() async {
    final url = (_cam.callMethod<JSString>('snapshot'.toJS, id.toJS)).toDart;
    if (!url.startsWith('data:image/jpeg;base64,')) throw StateError('ไม่ได้ภาพจากกล้อง');
    return base64Decode(url.substring('data:image/jpeg;base64,'.length));
  }

  Future<void> close() async {
    _cam.callMethod<JSAny?>('close'.toJS, id.toJS);
  }
}

/// Opens the front (or back) camera, or a specific one by [deviceId]. Asks for camera permission once.
Future<LiveCamera> openLiveCamera({bool front = true, String? deviceId}) async {
  final opts = jsonEncode({'facing': front ? 'user' : 'environment', if (deviceId != null) 'deviceId': deviceId});
  final result = await _cam.callMethod<JSPromise<JSAny?>>('open'.toJS, opts.toJS).toDart;
  final json = jsonDecode((result as JSString).toDart) as Map<String, dynamic>;
  return LiveCamera(json['id'] as String, json['label'] as String, json['deviceId'] as String);
}

/// Video inputs (names are only filled in after camera permission has been granted).
Future<List<CameraDevice>> listCameras() async {
  final result = await _cam.callMethod<JSPromise<JSAny?>>('devices'.toJS).toDart;
  final list = jsonDecode((result as JSString).toDart) as List;
  return list.map((e) => CameraDevice(e['deviceId'] as String, e['label'] as String)).toList();
}

/// Live preview of [camera].
Widget liveCameraView(LiveCamera camera) => HtmlElementView.fromTagName(
      tagName: 'div',
      onElementCreated: (Object element) {
        _cam.callMethod<JSAny?>('mount'.toJS, camera.id.toJS, element as JSAny);
      },
    );
