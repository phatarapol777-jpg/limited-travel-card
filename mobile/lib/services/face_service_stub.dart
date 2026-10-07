import 'face_analysis.dart';

Future<void> preloadFaceModels() async {}

/// Face matching runs in the browser; other platforms are not supported yet.
Future<FaceAnalysis> analyzeFace(String dataUrl) async {
  throw UnsupportedError('การสแกนใบหน้ารองรับเฉพาะบนเว็บ');
}
