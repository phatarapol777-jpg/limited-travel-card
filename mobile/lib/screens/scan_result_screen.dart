import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../services/app_state.dart';
import '../theme.dart';
import '../widgets/card_widgets.dart';
import 'card_detail_screen.dart';

/// The reveal after scanning a quest or a physical card: the new card, or why it did not work.
class ScanResultScreen extends StatefulWidget {
  final String title;
  final TravelCard? card;
  final String? error;
  const ScanResultScreen({super.key, required this.title, this.card, this.error});

  @override
  State<ScanResultScreen> createState() => _ScanResultScreenState();
}

class _ScanResultScreenState extends State<ScanResultScreen> {
  @override
  void initState() {
    super.initState();
    if (widget.card != null) WidgetsBinding.instance.addPostFrameCallback((_) => context.read<AppState>().refreshStats());
  }

  @override
  Widget build(BuildContext context) {
    final card = widget.card;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: card == null
              ? Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.error_outline, color: Colors.redAccent, size: 64),
                  const SizedBox(height: 14),
                  Text(widget.error ?? 'เกิดข้อผิดพลาด', textAlign: TextAlign.center, style: const TextStyle(fontSize: 16)),
                  const SizedBox(height: 24),
                  ElevatedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('กลับ')),
                ])
              : Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.celebration, color: AppColors.gold, size: 44),
                  const SizedBox(height: 8),
                  const Text('ปลดล็อกการ์ดใหม่!', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 18),
                  ConstrainedBox(constraints: const BoxConstraints(maxWidth: 280), child: TiltCard(child: CardFace(card: card, large: true))),
                  const SizedBox(height: 10),
                  const Text('ลากนิ้วบนการ์ดเพื่อเอียงดู', style: TextStyle(color: Colors.grey, fontSize: 12)),
                  const SizedBox(height: 22),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => CardDetailScreen(card: card))),
                    child: const Text('ดูรายละเอียดการ์ด'),
                  ),
                  const SizedBox(height: 10),
                  TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('เสร็จสิ้น')),
                ]),
        ),
      ),
    );
  }
}
