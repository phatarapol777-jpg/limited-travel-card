import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/api_client.dart';
import '../theme.dart';

String _ymd(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
String _hm(String iso) => iso.length >= 16 ? iso.substring(11, 16) : iso;
String _thaiDate(DateTime d) => '${d.day}/${d.month}/${d.year + 543}';
String _duration(int? min) => min == null ? '' : '${min ~/ 60} ชม. ${min % 60} น.';
String _baht(num v) {
  final s = v.round().toString();
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write(',');
    b.write(s[i]);
  }
  return '฿${b.toString()}';
}

Future<void> _sendRequest(BuildContext context, {required String kind, required String title, required num? price, required Map<String, dynamic> summary}) async {
  try {
    await apiClient.post('/booking/transport/request', {'kind': kind, 'title': title, 'price': price, 'currency': 'THB', 'summary': summary});
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.check_circle, color: AppColors.success, size: 36),
        title: const Text('ส่งคำขอจองแล้ว'),
        content: const Text('บันทึกคำขอของคุณแล้ว ทีมงานจะติดต่อกลับเพื่อยืนยันการจอง'),
        actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('ตกลง'))],
      ),
    );
  } on ApiException catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
  }
}

Widget _field(String label, String value, IconData icon, VoidCallback onTap) => InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon, size: 20)),
        child: Text(value, overflow: TextOverflow.ellipsis),
      ),
    );

// ================================================================= flights ===================================================

class _Airport {
  final String code;
  final String name;
  final String? city;
  const _Airport(this.code, this.name, [this.city]);
  String get label => city == null || city == name ? (name.contains('(') ? name : '$name ($code)') : '$city · $name';
}

const _quickDestinations = [
  _Airport('CNX.AIRPORT', 'เชียงใหม่ (CNX)'),
  _Airport('HKT.AIRPORT', 'ภูเก็ต (HKT)'),
  _Airport('KBV.AIRPORT', 'กระบี่ (KBV)'),
  _Airport('CEI.AIRPORT', 'เชียงราย (CEI)'),
  _Airport('USM.AIRPORT', 'เกาะสมุย (USM)'),
  _Airport('HDY.AIRPORT', 'หาดใหญ่ (HDY)'),
  _Airport('KKC.AIRPORT', 'ขอนแก่น (KKC)'),
  _Airport('UTH.AIRPORT', 'อุดรธานี (UTH)'),
];

/// Search real flights (from the Booking.com data), look at the details and send a booking request.
class FlightsScreen extends StatefulWidget {
  const FlightsScreen({super.key});

  @override
  State<FlightsScreen> createState() => _FlightsScreenState();
}

class _FlightsScreenState extends State<FlightsScreen> {
  _Airport _from = const _Airport('BKK.CITY', 'กรุงเทพฯ (ทุกสนามบิน)');
  _Airport? _to;
  late DateTime _date;
  DateTime? _return;
  int _adults = 1;
  String _cabin = 'ECONOMY';
  String _order = 'BEST';
  bool _loading = false;
  bool _searched = false;
  String? _error;
  int _total = 0;
  List<Map<String, dynamic>> _offers = [];

  static const _cabins = {'ECONOMY': 'ชั้นประหยัด', 'PREMIUM_ECONOMY': 'ประหยัดพิเศษ', 'BUSINESS': 'ชั้นธุรกิจ', 'FIRST': 'ชั้นหนึ่ง'};
  static const _orders = {'BEST': 'แนะนำ', 'CHEAPEST': 'ถูกที่สุด', 'FASTEST': 'เร็วที่สุด'};

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _date = DateTime(now.year, now.month, now.day).add(const Duration(days: 14));
  }

  Future<void> _pickAirport(bool isFrom) async {
    final picked = await showModalBottomSheet<_Airport>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _AirportPicker(showQuick: !isFrom),
    );
    if (picked != null) setState(() => isFrom ? _from = picked : _to = picked);
  }

  Future<void> _pickDate(bool isReturn) async {
    final first = isReturn ? _date : DateTime.now();
    final picked = await showDatePicker(context: context, initialDate: isReturn ? (_return ?? _date) : _date, firstDate: first, lastDate: DateTime.now().add(const Duration(days: 364)));
    if (picked == null) return;
    setState(() {
      if (isReturn) {
        _return = picked;
      } else {
        _date = picked;
        if (_return != null && _return!.isBefore(_date)) _return = _date;
      }
    });
  }

  Future<void> _search() async {
    if (_to == null) return setState(() => _error = 'เลือกปลายทาง');
    if (_from.code == _to!.code) return setState(() => _error = 'ต้นทางและปลายทางต้องไม่ใช่ที่เดียวกัน');
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final q = 'from=${Uri.encodeQueryComponent(_from.code)}&to=${Uri.encodeQueryComponent(_to!.code)}&date=${_ymd(_date)}&adults=$_adults&cabin=$_cabin&order=$_order${_return == null ? '' : '&return_date=${_ymd(_return!)}'}';
      final data = await apiClient.get('/booking/flights?$q');
      if (!mounted) return;
      setState(() {
        _offers = (data['offers'] as List).map((e) => e as Map<String, dynamic>).toList();
        _total = (data['total'] as num?)?.toInt() ?? _offers.length;
        _loading = false;
        _searched = true;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.message; });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = 'เชื่อมต่อไม่สำเร็จ: $e'; });
    }
  }

  void _details(Map<String, dynamic> offer) {
    final segs = (offer['segments'] as List).map((e) => e as Map<String, dynamic>).toList();
    final title = '${_from.code.split('.').first} → ${_to!.code.split('.').first} ${_ymd(_date)}${_return == null ? '' : ' / ${_ymd(_return!)}'}';
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        maxChildSize: 0.95,
        expand: false,
        builder: (ctx, controller) => ListView(controller: controller, padding: const EdgeInsets.all(20), children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
          const SizedBox(height: 4),
          Text('${_baht(offer['price'] as num)} · ผู้โดยสาร $_adults คน · ${_cabins[_cabin]}', style: const TextStyle(color: AppColors.navy, fontWeight: FontWeight.w600)),
          for (var i = 0; i < segs.length; i++) ...[
            const Divider(height: 28),
            Text(segs.length > 1 ? (i == 0 ? 'ขาไป' : 'ขากลับ') : 'เที่ยวบิน', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            _segmentDetail(segs[i]),
          ],
          const SizedBox(height: 18),
          ElevatedButton.icon(
            icon: const Icon(Icons.send),
            label: const Text('ขอจองเที่ยวบินนี้'),
            onPressed: () async {
              Navigator.of(ctx).pop();
              await _sendRequest(context, kind: 'flight', title: title, price: offer['price'] as num, summary: {'adults': _adults, 'cabin': _cabin, 'segments': segs});
            },
          ),
          const SizedBox(height: 8),
          const Text('ราคาและที่นั่งเป็นข้อมูลจากผู้ให้บริการ ณ ตอนค้นหา อาจเปลี่ยนแปลงเมื่อยืนยันการจอง', style: TextStyle(color: Colors.grey, fontSize: 12)),
        ]),
      ),
    );
  }

  Widget _segmentDetail(Map<String, dynamic> s) {
    final from = s['from'] as Map<String, dynamic>;
    final to = s['to'] as Map<String, dynamic>;
    final flights = (s['flights'] as List).map((e) => e as Map<String, dynamic>).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('${_hm('${s['departure']}')} ${from['city'] ?? from['code']} (${from['code']}) → ${_hm('${s['arrival']}')} ${to['city'] ?? to['code']} (${to['code']})', style: const TextStyle(fontWeight: FontWeight.w600)),
      Text('${'${s['departure']}'.substring(0, 10)} · ใช้เวลา ${_duration((s['duration_min'] as num?)?.toInt())} · ${(s['stops'] as num) == 0 ? 'บินตรง' : 'แวะพัก ${s['stops']} ครั้ง'}', style: const TextStyle(color: Colors.grey)),
      const SizedBox(height: 6),
      for (final f in flights) Text('${f['number']}  ${f['from']} ${_hm('${f['departure']}')} → ${f['to']} ${_hm('${f['arrival']}')}', style: const TextStyle(fontSize: 13)),
      const SizedBox(height: 6),
      Text(s['checked_bag_kg'] != null ? 'สัมภาระโหลดใต้ท้องเครื่อง ${s['checked_bag_pieces']} ชิ้น (${s['checked_bag_kg']} กก.)' : 'ไม่รวมสัมภาระโหลดใต้ท้องเครื่อง', style: const TextStyle(fontSize: 12, color: Colors.grey)),
    ]);
  }

  Widget _offerCard(Map<String, dynamic> offer) {
    final segs = (offer['segments'] as List).map((e) => e as Map<String, dynamic>).toList();
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: () => _details(offer),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Expanded(
              child: Column(children: [
                for (final s in segs) _segmentRow(s),
              ]),
            ),
            const SizedBox(width: 10),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(_baht(offer['price'] as num), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.navy)),
              const Text('รวมภาษี', style: TextStyle(fontSize: 11, color: Colors.grey)),
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _segmentRow(Map<String, dynamic> s) {
    final carriers = (s['carriers'] as List).map((e) => e as Map<String, dynamic>).toList();
    final from = s['from'] as Map<String, dynamic>;
    final to = s['to'] as Map<String, dynamic>;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        SizedBox(
          width: 34,
          child: carriers.isNotEmpty && carriers.first['logo'] != null
              ? Image.network('${carriers.first['logo']}', height: 28, errorBuilder: (_, __, ___) => const Icon(Icons.flight, color: AppColors.navy))
              : const Icon(Icons.flight, color: AppColors.navy),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${_hm('${s['departure']}')} ${from['code']} → ${_hm('${s['arrival']}')} ${to['code']}', style: const TextStyle(fontWeight: FontWeight.w600)),
            Text('${carriers.map((c) => c['name']).join(', ')} · ${_duration((s['duration_min'] as num?)?.toInt())} · ${(s['stops'] as num) == 0 ? 'บินตรง' : 'แวะ ${s['stops']}'}', style: const TextStyle(fontSize: 12, color: Colors.grey), overflow: TextOverflow.ellipsis),
          ]),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('จองเที่ยวบิน')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        _field('ต้นทาง', _from.label, Icons.flight_takeoff, () => _pickAirport(true)),
        const SizedBox(height: 10),
        _field('ปลายทาง', _to?.label ?? 'เลือกปลายทาง', Icons.flight_land, () => _pickAirport(false)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _field('วันไป', _thaiDate(_date), Icons.event, () => _pickDate(false))),
          const SizedBox(width: 10),
          Expanded(
            child: _return == null
                ? OutlinedButton.icon(style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(56)), icon: const Icon(Icons.add), label: const Text('เพิ่มวันกลับ'), onPressed: () => _pickDate(true))
                : Stack(children: [
                    _field('วันกลับ', _thaiDate(_return!), Icons.event_repeat, () => _pickDate(true)),
                    Positioned(right: 0, top: 0, child: IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => setState(() => _return = null))),
                  ]),
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: DropdownButtonFormField<int>(
              initialValue: _adults,
              decoration: const InputDecoration(labelText: 'ผู้โดยสาร'),
              items: [for (var i = 1; i <= 9; i++) DropdownMenuItem(value: i, child: Text('$i คน'))],
              onChanged: (v) => setState(() => _adults = v ?? 1),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: _cabin,
              decoration: const InputDecoration(labelText: 'ชั้นโดยสาร'),
              isExpanded: true,
              items: _cabins.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis))).toList(),
              onChanged: (v) => setState(() => _cabin = v ?? 'ECONOMY'),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        ElevatedButton.icon(icon: _loading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.search), label: const Text('ค้นหาเที่ยวบิน'), onPressed: _loading ? null : _search),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: Colors.red))),
        if (_searched) ...[
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: Text(_offers.isEmpty ? 'ไม่พบเที่ยวบิน' : 'พบ $_total เที่ยวบิน (แสดง ${_offers.length} รายการ)', style: const TextStyle(fontWeight: FontWeight.bold))),
          ]),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: _orders.entries.map((e) => ChoiceChip(label: Text(e.value), selected: _order == e.key, onSelected: (_) { setState(() => _order = e.key); _search(); })).toList()),
          const SizedBox(height: 10),
          ..._offers.map(_offerCard),
        ],
      ]),
    );
  }
}

class _AirportPicker extends StatefulWidget {
  final bool showQuick;
  const _AirportPicker({required this.showQuick});

  @override
  State<_AirportPicker> createState() => _AirportPickerState();
}

class _AirportPickerState extends State<_AirportPicker> {
  final _ctrl = TextEditingController();
  List<_Airport> _results = [];
  bool _searching = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _search(String q) async {
    final text = q.trim();
    if (text.length < 2) return setState(() => _results = []);
    setState(() => _searching = true);
    try {
      final data = await apiClient.get('/booking/airports?q=${Uri.encodeQueryComponent(text)}');
      if (!mounted || _ctrl.text.trim() != text) return;
      setState(() {
        _results = (data['airports'] as List).map((e) => _Airport(e['code'], e['name'], e['city'])).toList();
        _error = null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: TextField(controller: _ctrl, decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: 'ค้นหาเมืองหรือสนามบิน เช่น Bangkok, Phuket', suffixIcon: _searching ? const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))) : null), onChanged: _search),
            ),
            if (_error != null) Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Text(_error!, style: const TextStyle(color: Colors.red))),
            Expanded(
              child: ListView(children: [
                if (_results.isEmpty && widget.showQuick && _ctrl.text.trim().length < 2) ...[
                  const Padding(padding: EdgeInsets.fromLTRB(16, 0, 16, 6), child: Text('ปลายทางยอดนิยม', style: TextStyle(fontWeight: FontWeight.bold))),
                  ..._quickDestinations.map((a) => ListTile(leading: const Icon(Icons.flight_land, color: AppColors.navy), title: Text(a.name), onTap: () => Navigator.of(context).pop(a))),
                ],
                ..._results.map((a) => ListTile(leading: Icon(a.code.endsWith('CITY') ? Icons.location_city : Icons.flight, color: AppColors.navy), title: Text(a.label), subtitle: Text(a.code), onTap: () => Navigator.of(context).pop(a))),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

// ================================================================= rental cars ===============================================

/// Search real rental cars around a place (from the Booking.com data) and send a booking request.
class CarsScreen extends StatefulWidget {
  final TravelLocation? location;
  const CarsScreen({super.key, this.location});

  @override
  State<CarsScreen> createState() => _CarsScreenState();
}

class _CarsScreenState extends State<CarsScreen> {
  List<TravelLocation> _locations = [];
  TravelLocation? _location;
  late DateTime _pickUp;
  late DateTime _dropOff;
  String _sort = 'price_low_to_high';
  bool _loading = false;
  bool _searched = false;
  String? _error;
  List<Map<String, dynamic>> _cars = [];

  static const _sorts = {'price_low_to_high': 'ราคาต่ำสุด', 'recommended': 'แนะนำ', 'review_score': 'คะแนนรีวิว'};

  @override
  void initState() {
    super.initState();
    _location = widget.location;
    final now = DateTime.now();
    _pickUp = DateTime(now.year, now.month, now.day).add(const Duration(days: 14));
    _dropOff = _pickUp.add(const Duration(days: 2));
    apiClient.get('/catalog/locations').then((d) {
      if (mounted) setState(() => _locations = (d['locations'] as List).map((e) => TravelLocation.fromJson(e)).toList());
    }).catchError((_) {});
    if (_location != null) WidgetsBinding.instance.addPostFrameCallback((_) => _search());
  }

  Future<void> _pickDate(bool isPickUp) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isPickUp ? _pickUp : _dropOff,
      firstDate: isPickUp ? DateTime.now() : _pickUp.add(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 364)),
    );
    if (picked == null) return;
    setState(() {
      if (isPickUp) {
        _pickUp = picked;
        if (!_dropOff.isAfter(_pickUp)) _dropOff = _pickUp.add(const Duration(days: 1));
      } else {
        _dropOff = picked;
      }
    });
  }

  Future<void> _search() async {
    if (_location == null) return setState(() => _error = 'เลือกสถานที่รับรถ');
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await apiClient.get('/booking/cars?location_id=${Uri.encodeQueryComponent(_location!.locationId)}&pick_up=${_ymd(_pickUp)}&drop_off=${_ymd(_dropOff)}&sort=$_sort');
      if (!mounted) return;
      setState(() {
        _cars = (data['cars'] as List).map((e) => e as Map<String, dynamic>).toList();
        _loading = false;
        _searched = true;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() { _loading = false; _error = e.message; });
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = 'เชื่อมต่อไม่สำเร็จ: $e'; });
    }
  }

  Future<void> _request(Map<String, dynamic> car) async {
    await _sendRequest(context,
        kind: 'car',
        title: '${car['title']} · ${_location!.name} ${_ymd(_pickUp)} ถึง ${_ymd(_dropOff)}',
        price: car['price'] as num?,
        summary: {'car': car, 'place': _location!.name, 'pick_up': _ymd(_pickUp), 'drop_off': _ymd(_dropOff)});
  }

  Widget _carCard(Map<String, dynamic> car) {
    final specs = (car['specs'] as List).map((e) => '$e').toList();
    final badges = (car['badges'] as List).map((e) => '$e').toList();
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 110,
              height: 70,
              child: car['image'] != null ? Image.network('${car['image']}', fit: BoxFit.contain, errorBuilder: (_, __, ___) => const Icon(Icons.directions_car, size: 40, color: AppColors.navy)) : const Icon(Icons.directions_car, size: 40, color: AppColors.navy),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${car['title']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                if (car['subtitle'] != null) Text('${car['subtitle']}', style: const TextStyle(color: Colors.grey, fontSize: 12)),
                const SizedBox(height: 4),
                Text(specs.join(' · '), style: const TextStyle(fontSize: 12)),
              ]),
            ),
          ]),
          const SizedBox(height: 8),
          if (car['pickup'] != null) Row(children: [const Icon(Icons.place, size: 16, color: Colors.redAccent), const SizedBox(width: 4), Expanded(child: Text('${car['pickup']}', style: const TextStyle(fontSize: 12)))]),
          if (car['supplier'] != null) Padding(padding: const EdgeInsets.only(top: 2), child: Text('${car['supplier']}${car['supplier_rating'] != null ? ' · ${car['supplier_rating']}' : ''}', style: const TextStyle(fontSize: 12, color: Colors.grey))),
          if (badges.isNotEmpty || car['special_offer'] != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text([...badges, if (car['special_offer'] != null) '${car['special_offer']}'].join(' · '), style: const TextStyle(fontSize: 12, color: AppColors.success))),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: Text('${car['price_text'] ?? ''}  ${car['duration_text'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.navy))),
            ElevatedButton(style: ElevatedButton.styleFrom(minimumSize: const Size(0, 38)), onPressed: () => _request(car), child: const Text('ขอจอง')),
          ]),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('เช่ารถ')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        DropdownButtonFormField<String>(
          initialValue: _location?.locationId,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'รับ-คืนรถใกล้สถานที่', prefixIcon: Icon(Icons.place, size: 20)),
          items: _locations.map((l) => DropdownMenuItem(value: l.locationId, child: Text('${l.name} (${l.province})', overflow: TextOverflow.ellipsis))).toList(),
          onChanged: (v) => setState(() => _location = _locations.firstWhere((l) => l.locationId == v)),
        ),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _field('วันรับรถ', _thaiDate(_pickUp), Icons.event, () => _pickDate(true))),
          const SizedBox(width: 10),
          Expanded(child: _field('วันคืนรถ', _thaiDate(_dropOff), Icons.event_available, () => _pickDate(false))),
        ]),
        const SizedBox(height: 12),
        ElevatedButton.icon(icon: _loading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.search), label: const Text('ค้นหารถเช่า'), onPressed: _loading ? null : _search),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: Colors.red))),
        if (_searched) ...[
          const SizedBox(height: 16),
          Text(_cars.isEmpty ? 'ไม่พบรถเช่าในช่วงวันที่นี้' : 'พบ ${_cars.length} คัน', style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: _sorts.entries.map((e) => ChoiceChip(label: Text(e.value), selected: _sort == e.key, onSelected: (_) { setState(() => _sort = e.key); _search(); })).toList()),
          const SizedBox(height: 10),
          ..._cars.map(_carCard),
        ],
      ]),
    );
  }
}
