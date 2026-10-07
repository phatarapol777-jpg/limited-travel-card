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

/// Detects the face in a JPEG data URL (exactly one clear face required) and returns its descriptor and head angle.
Future<FaceAnalysis> analyzeFace(String dataUrl) async {
  final result = await _travelFace.callMethod<JSPromise<JSAny?>>('analyze'.toJS, dataUrl.toJS).toDart;
  return FaceAnalysis.fromJson(jsonDecode((result as JSString).toDart) as Map<String, dynamic>);
}
