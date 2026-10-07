import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'face_analysis.dart';

JSObject get _travelFace => globalContext['travelFace'] as JSObject;

/// Starts downloading the face models in the background so the first scan is fast.
Future<void> preloadFaceModels() async {
  try {
    await _travelFace.callMethod<JSPromise<JSAny?>>('preload'.toJS).toDart;
  } catch (_) {}
}

/// Checks the current live camera frame: head angle always, plus the face descriptor when the pose matches
/// [mode] ('frontal' or 'turned'). Needs exactly one clear face.
Future<FaceAnalysis> analyzeLiveFrame(String mode) async {
  final result = await _travelFace.callMethod<JSPromise<JSAny?>>('liveFrame'.toJS, mode.toJS).toDart;
  return FaceAnalysis.fromJson(jsonDecode((result as JSString).toDart) as Map<String, dynamic>);
}
