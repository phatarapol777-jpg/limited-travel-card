import 'face_analysis.dart';

Future<void> preloadFaceModels() async {}

/// Face matching and QR reading run in the browser; other platforms are not supported yet.
Future<FaceAnalysis> analyzeLiveFrame(String mode, {String? label}) async {
  throw UnsupportedError('การสแกนใบหน้ารองรับเฉพาะบนเว็บ');
}

String readQrFromCamera({String? label}) => '';
