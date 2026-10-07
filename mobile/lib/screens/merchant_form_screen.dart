import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart' as ll;
import '../models/merchant_models.dart';
import '../models/models.dart';
import '../services/api_client.dart';
import '../services/image_tools.dart';
import '../theme.dart';
import 'shop_location_picker_screen.dart';

class _ItemDraft {
  final name = TextEditingController();
  final price = TextEditingController();
  String? image;
  bool signature = false;
  void dispose() {
    name.dispose();
    price.dispose();
  }
}

class _PerkDraft {
  CardOption? card;
  final description = TextEditingController();
  bool noExpiry = true;
  DateTimeRange? range;
  void dispose() => description.dispose();
}

/// Register a partner shop (or fix one): identity and pictures, location, opening hours, contact, featured items and the
/// perks given to holders of chosen cards. The whole form is sent each time; an admin reviews it before it goes on the map.
class MerchantFormScreen extends StatefulWidget {
  /// The shop to edit; null for a new one.
  final String? merchantId;
  const MerchantFormScreen({super.key, this.merchantId});

  @override
  State<MerchantFormScreen> createState() => _MerchantFormScreenState();
}

class _MerchantFormScreenState extends State<MerchantFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameTh = TextEditingController();
  final _nameEn = TextEditingController();
  final _description = TextEditingController();
  final _address = TextEditingController();
  final _phone = TextEditingController();
  final _facebook = TextEditingController();
  final _instagram = TextEditingController();
  final _line = TextEditingController();

  String _category = 'CAFE';
  ll.LatLng? _point;
  String? _nearbyId;
  String? _cover;
  final List<String> _gallery = [];
  final List<_ItemDraft> _items = [];
  final List<_PerkDraft> _perks = [];
  Map<String, List<List<String>>> _hours = {for (final d in dayKeys) d: [['09:00', '18:00']]};

  List<TravelLocation> _locations = [];
  List<CardOption> _cards = [];
  String? _statusNote;
  bool _loading = true;
  bool _sending = false;
  String? _error;

  bool get _editing => widget.merchantId != null;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_nameTh, _nameEn, _description, _address, _phone, _facebook, _instagram, _line]) {
      c.dispose();
    }
    for (final i in _items) {
      i.dispose();
    }
    for (final p in _perks) {
      p.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final loc = await apiClient.get('/catalog/locations');
      final picker = await apiClient.get('/merchants/card-picker');
      _locations = (loc['locations'] as List).map((e) => TravelLocation.fromJson(e)).toList();
      _cards = (picker['cards'] as List).map((e) => CardOption.fromJson(e)).toList();
      if (_editing) {
        final data = await apiClient.get('/merchants/${widget.merchantId}/form');
        _fill(data['form'] as Map<String, dynamic>);
        if (data['has_pending_revision'] == true) {
          _statusNote = 'คุณมีการแก้ไขที่รอแอดมินตรวจ — ฟอร์มนี้แสดงเนื้อหาที่ขอแก้ล่าสุด ร้านบนแผนที่ยังเป็นเวอร์ชันเดิมจนกว่าจะอนุมัติ';
        } else if (data['revision_note'] != null) {
          _statusNote = 'การแก้ไขครั้งก่อนไม่ได้รับอนุมัติ: ${data['revision_note']}';
        } else if (data['reject_reason'] != null) {
          _statusNote = 'ร้านไม่ได้รับอนุมัติ: ${data['reject_reason']}';
        }
      }
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'โหลดข้อมูลไม่สำเร็จ: $e';
        });
      }
    }
  }

  void _fill(Map<String, dynamic> f) {
    _nameTh.text = f['shop_name_th'] ?? '';
    _nameEn.text = f['shop_name_en'] ?? '';
    _description.text = f['description'] ?? '';
    _address.text = f['address_detail'] ?? '';
    _phone.text = f['phone'] ?? '';
    _facebook.text = f['facebook'] ?? '';
    _instagram.text = f['instagram'] ?? '';
    _line.text = f['line'] ?? '';
    _category = f['category'] ?? 'CAFE';
    if (f['latitude'] != null && f['longitude'] != null) _point = ll.LatLng((f['latitude'] as num).toDouble(), (f['longitude'] as num).toDouble());
    _nearbyId = f['nearby_location_id'];
    _cover = f['cover_image'];
    _gallery
      ..clear()
      ..addAll((f['gallery'] as List).map((g) => g['image'] as String));
    _items.clear();
    for (final i in (f['items'] as List)) {
      final d = _ItemDraft()
        ..name.text = i['name'] ?? ''
        ..price.text = i['price'] == null ? '' : ((i['price'] as num) == (i['price'] as num).roundToDouble() ? '${(i['price'] as num).round()}' : '${i['price']}')
        ..image = i['image']
        ..signature = i['is_signature'] == true;
      _items.add(d);
    }
    _perks.clear();
    for (final p in (f['privileges'] as List)) {
      final d = _PerkDraft();
      for (final c in _cards) {
        if (c.templateId == p['template_id']) d.card = c;
      }
      d.description.text = p['description'] ?? '';
      if (p['start_date'] != null && p['end_date'] != null) {
        d.noExpiry = false;
        d.range = DateTimeRange(start: DateTime.parse(p['start_date']), end: DateTime.parse(p['end_date']));
      }
      _perks.add(d);
    }
    final h = f['opening_hours'] as Map<String, dynamic>? ?? {};
    _hours = {for (final d in dayKeys) d: ((h[d] as List?) ?? const []).map((r) => (r as List).map((x) => '$x').toList()).toList()};
  }

  // Pickers must start inside the tap handler (iOS Safari), so no await before calling them.
  Future<void> _pickCover() async {
    final url = await pickJpeg(maxSide: 900, maxChars: 150000);
    if (url != null && mounted) setState(() => _cover = url);
  }

  Future<void> _addGallery() async {
    final url = await pickJpeg(maxSide: 640, maxChars: 55000);
    if (url != null && mounted) setState(() => _gallery.add(url));
  }

  Future<void> _pickItemImage(_ItemDraft d) async {
    final url = await pickJpeg(maxSide: 480, maxChars: 55000);
    if (url != null && mounted) setState(() => d.image = url);
  }

  Future<void> _pickPoint() async {
    final p = await Navigator.of(context).push<ll.LatLng>(MaterialPageRoute(builder: (_) => ShopLocationPickerScreen(initial: _point)));
    if (p != null && mounted) setState(() => _point = p);
  }

  String _fmtDate(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  String _fmtTime(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  TimeOfDay _parseTime(String s) {
    final p = s.split(':');
    return TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
  }

  Future<void> _pickTime(String day, int index, int part) async {
    final range = _hours[day]![index];
    final t = await showTimePicker(context: context, initialTime: _parseTime(range[part]), builder: (c, w) => MediaQuery(data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true), child: w!));
    if (t != null && mounted) setState(() => range[part] = _fmtTime(t));
  }

  Future<void> _pickRange(_PerkDraft d) async {
    final now = DateTime.now();
    final r = await showDateRangePicker(context: context, firstDate: DateTime(now.year, now.month, now.day), lastDate: DateTime(now.year + 3), initialDateRange: d.range);
    if (r != null) setState(() => d.range = r);
  }

  Future<void> _chooseCard(_PerkDraft d) async {
    final taken = _perks.where((p) => p != d && p.card != null).map((p) => p.card!.templateId).toSet();
    final available = _cards.where((c) => !taken.contains(c.templateId)).toList();
    final picked = await showModalBottomSheet<CardOption>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        var query = '';
        return StatefulBuilder(builder: (ctx, setSheet) {
          final shown = available.where((c) => c.name.toLowerCase().contains(query.toLowerCase()) || (c.locationName ?? '').toLowerCase().contains(query.toLowerCase())).toList();
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.of(ctx).size.height * 0.7,
              child: Column(children: [
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: TextField(decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'ค้นหาการ์ดหรือสถานที่'), onChanged: (v) => setSheet(() => query = v)),
                ),
                Expanded(
                  child: shown.isEmpty
                      ? const Center(child: Text('ไม่พบการ์ด', style: TextStyle(color: Colors.grey)))
                      : ListView(
                          children: shown
                              .map((c) => ListTile(
                                    leading: const Icon(Icons.style, color: AppColors.navy),
                                    title: Text(c.name),
                                    subtitle: Text([normalizeRarity(c.rarity), if (c.locationName != null) c.locationName!].join(' · ')),
                                    onTap: () => Navigator.of(ctx).pop(c),
                                  ))
                              .toList(),
                        ),
                ),
              ]),
            ),
          );
        });
      },
    );
    if (picked != null && mounted) setState(() => d.card = picked);
  }

  Map<String, dynamic>? _body() {
    if (_point == null) {
      setState(() => _error = 'ปักหมุดตำแหน่งร้านบนแผนที่');
      return null;
    }
    if (_cover == null) {
      setState(() => _error = 'เพิ่มภาพปกร้าน');
      return null;
    }
    for (final i in _items) {
      if (i.image == null) {
        setState(() => _error = 'ทุกเมนู/สินค้าแนะนำต้องมีรูปภาพ');
        return null;
      }
    }
    for (final p in _perks) {
      if (p.card == null) {
        setState(() => _error = 'เลือกการ์ดให้ครบทุกสิทธิประโยชน์ (หรือลบรายการที่ไม่ใช้)');
        return null;
      }
      if (!p.noExpiry && p.range == null) {
        setState(() => _error = 'เลือกช่วงวันของโปรโมชัน หรือเลือก "ไม่มีวันหมดอายุ"');
        return null;
      }
    }
    return {
      'shop_name_th': _nameTh.text.trim(),
      'shop_name_en': _nameEn.text.trim(),
      'category': _category,
      'description': _description.text.trim(),
      'address_detail': _address.text.trim(),
      'latitude': _point!.latitude,
      'longitude': _point!.longitude,
      'nearby_location_id': _nearbyId,
      'opening_hours': _hours,
      'phone': _phone.text.trim(),
      'facebook': _facebook.text.trim(),
      'instagram': _instagram.text.trim(),
      'line': _line.text.trim(),
      'cover_image': _cover,
      'gallery': _gallery.map((g) => {'image': g}).toList(),
      'items': _items.map((i) => {'name': i.name.text.trim(), 'price': i.price.text.trim().isEmpty ? null : double.tryParse(i.price.text.trim()), 'image': i.image, 'is_signature': i.signature}).toList(),
      'privileges': _perks
          .map((p) => {
                'template_id': p.card!.templateId,
                'description': p.description.text.trim(),
                'start_date': p.noExpiry ? null : _fmtDate(p.range!.start),
                'end_date': p.noExpiry ? null : _fmtDate(p.range!.end),
              })
          .toList(),
    };
  }

  Future<void> _submit() async {
    setState(() => _error = null);
    if (!_formKey.currentState!.validate()) return;
    final body = _body();
    if (body == null) return;
    setState(() => _sending = true);
    try {
      final res = _editing ? await apiClient.put('/merchants/${widget.merchantId}', body) : await apiClient.post('/merchants', body);
      if (!mounted) return;
      final live = res['revision_pending'] == true;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.hourglass_top, color: AppColors.navy, size: 36),
          title: const Text('ส่งให้แอดมินตรวจสอบแล้ว'),
          content: Text(live
              ? 'ร้านของคุณยังแสดงบนแผนที่ตามเดิม เมื่อแอดมินอนุมัติการแก้ไข ข้อมูลใหม่จะแทนที่ทันที และคุณจะได้รับการแจ้งเตือน'
              : 'เมื่อแอดมินอนุมัติ หมุดร้านจะขึ้นบนแผนที่ และคุณจะได้รับการแจ้งเตือน'),
          actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('ตกลง'))],
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'ส่งไม่สำเร็จ: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Widget _section(String text, {String? hint}) => Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.navy)),
          if (hint != null) Text(hint, style: const TextStyle(color: Colors.grey, fontSize: 12)),
        ]),
      );

  Widget _picture({required String? dataUrl, required double aspect, required String label, required VoidCallback onTap, VoidCallback? onRemove}) {
    Uint8List? bytes;
    if (dataUrl != null) bytes = decodeDataUrl(dataUrl);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: AspectRatio(
        aspectRatio: aspect,
        child: Container(
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFDDE2EA))),
          clipBehavior: Clip.antiAlias,
          child: bytes == null
              ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.add_photo_alternate_outlined, size: 30, color: AppColors.navy),
                  const SizedBox(height: 4),
                  Text(label, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey, fontSize: 12)),
                ])
              : Stack(fit: StackFit.expand, children: [
                  Image.memory(bytes, fit: BoxFit.cover),
                  if (onRemove != null)
                    Positioned(
                      right: 4,
                      top: 4,
                      child: GestureDetector(onTap: onRemove, child: const CircleAvatar(radius: 12, backgroundColor: Colors.black54, child: Icon(Icons.close, size: 14, color: Colors.white))),
                    ),
                ]),
        ),
      ),
    );
  }

  Widget _hoursEditor() {
    return Column(children: [
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          icon: const Icon(Icons.copy_all, size: 18),
          label: const Text('ใช้เวลาของวันจันทร์กับทุกวัน'),
          onPressed: () => setState(() {
            final src = _hours['mon']!;
            for (final d in dayKeys) {
              _hours[d] = src.map((r) => [...r]).toList();
            }
          }),
        ),
      ),
      for (final day in dayKeys)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 78, child: Padding(padding: const EdgeInsets.only(top: 12), child: Text(dayNames[day]!, style: const TextStyle(fontWeight: FontWeight.w600)))),
            Expanded(
              child: _hours[day]!.isEmpty
                  ? Row(children: [
                      const Text('ปิดทำการ', style: TextStyle(color: Colors.grey)),
                      const Spacer(),
                      TextButton(onPressed: () => setState(() => _hours[day]!.add(['09:00', '18:00'])), child: const Text('เปิดวันนี้')),
                    ])
                  : Column(children: [
                      for (var i = 0; i < _hours[day]!.length; i++)
                        Row(children: [
                          OutlinedButton(onPressed: () => _pickTime(day, i, 0), child: Text(_hours[day]![i][0])),
                          const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Text('-')),
                          OutlinedButton(onPressed: () => _pickTime(day, i, 1), child: Text(_hours[day]![i][1])),
                          IconButton(icon: const Icon(Icons.close, size: 18), tooltip: 'ลบช่วงเวลา', onPressed: () => setState(() => _hours[day]!.removeAt(i))),
                        ]),
                      if (_hours[day]!.length < 3)
                        Align(alignment: Alignment.centerLeft, child: TextButton(onPressed: () => setState(() => _hours[day]!.add(['13:00', '18:00'])), child: const Text('+ เพิ่มช่วงเวลา'))),
                    ]),
            ),
          ]),
        ),
      const Align(alignment: Alignment.centerLeft, child: Text('ร้านที่เปิดข้ามเที่ยงคืน เช่น 18:00 - 02:00 ใส่เวลาปิดเป็น 02:00 ได้', style: TextStyle(color: Colors.grey, fontSize: 12))),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_editing ? 'แก้ไขร้านค้า' : 'ลงทะเบียนร้านค้าพันธมิตร')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  if (_statusNote != null)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: Colors.orange.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                      child: Text(_statusNote!),
                    ),
                  _section('ส่วนที่ 1: ข้อมูลร้านและรูปภาพ'),
                  TextFormField(controller: _nameTh, maxLength: 80, decoration: const InputDecoration(labelText: 'ชื่อร้าน (ภาษาไทย)'), validator: (v) => (v == null || v.trim().isEmpty) ? 'กรอกชื่อร้านภาษาไทย' : null),
                  TextFormField(controller: _nameEn, maxLength: 80, decoration: const InputDecoration(labelText: 'ชื่อร้าน (English)'), validator: (v) => (v == null || v.trim().isEmpty) ? 'กรอกชื่อร้านภาษาอังกฤษ' : null),
                  const SizedBox(height: 8),
                  const Text('หมวดหมู่', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: shopCategories
                        .map((c) => ChoiceChip(avatar: Icon(c.icon, size: 18, color: _category == c.id ? Colors.white : c.color), label: Text(c.label), selected: _category == c.id, selectedColor: c.color, labelStyle: TextStyle(color: _category == c.id ? Colors.white : null), onSelected: (_) => setState(() => _category = c.id)))
                        .toList(),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(controller: _description, maxLines: 4, maxLength: 1000, decoration: const InputDecoration(labelText: 'คำอธิบายร้าน'), validator: (v) => (v == null || v.trim().isEmpty) ? 'กรอกคำอธิบายร้าน' : null),
                  const SizedBox(height: 6),
                  const Text('ภาพปกร้าน (1 ภาพ)', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  _picture(dataUrl: _cover, aspect: 16 / 9, label: 'แตะเพื่อเลือกภาพปก (แนวนอน)', onTap: _pickCover),
                  const SizedBox(height: 14),
                  Text('ภาพบรรยากาศร้าน (${_gallery.length}/5)', style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, runSpacing: 8, children: [
                    for (var i = 0; i < _gallery.length; i++) SizedBox(width: 104, child: _picture(dataUrl: _gallery[i], aspect: 1, label: '', onTap: () {}, onRemove: () => setState(() => _gallery.removeAt(i)))),
                    if (_gallery.length < 5) SizedBox(width: 104, child: _picture(dataUrl: null, aspect: 1, label: 'เพิ่มภาพ', onTap: _addGallery)),
                  ]),
                  _section('ส่วนที่ 2: ที่ตั้งและเวลาเปิด-ปิด'),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.place),
                    label: Text(_point == null ? 'ปักหมุดตำแหน่งร้านบนแผนที่' : 'พิกัด ${_point!.latitude.toStringAsFixed(5)}, ${_point!.longitude.toStringAsFixed(5)} (แตะเพื่อแก้ไข)'),
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    onPressed: _pickPoint,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(controller: _address, maxLines: 2, maxLength: 300, decoration: const InputDecoration(labelText: 'ที่อยู่ร้าน'), validator: (v) => (v == null || v.trim().isEmpty) ? 'กรอกที่อยู่ร้าน' : null),
                  DropdownButtonFormField<String?>(
                    initialValue: _nearbyId,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'สถานที่ท่องเที่ยวใกล้เคียง (ไม่บังคับ)'),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('ไม่ระบุ')),
                      ..._locations.map((l) => DropdownMenuItem<String?>(value: l.locationId, child: Text('${l.name} (${l.province})', overflow: TextOverflow.ellipsis))),
                    ],
                    onChanged: (v) => setState(() => _nearbyId = v),
                  ),
                  const SizedBox(height: 14),
                  const Text('เวลาเปิด-ปิด', style: TextStyle(fontWeight: FontWeight.w600)),
                  _hoursEditor(),
                  _section('ส่วนที่ 3: ช่องทางติดต่อ'),
                  TextFormField(controller: _phone, keyboardType: TextInputType.phone, decoration: const InputDecoration(labelText: 'เบอร์โทรศัพท์'), validator: (v) => (v == null || v.trim().length < 6) ? 'กรอกเบอร์โทรศัพท์' : null),
                  TextFormField(controller: _facebook, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Facebook (ลิงก์ https://... ไม่บังคับ)')),
                  TextFormField(controller: _instagram, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Instagram (ลิงก์ https://... ไม่บังคับ)')),
                  TextFormField(controller: _line, decoration: const InputDecoration(labelText: 'LINE (@ไอดี หรือลิงก์ ไม่บังคับ)')),
                  _section('ส่วนที่ 4: เมนู / สินค้าแนะนำ', hint: 'ไม่บังคับ ใส่ได้สูงสุด 8 รายการ'),
                  for (var n = 0; n < _items.length; n++) _itemCard(n),
                  if (_items.length < 8)
                    OutlinedButton.icon(icon: const Icon(Icons.add), label: const Text('เพิ่มเมนู/สินค้า'), onPressed: () => setState(() => _items.add(_ItemDraft()))),
                  _section('ส่วนที่ 5: สิทธิประโยชน์สำหรับผู้ถือการ์ด', hint: 'ไม่บังคับ ผู้ถือการ์ดที่เลือกแสดงการ์ดที่ร้านเพื่อรับสิทธิ (ไม่ต้องสแกน)'),
                  for (var n = 0; n < _perks.length; n++) _perkCard(n),
                  if (_perks.length < 5)
                    OutlinedButton.icon(icon: const Icon(Icons.card_giftcard), label: const Text('เพิ่มสิทธิประโยชน์'), onPressed: () => setState(() => _perks.add(_PerkDraft()))),
                  if (_error != null) ...[const SizedBox(height: 14), Text(_error!, style: const TextStyle(color: Colors.red))],
                  const SizedBox(height: 22),
                  ElevatedButton(
                    onPressed: _sending ? null : _submit,
                    child: _sending ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text(_editing ? 'บันทึกและส่งให้แอดมินตรวจสอบ' : 'ส่งให้แอดมินตรวจสอบ'),
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
    );
  }

  Widget _itemCard(int n) {
    final d = _items[n];
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(width: 84, child: _picture(dataUrl: d.image, aspect: 1, label: 'รูป', onTap: () => _pickItemImage(d))),
          const SizedBox(width: 10),
          Expanded(
            child: Column(children: [
              TextFormField(controller: d.name, maxLength: 80, decoration: const InputDecoration(labelText: 'ชื่อ', counterText: ''), validator: (v) => (v == null || v.trim().isEmpty) ? 'กรอกชื่อ' : null),
              TextFormField(
                controller: d.price,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'ราคา (บาท)'),
                validator: (v) => (v == null || v.trim().isEmpty || double.tryParse(v.trim()) != null) ? null : 'ใส่ตัวเลข',
              ),
              Row(children: [
                Checkbox(value: d.signature, onChanged: (v) => setState(() => d.signature = v == true)),
                const Expanded(child: Text('เมนู/สินค้าซิกเนเจอร์ ★', style: TextStyle(fontSize: 13))),
                IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: () => setState(() {
                    _items.removeAt(n).dispose();
                  }),
                ),
              ]),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _perkCard(int n) {
    final d = _perks[n];
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          OutlinedButton.icon(
            icon: const Icon(Icons.style),
            label: Text(d.card == null ? 'เลือกการ์ด' : d.card!.name, overflow: TextOverflow.ellipsis),
            style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
            onPressed: () => _chooseCard(d),
          ),
          TextFormField(
            controller: d.description,
            maxLines: 2,
            maxLength: 300,
            decoration: const InputDecoration(labelText: 'สิทธิประโยชน์ เช่น ลด 10% เมื่อแสดงการ์ด'),
            validator: (v) => (v == null || v.trim().isEmpty) ? 'กรอกรายละเอียดสิทธิประโยชน์' : null,
          ),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('ไม่มีวันหมดอายุ'), value: d.noExpiry, onChanged: (v) => setState(() => d.noExpiry = v)),
          if (!d.noExpiry)
            OutlinedButton.icon(
              icon: const Icon(Icons.date_range),
              label: Text(d.range == null ? 'เลือกวันเริ่มต้น - สิ้นสุด' : '${_fmtDate(d.range!.start)}  ถึง  ${_fmtDate(d.range!.end)}'),
              onPressed: () => _pickRange(d),
            ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              icon: const Icon(Icons.delete_outline, color: Colors.red),
              label: const Text('ลบสิทธิประโยชน์นี้', style: TextStyle(color: Colors.red)),
              onPressed: () => setState(() {
                _perks.removeAt(n).dispose();
              }),
            ),
          ),
        ]),
      ),
    );
  }
}
