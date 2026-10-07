import 'package:flutter/material.dart';
import '../models/merchant_models.dart';
import '../services/api_client.dart';
import '../theme.dart';
import '../widgets/shop_detail.dart';
import 'merchant_form_screen.dart';

/// Your partner shops: status, the reason when one needs changes, and edit / withdraw.
class MyShopsScreen extends StatefulWidget {
  const MyShopsScreen({super.key});

  @override
  State<MyShopsScreen> createState() => _MyShopsScreenState();
}

class _MyShopsScreenState extends State<MyShopsScreen> {
  List<MyShop> _shops = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final data = await apiClient.get('/merchants/mine');
      if (!mounted) return;
      setState(() {
        _shops = (data['shops'] as List).map((e) => MyShop.fromJson(e)).toList();
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'โหลดไม่สำเร็จ: $e';
        });
      }
    }
  }

  Future<void> _edit(String? id) async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => MerchantFormScreen(merchantId: id)));
    if (saved == true) _load();
  }

  Future<void> _withdraw(MyShop s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ถอนคำร้องนี้?'),
        content: Text('ลบ "${s.nameTh}" ออกจากรายการ ข้อมูลและรูปภาพของร้านจะถูกลบทั้งหมด'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('ยกเลิก')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('ลบ', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await apiClient.delete('/merchants/${s.merchantId}');
      _load();
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  (String, Color) _status(MyShop s) {
    switch (s.status) {
      case 'PENDING':
        return ('รอแอดมินอนุมัติ', Colors.orange);
      case 'APPROVED':
        return (s.hasPendingRevision ? 'เปิดอยู่ (มีการแก้ไขรออนุมัติ)' : 'เปิดอยู่บนแผนที่', AppColors.success);
      case 'REJECTED':
        return ('ต้องแก้ไข', Colors.red);
      default:
        return ('ถูกระงับ', Colors.grey);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ร้านค้าของฉัน')),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _edit(null), icon: const Icon(Icons.add_business), label: const Text('เพิ่มร้านค้า')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _shops.isEmpty
                      ? ListView(children: const [Padding(padding: EdgeInsets.all(40), child: Center(child: Text('ยังไม่มีร้านค้า\nกด "เพิ่มร้านค้า" เพื่อลงทะเบียนร้านพันธมิตร', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey))))])
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
                          children: _shops.map(_tile).toList(),
                        ),
                ),
    );
  }

  Widget _tile(MyShop s) {
    final (label, color) = _status(s);
    final cat = s.cat;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(backgroundColor: cat.color, child: Icon(cat.icon, color: Colors.white)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.nameTh, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                Text(cat.label, style: const TextStyle(color: Colors.grey)),
              ]),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
              child: Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ]),
          if (s.rejectReason != null && s.status == 'REJECTED') Padding(padding: const EdgeInsets.only(top: 10), child: Text('เหตุผล: ${s.rejectReason}', style: const TextStyle(color: Colors.red))),
          if (s.revisionNote != null && !s.hasPendingRevision) Padding(padding: const EdgeInsets.only(top: 10), child: Text('การแก้ไขล่าสุดไม่ได้รับอนุมัติ: ${s.revisionNote}', style: const TextStyle(color: Colors.red))),
          const SizedBox(height: 10),
          Wrap(spacing: 8, children: [
            if (s.status != 'SUSPENDED') OutlinedButton.icon(icon: const Icon(Icons.edit, size: 18), label: const Text('แก้ไข'), onPressed: () => _edit(s.merchantId)),
            if (s.status == 'APPROVED')
              TextButton.icon(
                icon: const Icon(Icons.visibility_outlined, size: 18),
                label: const Text('ดูหน้าร้าน'),
                onPressed: () => showShopDetail(
                  context,
                  ShopPin(merchantId: s.merchantId, nameTh: s.nameTh, nameEn: s.nameEn, category: s.category, latitude: 0, longitude: 0, hasCover: s.hasCover, rev: s.rev),
                ),
              ),
            if (s.status == 'PENDING' || s.status == 'REJECTED') TextButton.icon(icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red), label: const Text('ถอนคำร้อง', style: TextStyle(color: Colors.red)), onPressed: () => _withdraw(s)),
          ]),
        ]),
      ),
    );
  }
}
