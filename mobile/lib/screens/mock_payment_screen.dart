import 'dart:async';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../theme.dart';

/// What the traveler chose on the demo payment page.
class MockPaymentResult {
  final String method; // card | promptpay | bank
  final String? bank;
  const MockPaymentResult(this.method, this.bank);
  Map<String, dynamic> toJson() => {'method': method, if (bank != null) 'bank': bank, 'demo': true};
}

/// Opens the demo payment page. Returns the chosen method when the traveler "pays", or null when they leave or time runs out.
Future<MockPaymentResult?> openMockPayment(BuildContext context, {required String title, required List<String> lines, required num? amount, String currency = '฿'}) {
  return Navigator.of(context).push<MockPaymentResult>(MaterialPageRoute(builder: (_) => MockPaymentScreen(title: title, lines: lines, amount: amount, currency: currency)));
}

String _money(num v) {
  final fixed = v.toStringAsFixed(v == v.roundToDouble() ? 0 : 2).split('.');
  final s = fixed[0];
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return fixed.length > 1 ? '$b.${fixed[1]}' : b.toString();
}

/// A pretend payment step for the demo: it looks like a checkout page but nothing is charged and no card or bank data is asked for.
class MockPaymentScreen extends StatefulWidget {
  final String title;
  final List<String> lines;
  final num? amount;
  final String currency;
  const MockPaymentScreen({super.key, required this.title, required this.lines, required this.amount, this.currency = '฿'});

  @override
  State<MockPaymentScreen> createState() => _MockPaymentScreenState();
}

class _MockPaymentScreenState extends State<MockPaymentScreen> {
  static const _banks = ['ธนาคารกรุงไทย', 'ธนาคารกสิกรไทย', 'ธนาคารไทยพาณิชย์', 'ธนาคารกรุงเทพ', 'ธนาคารกรุงศรี'];
  String _method = 'bank';
  String _bank = _banks.first;
  int _left = 30 * 60;
  Timer? _timer;
  bool _paying = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_left <= 1) {
        t.cancel();
        Navigator.of(context).pop();
        return;
      }
      setState(() => _left--);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _clock => '00:${(_left ~/ 60).toString().padLeft(2, '0')}:${(_left % 60).toString().padLeft(2, '0')}';

  Future<void> _pay() async {
    setState(() => _paying = true);
    await Future<void>.delayed(const Duration(milliseconds: 1600));
    if (!mounted) return;
    _timer?.cancel();
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.verified, color: AppColors.success, size: 44),
        title: const Text('ชำระเงินสำเร็จ (จำลอง)'),
        content: const Text('นี่เป็นหน้าตัวอย่างสำหรับสาธิต ไม่มีการตัดเงินจริง ระบบจะบันทึกคำขอจองของคุณต่อ'),
        actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('ตกลง'))],
      ),
    );
    if (mounted) Navigator.of(context).pop(MockPaymentResult(_method, _method == 'bank' ? _bank : null));
  }

  Widget _option(String id, IconData icon, String title, {String? subtitle, Widget? extra}) {
    final selected = _method == id;
    return Column(children: [
      InkWell(
        onTap: () => setState(() => _method = id),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(children: [
            Icon(icon, color: AppColors.navy, size: 28),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              if (subtitle != null) Text(subtitle, style: const TextStyle(color: Colors.grey, fontSize: 12)),
            ])),
            Icon(selected ? Icons.check_circle : Icons.radio_button_unchecked, color: selected ? const Color(0xFF2F6BFF) : Colors.grey),
          ]),
        ),
      ),
      if (selected && extra != null) Padding(padding: const EdgeInsets.only(left: 42, bottom: 12), child: extra),
      const Divider(height: 1),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('ชำระเงิน')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
          child: const Row(children: [
            Icon(Icons.science_outlined, color: Colors.orange),
            SizedBox(width: 8),
            Expanded(child: Text('หน้าชำระเงินจำลองเพื่อสาธิตเท่านั้น ไม่มีการตัดเงินและไม่ต้องกรอกข้อมูลบัตรหรือบัญชีจริง', style: TextStyle(fontSize: 12.5))),
          ]),
        ),
        const SizedBox(height: 18),
        const Center(child: Text('ระบบชำระเงินปลอดภัย (ตัวอย่าง)', style: TextStyle(color: AppColors.success, fontWeight: FontWeight.bold))),
        Center(child: Text('ชำระเงินให้เสร็จภายใน $_clock', style: const TextStyle(color: Colors.grey))),
        const SizedBox(height: 8),
        Center(child: Text(widget.amount == null ? '-' : '${widget.currency} ${_money(widget.amount!)}', style: const TextStyle(fontSize: 34, fontWeight: FontWeight.bold))),
        const SizedBox(height: 14),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              const SizedBox(height: 4),
              ...widget.lines.map((l) => Text(l, style: const TextStyle(color: Colors.black54, fontSize: 13))),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Column(children: [
              _option('card', Icons.credit_card, 'บัตรเครดิต/เดบิต', subtitle: 'Visa · Mastercard · JCB (ตัวอย่าง ไม่ต้องกรอกเลขบัตร)'),
              _option('promptpay', Icons.qr_code_2, 'QR PromptPay', subtitle: 'สแกนเพื่อชำระผ่านแอปธนาคาร',
                  extra: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(color: Colors.white, padding: const EdgeInsets.all(6), child: QrImageView(data: 'DEMO-ONLY-NOT-A-REAL-PAYMENT', size: 130)),
                    const SizedBox(height: 4),
                    const Text('QR ตัวอย่าง ใช้ชำระเงินจริงไม่ได้', style: TextStyle(fontSize: 11, color: Colors.grey)),
                  ])),
              _option('bank', Icons.account_balance, 'ธนาคารออนไลน์', subtitle: 'ชำระเงินผ่านแอปธนาคาร',
                  extra: Wrap(spacing: 8, runSpacing: 4, children: _banks.map((b) => ChoiceChip(label: Text(b, style: const TextStyle(fontSize: 12)), selected: _bank == b, onSelected: (_) => setState(() => _bank = b))).toList())),
            ]),
          ),
        ),
        const SizedBox(height: 18),
        ElevatedButton(
          style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(52), backgroundColor: const Color(0xFF2F6BFF)),
          onPressed: _paying ? null : _pay,
          child: _paying ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)) : const Text('ชำระตอนนี้', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
        ),
        const SizedBox(height: 24),
      ]),
    );
  }
}
