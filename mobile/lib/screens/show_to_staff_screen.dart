import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/merchant_models.dart';
import '../models/models.dart';
import '../services/api_client.dart';
import '../services/app_state.dart';
import '../theme.dart';
import '../widgets/card_widgets.dart';

/// Full-screen proof for the shop staff: the traveler's card (serial number, name), the perk, and a live clock so a
/// screenshot is easy to tell apart from the real thing. Staff just look at it; there is nothing to scan.
class ShowToStaffScreen extends StatefulWidget {
  final ShopPin shop;
  final ShopPrivilege privilege;
  const ShowToStaffScreen({super.key, required this.shop, required this.privilege});

  @override
  State<ShowToStaffScreen> createState() => _ShowToStaffScreenState();
}

class _ShowToStaffScreenState extends State<ShowToStaffScreen> with SingleTickerProviderStateMixin {
  TravelCard? _card;
  bool _loading = true;
  String? _error;
  DateTime _now = DateTime.now();
  Timer? _clock;
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) => setState(() => _now = DateTime.now()));
    _load();
  }

  @override
  void dispose() {
    _clock?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await apiClient.get('/cards');
      final cards = (data['cards'] as List).map((e) => TravelCard.fromJson(e)).where((c) => c.templateId == widget.privilege.templateId).toList();
      if (!mounted) return;
      setState(() {
        _card = cards.isEmpty ? null : cards.first;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'โหลดการ์ดไม่สำเร็จ: $e';
          _loading = false;
        });
      }
    }
  }

  String two(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AppState>().currentUser;
    final p = widget.privilege;
    return Scaffold(
      backgroundColor: AppColors.navyDark,
      appBar: AppBar(title: const Text('แสดงให้พนักงานร้าน'), backgroundColor: AppColors.navyDark, foregroundColor: Colors.white),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, style: const TextStyle(color: Colors.white))))
              : _card == null
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.style_outlined, color: AppColors.gold, size: 48),
                          const SizedBox(height: 14),
                          Text('คุณยังไม่มีการ์ด "${p.cardName}"', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                          const SizedBox(height: 8),
                          const Text('สะสมการ์ดใบนี้ก่อน แล้วค่อยมาแสดงที่ร้านเพื่อรับสิทธิประโยชน์', textAlign: TextAlign.center, style: TextStyle(color: Colors.white70)),
                        ]),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        Text(widget.shop.nameTh, textAlign: TextAlign.center, style: const TextStyle(color: AppColors.gold, fontSize: 20, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        Text(p.description, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 16)),
                        const SizedBox(height: 18),
                        Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 260),
                            child: AnimatedBuilder(
                              animation: _pulse,
                              builder: (_, child) => Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(24),
                                  boxShadow: [BoxShadow(color: AppColors.gold.withValues(alpha: 0.25 + 0.4 * _pulse.value), blurRadius: 12 + 20 * _pulse.value)],
                                ),
                                child: child,
                              ),
                              child: CardFace(card: _card!, large: true),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(user?.username == null ? '' : '@${user!.username}', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                        if (_card!.serialLabel != null)
                          Text('การ์ดหมายเลข ${_card!.serialLabel}', textAlign: TextAlign.center, style: const TextStyle(color: AppColors.gold, fontSize: 16, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 14),
                        Text('${two(_now.hour)}:${two(_now.minute)}:${two(_now.second)}', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 40, fontWeight: FontWeight.w300, letterSpacing: 2)),
                        Text('${_now.day}/${_now.month}/${_now.year}', textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54)),
                        const SizedBox(height: 14),
                        Text(p.validNow ? 'ใช้ได้: ${p.period}' : 'สิทธิประโยชน์นี้ยังไม่เริ่ม (${p.period})', textAlign: TextAlign.center, style: TextStyle(color: p.validNow ? Colors.white70 : Colors.orangeAccent)),
                      ],
                    ),
    );
  }
}
