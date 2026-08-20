import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/api_client.dart';
import '../theme.dart';

class BookingScreen extends StatefulWidget {
  final TravelLocation location;
  const BookingScreen({super.key, required this.location});

  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  late DateTime _checkIn;
  late DateTime _checkOut;
  int _adults = 2;
  bool _loading = false;
  String? _error;
  String? _infoMessage;
  List<HotelOffer> _hotels = [];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _checkIn = DateTime(now.year, now.month, now.day).add(const Duration(days: 14));
    _checkOut = _checkIn.add(const Duration(days: 2));
    _search();
  }

  String _fmt(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _pickDate({required bool isCheckIn}) async {
    final initial = isCheckIn ? _checkIn : _checkOut;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      if (isCheckIn) {
        _checkIn = picked;
        if (!_checkOut.isAfter(_checkIn)) _checkOut = _checkIn.add(const Duration(days: 1));
      } else {
        _checkOut = picked;
      }
    });
  }

  Future<void> _search() async {
    setState(() {
      _loading = true;
      _error = null;
      _infoMessage = null;
    });
    try {
      final data = await apiClient.get(
        '/booking/hotels?location_id=${widget.location.locationId}&check_in=${_fmt(_checkIn)}&check_out=${_fmt(_checkOut)}&adults=$_adults',
      );
      final hotels = (data['hotels'] as List).map((e) => HotelOffer.fromJson(e)).toList();
      setState(() {
        _hotels = hotels;
        _loading = false;
        if (hotels.isEmpty) {
          _infoMessage = 'ไม่พบข้อเสนอโรงแรมสำหรับเงื่อนไขนี้ ลองเปลี่ยนวันที่ดู';
        }
      });
    } on ApiException catch (e) {
      setState(() {
        _loading = false;
        _error = e.message;
      });
    } catch (e) {
      setState(() {
        _loading = false;
        _error = 'เชื่อมต่อไม่สำเร็จ: $e';
      });
    }
  }

  void _openRequestDialog(HotelOffer offer) {
    final nameCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(offer.hotelName),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (offer.roomDescription != null) ...[
              Text(offer.roomDescription!, style: const TextStyle(color: Colors.grey)),
              const SizedBox(height: 12),
            ],
            Text(
              offer.priceAmount != null ? '${offer.priceAmount!.toStringAsFixed(2)} ${offer.priceCurrency ?? ''}' : 'ราคาไม่ระบุ',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.navy),
            ),
            const SizedBox(height: 16),
            TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'ชื่อผู้เข้าพัก')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('ยกเลิก')),
          ElevatedButton(
            onPressed: () async {
              try {
                await apiClient.post('/booking/request', {
                  'offer_id': offer.offerId,
                  'guest_name': nameCtrl.text.trim().isEmpty ? null : nameCtrl.text.trim(),
                });
                if (!mounted) return;
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('ส่งคำขอจอง "${offer.hotelName}" สำเร็จ')),
                );
              } on ApiException catch (e) {
                ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(e.message)));
              }
            },
            child: const Text('ยืนยันคำขอจอง'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('ที่พักใกล้ ${widget.location.name}')),
      body: Column(
        children: [
          Container(
            color: Colors.white,
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.calendar_today, size: 16),
                        label: Text('เช็คอิน ${_fmt(_checkIn)}'),
                        onPressed: () => _pickDate(isCheckIn: true),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.calendar_today, size: 16),
                        label: Text('เช็คเอาต์ ${_fmt(_checkOut)}'),
                        onPressed: () => _pickDate(isCheckIn: false),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Text('ผู้เข้าพัก:'),
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: _adults > 1 ? () => setState(() => _adults--) : null,
                    ),
                    Text('$_adults'),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      onPressed: _adults < 8 ? () => setState(() => _adults++) : null,
                    ),
                    const Spacer(),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.search),
                      label: const Text('ค้นหา'),
                      onPressed: _loading ? null : _search,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.red))))
                    : _hotels.isEmpty
                        ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_infoMessage ?? 'ไม่พบข้อเสนอ', textAlign: TextAlign.center)))
                        : ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _hotels.length,
                            itemBuilder: (ctx, i) {
                              final h = _hotels[i];
                              return Card(
                                margin: const EdgeInsets.only(bottom: 10),
                                child: ListTile(
                                  leading: const CircleAvatar(backgroundColor: AppColors.navy, child: Icon(Icons.hotel, color: Colors.white)),
                                  title: Text(h.hotelName, style: const TextStyle(fontWeight: FontWeight.bold)),
                                  subtitle: Text(h.roomDescription ?? 'ห้องพักมาตรฐาน', maxLines: 2, overflow: TextOverflow.ellipsis),
                                  trailing: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        h.priceAmount != null ? h.priceAmount!.toStringAsFixed(0) : '-',
                                        style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.navy),
                                      ),
                                      Text(h.priceCurrency ?? '', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                    ],
                                  ),
                                  onTap: () => _openRequestDialog(h),
                                ),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}
