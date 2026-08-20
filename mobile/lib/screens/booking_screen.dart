import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/api_client.dart';
import '../theme.dart';
import 'hotel_detail_screen.dart';

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
                              return _HotelResultCard(
                                offer: h,
                                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                                      builder: (_) => HotelDetailScreen(offer: h, checkIn: _checkIn, checkOut: _checkOut),
                                    )),
                              );
                            },
                          ),
          ),
        ],
      ),
    );
  }
}

class _HotelResultCard extends StatelessWidget {
  final HotelOffer offer;
  final VoidCallback onTap;
  const _HotelResultCard({required this.offer, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      clipBehavior: Clip.antiAlias,
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 180,
              width: double.infinity,
              child: offer.largePhotoUrl != null
                  ? Image.network(
                      offer.largePhotoUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (ctx, err, st) => Container(color: AppColors.navy, child: const Icon(Icons.hotel, color: Colors.white54, size: 48)),
                    )
                  : Container(color: AppColors.navy, child: const Icon(Icons.hotel, color: Colors.white54, size: 48)),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(offer.hotelName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  if (offer.starClass != null && offer.starClass! > 0) ...[
                    const SizedBox(height: 4),
                    Row(children: List.generate(offer.starClass!, (_) => const Icon(Icons.star, size: 14, color: Colors.amber))),
                  ],
                  const SizedBox(height: 6),
                  if (offer.address != null)
                    Row(
                      children: [
                        const Icon(Icons.location_on, size: 14, color: Colors.grey),
                        const SizedBox(width: 4),
                        Expanded(child: Text(offer.address!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.grey, fontSize: 12))),
                      ],
                    ),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (offer.reviewScore != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(6)),
                          child: Text(offer.reviewScore!.toStringAsFixed(1), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                        ),
                        const SizedBox(width: 8),
                        if (offer.reviewScoreWord != null)
                          Flexible(
                            child: Text(
                              '${offer.reviewScoreWord}${offer.reviewCount != null ? ' (${offer.reviewCount})' : ''}',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      const Spacer(),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            offer.priceAmount != null ? offer.priceAmount!.toStringAsFixed(0) : '-',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: AppColors.navy),
                          ),
                          Text(offer.priceCurrency ?? '', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
