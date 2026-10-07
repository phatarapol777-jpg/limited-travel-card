import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../models/collection_models.dart';
import '../models/models.dart';
import '../services/api_client.dart';
import '../services/image_tools.dart';
import '../theme.dart';

/// Request a new quest: details, a cover picture, the reward card and how many can be given out.
/// It goes to an admin for approval (status "pending"); once approved you get a QR code to put up at the place.
class QuestCreateScreen extends StatefulWidget {
  /// A quest that was rejected (or is still waiting) to fix and send again.
  final Quest? existing;
  const QuestCreateScreen({super.key, this.existing});

  @override
  State<QuestCreateScreen> createState() => _QuestCreateScreenState();
}

class _QuestCreateScreenState extends State<QuestCreateScreen> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _cardName = TextEditingController();
  final _lore = TextEditingController();
  final _limit = TextEditingController(text: '100');

  List<TravelLocation> _locations = [];
  TravelLocation? _location;
  bool _permanent = true;
  DateTimeRange? _range;
  String _rarity = 'normal';
  String? _cover;
  String? _artwork;
  bool _coverChanged = false;
  bool _artworkChanged = false;

  bool get _editing => widget.existing != null;
  bool _loading = true;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final q = widget.existing;
    if (q != null) {
      _title.text = q.title;
      _description.text = q.description;
      _permanent = q.permanent;
      if (!q.permanent && q.startDate != null && q.endDate != null) {
        _range = DateTimeRange(start: DateTime.parse(q.startDate!), end: DateTime.parse(q.endDate!));
      }
      final c = q.card;
      if (c != null) {
        _cardName.text = c.name;
        _lore.text = c.lore ?? '';
        _rarity = c.rarity;
        _limit.text = '${c.mintLimit ?? 100}';
      }
      _loadExistingImages(q.questId);
    }
    _loadLocations();
  }

  // The pictures of a quest still under review are private: fetch them with the creator's session.
  Future<void> _loadExistingImages(String questId) async {
    try {
      final data = await apiClient.get('/quests/$questId/images');
      if (!mounted) return;
      setState(() {
        _cover = data['cover_image'] as String?;
        _artwork = data['card_image'] as String?;
      });
    } catch (_) {
      // the pictures just show as empty; the old ones are kept unless a new one is picked
    }
  }

  @override
  void dispose() {
    for (final c in [_title, _description, _cardName, _lore, _limit]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadLocations() async {
    try {
      final data = await apiClient.get('/catalog/locations');
      if (!mounted) return;
      setState(() {
        _locations = (data['locations'] as List).map((e) => TravelLocation.fromJson(e)).toList();
        final wanted = widget.existing?.locationId;
        if (wanted != null) {
          for (final l in _locations) {
            if (l.locationId == wanted) _location = l;
          }
        }
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() {
        _loading = false;
        _error = 'โหลดรายการสถานที่ไม่สำเร็จ: $e';
      });
    }
  }

  // The picker must start inside the tap handler (iOS Safari), so no await before calling it.
  Future<void> _pickCover() async {
    final url = await pickJpeg(maxSide: 900, maxChars: 420000);
    if (url != null && mounted) {
      setState(() {
        _cover = url;
        _coverChanged = true;
      });
    }
  }

  Future<void> _pickArtwork() async {
    final url = await pickJpeg(maxSide: 1100, maxChars: 750000);
    if (url != null && mounted) {
      setState(() {
        _artwork = url;
        _artworkChanged = true;
      });
    }
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: DateTime(now.year + 3),
      initialDateRange: _range,
    );
    if (picked != null) setState(() => _range = picked);
  }

  String _fmt(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_location == null) return setState(() => _error = 'เลือกสถานที่ตั้งของภารกิจ');
    if (_cover == null) return setState(() => _error = 'เพิ่มภาพประกอบภารกิจ');
    if (_artwork == null) return setState(() => _error = 'เพิ่มภาพ Artwork ของการ์ด');
    if (!_permanent && _range == null) return setState(() => _error = 'เลือกวันเริ่มต้น-สิ้นสุด หรือเลือกภารกิจถาวร');
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final body = {
        'title': _title.text.trim(),
        'location_id': _location!.locationId,
        'description': _description.text.trim(),
        if (!_editing || _coverChanged) 'cover_image': _cover,
        'permanent': _permanent,
        if (!_permanent) 'start_date': _fmt(_range!.start),
        if (!_permanent) 'end_date': _fmt(_range!.end),
        'card_name': _cardName.text.trim(),
        if (!_editing || _artworkChanged) 'card_image': _artwork,
        'card_lore': _lore.text.trim(),
        'rarity': _rarity,
        'mint_limit': int.tryParse(_limit.text.trim()) ?? 0,
      };
      if (_editing) {
        await apiClient.put('/quests/${widget.existing!.questId}', body);
      } else {
        await apiClient.post('/quests', body);
      }
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.hourglass_top, color: AppColors.navy, size: 36),
          title: Text(_editing ? 'ส่งใหม่แล้ว' : 'ส่งคำร้องแล้ว'),
          content: const Text('แอดมินจะตรวจสอบเนื้อหาและรูปภาพ เมื่ออนุมัติแล้วคุณจะได้รับการแจ้งเตือน และดาวน์โหลด QR Code ไปติดที่สถานที่จริงได้'),
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

  Widget _section(String text) => Padding(
        padding: const EdgeInsets.only(top: 22, bottom: 10),
        child: Text(text, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.navy)),
      );

  Widget _imageBox({required String label, required String? dataUrl, required double aspect, required VoidCallback onTap}) {
    Uint8List? bytes;
    if (dataUrl != null) bytes = decodeDataUrl(dataUrl);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AspectRatio(
        aspectRatio: aspect,
        child: Container(
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFDDE2EA))),
          clipBehavior: Clip.antiAlias,
          child: bytes == null
              ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Icon(Icons.add_photo_alternate_outlined, size: 40, color: AppColors.navy),
                  const SizedBox(height: 6),
                  Text(label, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
                ])
              : Stack(fit: StackFit.expand, children: [
                  Image.memory(bytes, fit: BoxFit.cover),
                  const Positioned(right: 8, bottom: 8, child: CircleAvatar(radius: 16, backgroundColor: Colors.black54, child: Icon(Icons.edit, size: 16, color: Colors.white))),
                ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_editing ? 'แก้ไขภารกิจ' : 'สร้างภารกิจใหม่')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  _section('ส่วนที่ 1: ข้อมูลภารกิจ'),
                  TextFormField(
                    controller: _title,
                    maxLength: 80,
                    decoration: const InputDecoration(labelText: 'ชื่อภารกิจ', hintText: 'เช่น ตามหาร้านกาแฟลับลับ'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'กรอกชื่อภารกิจ' : null,
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<TravelLocation>(
                    initialValue: _location,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'สถานที่ตั้ง'),
                    items: _locations.map((l) => DropdownMenuItem(value: l, child: Text('${l.name} (${l.province})', overflow: TextOverflow.ellipsis))).toList(),
                    onChanged: (v) => setState(() => _location = v),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _description,
                    maxLines: 4,
                    maxLength: 2000,
                    decoration: const InputDecoration(labelText: 'คำอธิบายภารกิจ / เงื่อนไขการทำภารกิจ'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'กรอกคำอธิบายภารกิจ' : null,
                  ),
                  const SizedBox(height: 8),
                  const Text('ภาพประกอบภารกิจ (1 ภาพ)', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  _imageBox(label: 'แตะเพื่อเลือกภาพ (แนวนอน)', dataUrl: _cover, aspect: 16 / 9, onTap: _pickCover),
                  const SizedBox(height: 16),
                  const Text('ระยะเวลาภารกิจ', style: TextStyle(fontWeight: FontWeight.w600)),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('ภารกิจถาวร (ไม่มีวันสิ้นสุด)'),
                    value: _permanent,
                    onChanged: (v) => setState(() => _permanent = v),
                  ),
                  if (!_permanent)
                    OutlinedButton.icon(
                      icon: const Icon(Icons.date_range),
                      label: Text(_range == null ? 'เลือกวันที่เริ่มต้น - สิ้นสุด' : '${_fmt(_range!.start)}  ถึง  ${_fmt(_range!.end)}'),
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                      onPressed: _pickRange,
                    ),
                  _section('ส่วนที่ 2: การ์ดรางวัล'),
                  TextFormField(
                    controller: _cardName,
                    maxLength: 60,
                    decoration: const InputDecoration(labelText: 'ชื่อการ์ด'),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'กรอกชื่อการ์ด' : null,
                  ),
                  const SizedBox(height: 8),
                  const Text('ภาพ Artwork การ์ด (แนวตั้ง ความละเอียดสูง)', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(width: 190, child: _imageBox(label: 'แตะเพื่อเลือกภาพ (แนวตั้ง 5:7)', dataUrl: _artwork, aspect: 5 / 7, onTap: _pickArtwork)),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _lore,
                    maxLines: 3,
                    maxLength: 500,
                    decoration: const InputDecoration(labelText: 'เรื่องราวของการ์ด / ประวัติสถานที่ (ไม่บังคับ)'),
                  ),
                  const SizedBox(height: 8),
                  const Text('ระดับความหายาก', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'normal', label: Text('Normal')),
                      ButtonSegment(value: 'rare', label: Text('Rare')),
                      ButtonSegment(value: 'special', label: Text('Special')),
                    ],
                    selected: {_rarity},
                    onSelectionChanged: (v) => setState(() => _rarity = v.first),
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _limit,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'จำนวนที่แจกได้สูงสุด (ใบ)', helperText: 'เมื่อแจกครบแล้ว จะสแกนรับเพิ่มไม่ได้'),
                    validator: (v) {
                      final n = int.tryParse((v ?? '').trim());
                      return (n == null || n < 1 || n > 100000) ? 'ใส่จำนวนเต็ม 1 - 100,000' : null;
                    },
                  ),
                  if (_error != null) ...[const SizedBox(height: 14), Text(_error!, style: const TextStyle(color: Colors.red))],
                  const SizedBox(height: 22),
                  ElevatedButton(
                    onPressed: _sending ? null : _submit,
                    child: _sending
                        ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : Text(_editing ? 'บันทึกและส่งให้แอดมินตรวจสอบอีกครั้ง' : 'ส่งคำร้องให้แอดมินตรวจสอบ'),
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
    );
  }
}
