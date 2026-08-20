import 'dart:math';
import 'package:flutter/material.dart';
import '../theme.dart';

class FaceScanWidget extends StatefulWidget {
  final bool complete;
  const FaceScanWidget({super.key, required this.complete});

  @override
  State<FaceScanWidget> createState() => _FaceScanWidgetState();
}

class _FaceScanWidgetState extends State<FaceScanWidget> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const size = 220.0;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: size - 20,
            height: size - 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.navy.withValues(alpha: 0.06),
              border: Border.all(color: AppColors.navy.withValues(alpha: 0.25), width: 1.5),
            ),
          ),
          Icon(Icons.face_retouching_natural, size: 96, color: AppColors.navy.withValues(alpha: widget.complete ? 0.85 : 0.35)),
          CustomPaint(size: const Size(size, size), painter: _FaceMeshPainter()),
          ...List.generate(4, (i) => _CornerBracket(index: i, size: size)),
          if (!widget.complete)
            AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                final y = (size - 30) * _controller.value + 15;
                return Positioned(
                  top: y,
                  child: Container(
                    width: size - 40,
                    height: 2.5,
                    decoration: BoxDecoration(
                      color: AppColors.gold,
                      boxShadow: [BoxShadow(color: AppColors.gold.withValues(alpha: 0.7), blurRadius: 6)],
                    ),
                  ),
                );
              },
            ),
          if (widget.complete)
            const Positioned(
              bottom: 12,
              child: Icon(Icons.check_circle, color: AppColors.success, size: 32),
            ),
        ],
      ),
    );
  }
}

class _CornerBracket extends StatelessWidget {
  final int index;
  final double size;
  const _CornerBracket({required this.index, required this.size});

  @override
  Widget build(BuildContext context) {
    final isTop = index < 2;
    final isLeft = index % 2 == 0;
    return Positioned(
      top: isTop ? 0 : null,
      bottom: isTop ? null : 0,
      left: isLeft ? 0 : null,
      right: isLeft ? null : 0,
      child: CustomPaint(
        size: const Size(28, 28),
        painter: _BracketPainter(top: isTop, left: isLeft),
      ),
    );
  }
}

class _BracketPainter extends CustomPainter {
  final bool top;
  final bool left;
  _BracketPainter({required this.top, required this.left});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.navy
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final path = Path();
    final y = top ? 0.0 : size.height;
    final dy = top ? size.height * 0.7 : -size.height * 0.7;
    final x = left ? 0.0 : size.width;
    final dx = left ? size.width * 0.7 : -size.width * 0.7;
    path.moveTo(x, y + dy);
    path.lineTo(x, y);
    path.lineTo(x + dx, y);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _FaceMeshPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.gold.withValues(alpha: 0.55)
      ..style = PaintingStyle.fill;
    final rand = Random(7);
    final center = size.center(Offset.zero);
    for (int i = 0; i < 18; i++) {
      final angle = rand.nextDouble() * 2 * pi;
      final radius = 35 + rand.nextDouble() * 45;
      final p = center + Offset(cos(angle) * radius, sin(angle) * radius * 1.1);
      canvas.drawCircle(p, 1.6, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
