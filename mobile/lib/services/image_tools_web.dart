import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

JSObject get _tools => globalContext['travelImage'] as JSObject;

/// Opens the photo picker and returns a JPEG resized to at most [maxSide] pixels and [maxChars] characters of
/// data URL, or null if the picker was cancelled. Must be called straight from a tap handler (iOS Safari only
/// allows the file dialog inside the tap, not after an await).
Future<String?> pickJpeg({int maxSide = 900, int maxChars = 400000}) async {
  final result = await _tools.callMethod<JSPromise<JSAny?>>('pick'.toJS, maxSide.toJS, maxChars.toJS).toDart;
  final text = (result as JSString).toDart;
  return text.isEmpty ? null : text;
}

void downloadDataUrl(String dataUrl, String filename) {
  _tools.callMethod<JSAny?>('download'.toJS, dataUrl.toJS, filename.toJS);
}

void openDataUrl(String dataUrl) {
  _tools.callMethod<JSAny?>('open'.toJS, dataUrl.toJS);
}

Uint8List decodeDataUrl(String dataUrl) => base64Decode(dataUrl.substring(dataUrl.indexOf(',') + 1));
