Future<void> preloadFaceModels() async {}

/// Face matching runs in the browser; other platforms are not supported yet.
Future<List<double>?> faceDescriptorFromDataUrl(String dataUrl) async {
  throw UnsupportedError('การสแกนใบหน้ารองรับเฉพาะบนเว็บ');
}
