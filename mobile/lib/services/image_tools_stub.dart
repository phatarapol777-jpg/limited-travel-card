import 'dart:typed_data';

/// Opens the photo picker and returns a resized JPEG as a data URL (null if cancelled). Web only.
Future<String?> pickJpeg({int maxSide = 900, int maxChars = 400000}) async => throw UnsupportedError('เลือกรูปได้เฉพาะบนเว็บ');

/// Saves an image (data URL) to the device.
void downloadDataUrl(String dataUrl, String filename) {}

/// Opens an image (data URL) in a new tab so it can be long-pressed and saved (iOS Safari ignores downloads).
void openDataUrl(String dataUrl) {}

Uint8List decodeDataUrl(String dataUrl) => Uint8List(0);
