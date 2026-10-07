import 'face_analysis.dart';

Future<void> preloadFaceModels() async {}

/// Face matching runs in the browser; other platforms are not supported yet.
Future<FaceAnalysis> analyzeLiveFrame(String mode) async {
  throw UnsupportedError('การสแกนใบหน้ารองรับเฉพาะบนเว็บ');
}
