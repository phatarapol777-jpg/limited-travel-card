import 'package:flutter/material.dart';
import '../theme.dart';

class CountdownRing extends StatelessWidget {
  final int secondsRemaining;
  final int totalSeconds;
  const CountdownRing({super.key, required this.secondsRemaining, required this.totalSeconds});

  @override
  Widget build(BuildContext context) {
    final progress = totalSeconds == 0 ? 0.0 : secondsRemaining / totalSeconds;
    final minutes = (secondsRemaining ~/ 60).toString().padLeft(2, '0');
    final seconds = (secondsRemaining % 60).toString().padLeft(2, '0');
    return SizedBox(
      width: 96,
      height: 96,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 96,
            height: 96,
            child: CircularProgressIndicator(
              value: progress.clamp(0.0, 1.0),
              strokeWidth: 6,
              backgroundColor: const Color(0xFFE3E7EF),
              valueColor: AlwaysStoppedAnimation(secondsRemaining < 30 ? Colors.redAccent : AppColors.gold),
            ),
          ),
          Text('$minutes:$seconds', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.navy)),
        ],
      ),
    );
  }
}
