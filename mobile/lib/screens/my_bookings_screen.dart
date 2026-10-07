import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../theme.dart';

class _Booking {
  final String id;
  final String kind; // hotel | flight | car
  final String title;
  final String detail;
  final String? extra;
  final num? price;
  final String currency;
  final String status; // requested | confirmed | rejected | cancelled
  final String requestedAt;
  final bool freeCancel;
  final String? payment;
  _Booking({required this.id, required this.kind, required this.title, required this.detail, this.extra, this.price, this.currency = 'THB', required this.status, required this.requestedAt, this.freeCancel = false, this.payment});
}

const _methodNames = {'card': 'บัตรเครดิต/เดบิต', 'promptpay': 'QR PromptPay', 'bank': 'ธนาคารออนไลน์'};

/// Everything you booked (hotels, flights, rental cars) with its status, and a button to cancel. The payment and the refund are demos.
class MyBookingsScreen extends StatefulWidget {
  const MyBookingsScreen({super.key});

  @override
  State<MyBookingsScreen> createState() => _MyBookingsScreenState();
}

class _MyBookingsScreenState extends State<MyBookingsScreen> {
  List<_Booking> _items = [];
  bool _loading = true;
  String? _error;
  String? _cancelling;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final hotels = await apiClient.get('/booking/requests');
      final other = await apiClient.get('/booking/transport/requests');
      final items = <_Booking>[];
      for (final r in (hotels['requests'] as List)) {
        items.add(_Booking(
          id: r['booking_request_id'],
          kind: 'hotel',
          title: '${r['hotel_name'] ?? 'ที่พัก'}',
          detail: 'เข้าพัก ${r['check_in_date']} ถึง ${r['check_out_date']}',
          extra: r['guest_name'] == null ? null : 'ผู้เข้าพัก ${r['guest_name']}',
          price: r['price_amount'] as num?,
          currency: '${r['price_currency'] ?? 'THB'}',
          status: '${r['status']}',
          requestedAt: '${r['requested_at']}',
        ));
      }
      for (final r in (other['requests'] as List)) {
        final summary = (r['summary'] as Map?) ?? const {};
        final car = summary['car'] as Map?;
        final badges = ((car?['badges'] as List?) ?? const []).map((e) => '$e').toList();
        final method = (summary['payment'] as Map?)?['method'];
        items.add(_Booking(
          id: r['request_id'],
          kind: '${r['kind']}',
          title: '${r['title']}',
          detail: r['kind'] == 'car' ? 'รับรถ ${summary['pick_up']} · คืนรถ ${summary['drop_off']}' : 'ผู้โดยสาร ${summary['adults'] ?? 1} คน',
          extra: car?['supplier'] == null ? null : 'ผู้ให้เช่า ${car!['supplier']}',
          price: r['price_amount'] as num?,
          currency: '${r['price_currency'] ?? 'THB'}',
          status: '${r['status']}',
          requestedAt: '${r['requested_at']}',
          freeCancel: badges.any((b) => b.toLowerCase().contains('free cancellation')),
          payment: method == null ? null : _methodNames['$method'],
        ));
      }
      items.sort((a, b) => b.requestedAt.compareTo(a.requestedAt));
      if (!mounted) return;
      setState(() {
        _items = items;
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

  (String, Color) _status(String s) {
    switch (s) {
      case 'confirmed':
        return ('ยืนยันแล้ว', AppColors.success);
      case 'rejected':
        return ('ไม่ได้รับการยืนยัน', Colors.red);
      case 'cancelled':
        return ('ยกเลิกแล้ว', Colors.grey);
      default:
        return ('รอยืนยัน', Colors.orange);
    }
  }

  IconData _icon(String kind) => kind == 'flight' ? Icons.flight : (kind == 'car' ? Icons.directions_car : Icons.hotel);

  Future<void> _cancel(_Booking b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.event_busy, color: Colors.red, size: 36),
        title: const Text('ยกเลิกการจองนี้?'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(b.title, style: const TextStyle(fontWeight: FontWeight.bold)),
          Text(b.detail),
          const SizedBox(height: 12),
          Text(b.freeCancel ? 'ยกเลิกฟรี ไม่มีค่าธรรมเนียม' : 'อาจมีค่าธรรมเนียมตามเงื่อนไขของผู้ให้บริการ', style: TextStyle(color: b.freeCancel ? AppColors.success : Colors.orange.shade800, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          const Text('เงินจะคืนตามวิธีที่ชำระ (การคืนเงินเป็นแบบจำลอง ไม่มีการโอนเงินจริง)', style: TextStyle(fontSize: 12, color: Colors.grey)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('ไม่ยกเลิก')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('ยืนยันยกเลิก', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _cancelling = b.id);
    try {
      await apiClient.post(b.kind == 'hotel' ? '/booking/requests/${b.id}/cancel' : '/booking/transport/requests/${b.id}/cancel');
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ยกเลิกการจองแล้ว คืนเงินตามวิธีที่ชำระ (จำลอง)')));
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      await _load();
    } finally {
      if (mounted) setState(() => _cancelling = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('การจองของฉัน')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _items.isEmpty
                      ? ListView(children: const [Padding(padding: EdgeInsets.all(40), child: Center(child: Text('ยังไม่มีการจอง\nจองที่พัก เที่ยวบิน หรือรถเช่าจากหน้าแผนที่', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey))))])
                      : ListView(
                          padding: const EdgeInsets.all(16),
                          children: _items.map((b) {
                            final (label, color) = _status(b.status);
                            final canCancel = b.status == 'requested' || b.status == 'confirmed';
                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                  Row(children: [
                                    CircleAvatar(backgroundColor: AppColors.navy.withValues(alpha: 0.1), child: Icon(_icon(b.kind), color: AppColors.navy)),
                                    const SizedBox(width: 10),
                                    Expanded(child: Text(b.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
                                      child: Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
                                    ),
                                  ]),
                                  const SizedBox(height: 8),
                                  Text(b.detail),
                                  if (b.extra != null) Text(b.extra!, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                                  const SizedBox(height: 4),
                                  Text('${b.price == null ? '' : '${b.currency == 'THB' ? '฿' : b.currency} ${b.price!.round()}'}${b.payment == null ? '' : ' · ชำระด้วย ${b.payment} (จำลอง)'}', style: const TextStyle(color: AppColors.navy, fontWeight: FontWeight.w600)),
                                  if (canCancel) ...[
                                    const SizedBox(height: 8),
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: OutlinedButton.icon(
                                        style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red)),
                                        icon: _cancelling == b.id ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.close, size: 18),
                                        label: const Text('ยกเลิกการจอง'),
                                        onPressed: _cancelling != null ? null : () => _cancel(b),
                                      ),
                                    ),
                                  ],
                                ]),
                              ),
                            );
                          }).toList(),
                        ),
                ),
    );
  }
}
