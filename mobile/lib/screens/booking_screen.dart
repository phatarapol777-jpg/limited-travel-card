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

class _HotelResultCard extends StatefulWidget {
  final HotelOffer offer;
  final VoidCallback onTap;
  const _HotelResultCard({required this.offer, required this.onTap});

  @override
  State<_HotelResultCard> createState() => _HotelResultCardState();
}

class _HotelResultCardState extends State<_HotelResultCard> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  List<String> _photoUrls = [];
  int _photoIndex = 0;
  final _pageController = PageController();

  @override
  void initState() {
    super.initState();
    final fallback = widget.offer.photoUrl;
    if (fallback != null) _photoUrls = [fallback];
    _loadPhotos();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadPhotos() async {
    final hotelId = widget.offer.externalHotelId;
    if (hotelId == null) return;
    try {
      final data = await apiClient.get('/booking/hotels/$hotelId/photos');
      final urls = (data['photos'] as List).map((e) => HotelPhoto.fromJson(e).thumbUrl).whereType<String>().take(5).toList();
      if (mounted && urls.isNotEmpty) setState(() => _photoUrls = urls);
    } catch (_) {
      // keep the single fallback photo already shown
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final offer = widget.offer;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      elevation: 2,
      child: InkWell(
        onTap: widget.onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: IntrinsicHeight(
            child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 110,
                  height: 110,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (_photoUrls.isEmpty)
                        Container(color: AppColors.navy, child: const Icon(Icons.hotel, color: Colors.white54, size: 32))
                      else
                        PageView.builder(
                          controller: _pageController,
                          itemCount: _photoUrls.length,
                          onPageChanged: (i) => setState(() => _photoIndex = i),
                          itemBuilder: (ctx, i) => Image.network(
                            _photoUrls[i],
                            fit: BoxFit.cover,
                            errorBuilder: (ctx, err, st) => Container(color: AppColors.navy, child: const Icon(Icons.hotel, color: Colors.white54, size: 32)),
                          ),
                        ),
                      if (_photoUrls.length > 1)
                        Positioned(
                          bottom: 5,
                          left: 0,
                          right: 0,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(
                              _photoUrls.length,
                              (i) => Container(
                                margin: const EdgeInsets.symmetric(horizontal: 1.5),
                                width: 5,
                                height: 5,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: i == _photoIndex ? Colors.white : Colors.white54,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(offer.hotelName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    if (offer.starClass != null && offer.starClass! > 0) ...[
                      const SizedBox(height: 2),
                      Row(children: List.generate(offer.starClass!, (_) => const Icon(Icons.star, size: 11, color: Colors.amber))),
                    ],
                    if (offer.address != null) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          const Icon(Icons.location_on, size: 12, color: Colors.grey),
                          const SizedBox(width: 3),
                          Expanded(child: Text(offer.address!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.grey, fontSize: 11))),
                        ],
                      ),
                    ],
                    if (offer.reviewScore != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(color: AppColors.navy, borderRadius: BorderRadius.circular(5)),
                            child: Text(offer.reviewScore!.toStringAsFixed(1), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11)),
                          ),
                          const SizedBox(width: 6),
                          if (offer.reviewScoreWord != null)
                            Flexible(
                              child: Text(
                                '${offer.reviewScoreWord}${offer.reviewCount != null ? ' (${offer.reviewCount})' : ''}',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                      ),
                    ],
                    const Spacer(),
                    Align(
                      alignment: Alignment.bottomRight,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            offer.priceAmount != null ? offer.priceAmount!.toStringAsFixed(0) : '-',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17, color: AppColors.navy),
                          ),
                          const SizedBox(width: 3),
                          Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Text(offer.priceCurrency ?? '', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
            ),
          ),
        ),
      ),
    );
  }
}
