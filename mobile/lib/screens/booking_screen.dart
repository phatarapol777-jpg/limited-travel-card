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

enum _SortOption { popularity, priceLowHigh, priceHighLow, ratingHigh }

class _BookingScreenState extends State<BookingScreen> {
  late DateTime _checkIn;
  late DateTime _checkOut;
  int _adults = 2;
  int _children = 0;
  int _rooms = 1;
  bool _loading = false;
  String? _error;
  String? _infoMessage;
  List<HotelOffer> _hotels = [];

  _SortOption _sortOption = _SortOption.popularity;
  RangeValues _priceRange = const RangeValues(0, 10000);
  double _priceCeiling = 10000;
  bool _filterFreeParking = false;
  bool _filterPool = false;
  bool _filterBreakfast = false;

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
        '/booking/hotels?location_id=${widget.location.locationId}&check_in=${_fmt(_checkIn)}&check_out=${_fmt(_checkOut)}'
        '&adults=$_adults&children=$_children&rooms=$_rooms',
      );
      final hotels = (data['hotels'] as List).map((e) => HotelOffer.fromJson(e)).toList();
      final maxPrice = hotels.map((h) => h.priceAmount ?? 0).fold(0.0, (a, b) => a > b ? a : b);
      setState(() {
        _hotels = hotels;
        _loading = false;
        _priceCeiling = maxPrice > 0 ? (maxPrice / 500).ceil() * 500 : 10000;
        _priceRange = RangeValues(0, _priceCeiling);
        _filterFreeParking = false;
        _filterPool = false;
        _filterBreakfast = false;
        _sortOption = _SortOption.popularity;
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

  List<HotelOffer> get _displayedHotels {
    var list = _hotels.where((h) {
      final price = h.priceAmount ?? 0;
      if (price < _priceRange.start || price > _priceRange.end) return false;
      if (_filterFreeParking && !h.hasFreeParking) return false;
      if (_filterPool && !h.hasSwimmingPool) return false;
      if (_filterBreakfast && !h.includeBreakfast) return false;
      return true;
    }).toList();
    switch (_sortOption) {
      case _SortOption.priceLowHigh:
        list.sort((a, b) => (a.priceAmount ?? 0).compareTo(b.priceAmount ?? 0));
        break;
      case _SortOption.priceHighLow:
        list.sort((a, b) => (b.priceAmount ?? 0).compareTo(a.priceAmount ?? 0));
        break;
      case _SortOption.ratingHigh:
        list.sort((a, b) => (b.reviewScore ?? 0).compareTo(a.reviewScore ?? 0));
        break;
      case _SortOption.popularity:
        break;
    }
    return list;
  }

  Future<void> _openGuestPicker() async {
    await showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('เลือกจำนวนผู้เข้าพัก', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 16),
                _GuestStepper(
                  label: 'ผู้ใหญ่',
                  value: _adults,
                  min: 1,
                  max: 16,
                  onChanged: (v) => setState(() => setSheetState(() => _adults = v)),
                ),
                const Divider(height: 24),
                _GuestStepper(
                  label: 'เด็ก',
                  value: _children,
                  min: 0,
                  max: 8,
                  onChanged: (v) => setState(() => setSheetState(() => _children = v)),
                ),
                const Divider(height: 24),
                _GuestStepper(
                  label: 'ห้องพัก',
                  value: _rooms,
                  min: 1,
                  max: 8,
                  onChanged: (v) => setState(() => setSheetState(() => _rooms = v)),
                ),
                const SizedBox(height: 20),
                ElevatedButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('เสร็จสิ้น')),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openFilterSheet() async {
    await showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('ตัวกรอง', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 12),
                Text('งบประมาณ (ต่อคืน): ${_priceRange.start.toInt()} - ${_priceRange.end.toInt()} THB', style: const TextStyle(fontSize: 13)),
                RangeSlider(
                  values: _priceRange,
                  min: 0,
                  max: _priceCeiling,
                  divisions: 20,
                  labels: RangeLabels('${_priceRange.start.toInt()}', '${_priceRange.end.toInt()}'),
                  onChanged: (v) => setState(() => setSheetState(() => _priceRange = v)),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('มีที่จอดรถฟรี'),
                  value: _filterFreeParking,
                  onChanged: (v) => setState(() => setSheetState(() => _filterFreeParking = v ?? false)),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('สระว่ายน้ำ'),
                  value: _filterPool,
                  onChanged: (v) => setState(() => setSheetState(() => _filterPool = v ?? false)),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('รวมอาหารเช้า'),
                  value: _filterBreakfast,
                  onChanged: (v) => setState(() => setSheetState(() => _filterBreakfast = v ?? false)),
                ),
                const SizedBox(height: 12),
                ElevatedButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('แสดงผลลัพธ์')),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _sortLabel(_SortOption o) {
    switch (o) {
      case _SortOption.popularity:
        return 'ยอดนิยม';
      case _SortOption.priceLowHigh:
        return 'ราคา: ต่ำ-สูง';
      case _SortOption.priceHighLow:
        return 'ราคา: สูง-ต่ำ';
      case _SortOption.ratingHigh:
        return 'คะแนนรีวิว';
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayed = _displayedHotels;
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
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.people_outline, size: 16),
                        label: Text(
                          '$_adults ผู้ใหญ่${_children > 0 ? ' · $_children เด็ก' : ''} · $_rooms ห้อง',
                          overflow: TextOverflow.ellipsis,
                        ),
                        onPressed: _openGuestPicker,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.search),
                        label: const Text('ค้นหา'),
                        onPressed: _loading ? null : _search,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (!_loading && _error == null && _hotels.isNotEmpty)
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.tune, size: 16),
                      label: const Text('ตัวกรอง'),
                      onPressed: _openFilterSheet,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: PopupMenuButton<_SortOption>(
                      initialValue: _sortOption,
                      onSelected: (v) => setState(() => _sortOption = v),
                      itemBuilder: (ctx) => _SortOption.values
                          .map((o) => PopupMenuItem(value: o, child: Text(_sortLabel(o))))
                          .toList(),
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.sort, size: 16),
                            const SizedBox(width: 6),
                            Expanded(child: Text(_sortLabel(_sortOption), overflow: TextOverflow.ellipsis)),
                          ],
                        ),
                      ),
                    ),
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
                        : displayed.isEmpty
                            ? const Center(child: Padding(padding: EdgeInsets.all(24), child: Text('ไม่มีที่พักตรงกับตัวกรอง ลองปรับตัวกรองดู', textAlign: TextAlign.center)))
                            : ListView.builder(
                                padding: const EdgeInsets.all(16),
                                itemCount: displayed.length,
                                itemBuilder: (ctx, i) {
                                  final h = displayed[i];
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

class _GuestStepper extends StatelessWidget {
  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;
  const _GuestStepper({required this.label, required this.value, required this.min, required this.max, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label, style: const TextStyle(fontSize: 15))),
        IconButton(
          icon: const Icon(Icons.remove_circle_outline),
          onPressed: value > min ? () => onChanged(value - 1) : null,
        ),
        SizedBox(width: 28, child: Text('$value', textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600))),
        IconButton(
          icon: const Icon(Icons.add_circle_outline),
          onPressed: value < max ? () => onChanged(value + 1) : null,
        ),
      ],
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
