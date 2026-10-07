import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

JSObject get _travelFace => globalContext['travelFace'] as JSObject;

/// Starts downloading the face models in the background so the first scan is fast.
Future<void> preloadFaceModels() async {
  try {
    await _travelFace.callMethod<JSPromise<JSAny?>>('preload'.toJS).toDart;
  } catch (_) {}
}

/// Returns the 128-number face descriptor for the largest face in [dataUrl], or null if no face is found.
Future<List<double>?> faceDescriptorFromDataUrl(String dataUrl) async {
  final result = await _travelFace.callMethod<JSPromise<JSAny?>>('descriptorFromDataUrl'.toJS, dataUrl.toJS).toDart;
  if (result == null || result.isUndefinedOrNull) return null;
  final list = jsonDecode((result as JSString).toDart) as List;
  return list.map((e) => (e as num).toDouble()).toList();
}
