/// Result of analysing one camera frame.
class FaceAnalysis {
  final List<double>? descriptor;
  final double yaw;

  /// null when exactly one clear face was found, otherwise one of: none, multiple, small.
  final String? problem;
  const FaceAnalysis({this.descriptor, this.yaw = 0.5, this.problem});

  factory FaceAnalysis.fromJson(Map<String, dynamic> j) => FaceAnalysis(
        descriptor: (j['descriptor'] as List?)?.map((e) => (e as num).toDouble()).toList(),
        yaw: (j['yaw'] as num?)?.toDouble() ?? 0.5,
        problem: j['problem'] as String?,
      );

  String get problemMessage {
    switch (problem) {
      case 'multiple':
        return 'พบหลายใบหน้าในภาพ กรุณาให้เหลือเฉพาะคุณคนเดียว';
      case 'small':
        return 'ใบหน้าเล็กเกินไป กรุณาเข้าใกล้กล้องอีกนิด';
      default:
        return 'ไม่พบใบหน้า กรุณาจัดใบหน้าให้อยู่ในกรอบและมีแสงสว่างพอ';
    }
  }
}
