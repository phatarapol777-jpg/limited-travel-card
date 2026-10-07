import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../models/community_models.dart';
import '../models/models.dart';
import '../services/api_client.dart';
import '../services/image_tools.dart';
import '../theme.dart';

class _Pic {
  final String? id; // a picture already on the post
  final String? dataUrl; // a new one
  _Pic.existing(this.id) : dataUrl = null;
  _Pic.fresh(this.dataUrl) : id = null;
}

/// Write a post (or edit one): text with #hashtags, up to 10 pictures, and an optional place tag.
class PostComposerScreen extends StatefulWidget {
  final String? existingPostId;
  final PlaceRef? initialPlace;
  const PostComposerScreen({super.key, this.existingPostId, this.initialPlace});

  @override
  State<PostComposerScreen> createState() => _PostComposerScreenState();
}

class _PostComposerScreenState extends State<PostComposerScreen> {
  final _text = TextEditingController();
  final List<_Pic> _pics = [];
  PlaceRef? _place;
  bool _loading = false;
  bool _sending = false;
  String? _error;

  bool get _editing => widget.existingPostId != null;

  @override
  void initState() {
    super.initState();
    _place = widget.initialPlace;
    if (_editing) _loadExisting();
  }

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _loadExisting() async {
    setState(() => _loading = true);
    try {
      final data = await apiClient.get('/community/posts/${widget.existingPostId}');
      final p = FeedPost.fromJson(data['post'] as Map<String, dynamic>);
      if (!mounted) return;
      setState(() {
        _text.text = p.content;
        _place = p.place;
        _pics
          ..clear()
          ..addAll(p.imageIds.map(_Pic.existing));
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'โหลดโพสต์ไม่สำเร็จ: $e';
        });
      }
    }
  }

  // The picker must start inside the tap handler (iOS Safari), so no await before calling it.
  Future<void> _addPicture() async {
    final url = await pickJpeg(maxSide: 760, maxChars: 44000);
    if (url == null) {
      if (mounted) setState(() => _error = 'เลือกรูปไม่สำเร็จ หรือรูปใหญ่เกินไป ลองรูปอื่น');
      return;
    }
    if (mounted) {
      setState(() {
        _pics.add(_Pic.fresh(url));
        _error = null;
      });
    }
  }

  Future<void> _pickPlace() async {
    final picked = await showModalBottomSheet<PlaceRef>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => const _PlacePicker(),
    );
    if (picked != null && mounted) setState(() => _place = picked);
  }

  Future<void> _submit() async {
    if (_text.text.trim().isEmpty && _pics.isEmpty) {
      setState(() => _error = 'เขียนข้อความหรือแนบรูปอย่างน้อยหนึ่งอย่าง');
      return;
    }
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final body = {
        'content': _text.text.trim(),
        'images': _pics.map((p) => p.id != null ? {'image_id': p.id} : {'image': p.dataUrl}).toList(),
        'location_id': _place?.locationId,
      };
      if (_editing) {
        await apiClient.put('/community/posts/${widget.existingPostId}', body);
      } else {
        await apiClient.post('/community/posts', body);
      }
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'โพสต์ไม่สำเร็จ: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Widget _thumb(int i) {
    final p = _pics[i];
    final Widget image = p.id != null ? Image.network(postImageUrl(p.id!), fit: BoxFit.cover) : Image.memory(_bytes(p.dataUrl!), fit: BoxFit.cover);
    return Stack(children: [
      Positioned.fill(child: ClipRRect(borderRadius: BorderRadius.circular(10), child: image)),
      Positioned(
        top: 4,
        right: 4,
        child: GestureDetector(onTap: () => setState(() => _pics.removeAt(i)), child: const CircleAvatar(radius: 11, backgroundColor: Colors.black54, child: Icon(Icons.close, size: 14, color: Colors.white))),
      ),
    ]);
  }

  Uint8List _bytes(String dataUrl) => decodeDataUrl(dataUrl);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? 'แก้ไขโพสต์' : 'สร้างโพสต์'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton(
              onPressed: _sending || _loading ? null : _submit,
              child: _sending ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text(_editing ? 'บันทึก' : 'โพสต์', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
            ),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.all(16), children: [
              TextField(
                controller: _text,
                maxLines: 6,
                maxLength: 2000,
                decoration: const InputDecoration(hintText: 'เล่าประสบการณ์การเดินทางของคุณ... ใส่ #แฮชแท็ก ได้', border: InputBorder.none),
              ),
              if (_place != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: InputChip(
                      avatar: const Icon(Icons.place, size: 18, color: Colors.redAccent),
                      label: Text(_place!.province == null ? _place!.name : '${_place!.name} · ${_place!.province}'),
                      onDeleted: () => setState(() => _place = null),
                      onPressed: _pickPlace,
                    ),
                  ),
                ),
              if (_pics.isNotEmpty)
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 3,
                  mainAxisSpacing: 6,
                  crossAxisSpacing: 6,
                  children: [for (var i = 0; i < _pics.length; i++) _thumb(i)],
                ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: OutlinedButton.icon(icon: const Icon(Icons.add_photo_alternate_outlined), label: Text('เพิ่มรูป (${_pics.length}/10)'), onPressed: _pics.length >= 10 ? null : _addPicture)),
                const SizedBox(width: 10),
                Expanded(child: OutlinedButton.icon(icon: const Icon(Icons.place_outlined), label: Text(_place == null ? 'แท็กสถานที่' : 'เปลี่ยนสถานที่'), onPressed: _pickPlace)),
              ]),
              const SizedBox(height: 8),
              const Text('รูปภาพถูกย่อให้เล็กลงอัตโนมัติ · ไม่รองรับวิดีโอ · แท็กสถานที่ที่ต่างกันช่วยให้ติดอันดับนักเที่ยวประจำเดือน', style: TextStyle(color: Colors.grey, fontSize: 12)),
              if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: Colors.red))),
            ]),
    );
  }
}

class _PlacePicker extends StatefulWidget {
  const _PlacePicker();

  @override
  State<_PlacePicker> createState() => _PlacePickerState();
}

class _PlacePickerState extends State<_PlacePicker> {
  List<PlaceRef> _all = [];
  List<PlaceRef> _booked = [];
  List<PlaceRef> _checkedIn = [];
  String _query = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final locs = await apiClient.get('/catalog/locations');
      final all = (locs['locations'] as List).map((e) => TravelLocation.fromJson(e)).map((l) => PlaceRef(locationId: l.locationId, name: l.name, province: l.province)).toList();
      List<PlaceRef> booked = [];
      List<PlaceRef> checked = [];
      try {
        final s = await apiClient.get('/community/suggestions');
        booked = (s['booked'] as List).map((e) => PlaceRef.fromJson(e)).toList();
        checked = (s['checked_in'] as List).map((e) => PlaceRef.fromJson(e)).toList();
      } catch (_) {
        // suggestions are a convenience; the search still works
      }
      if (mounted) {
        setState(() {
          _all = all;
          _booked = booked;
          _checkedIn = checked;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _tile(PlaceRef p, {IconData icon = Icons.place_outlined}) => ListTile(
        leading: Icon(icon, color: AppColors.navy),
        title: Text(p.name),
        subtitle: p.province == null ? null : Text(p.province!),
        onTap: () => Navigator.of(context).pop(p),
      );

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final results = q.isEmpty ? <PlaceRef>[] : _all.where((p) => p.name.toLowerCase().contains(q) || (p.province ?? '').toLowerCase().contains(q)).toList();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.75,
          child: Column(children: [
            Padding(padding: const EdgeInsets.all(14), child: TextField(autofocus: false, decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'ค้นหาสถานที่ท่องเที่ยวหรือจังหวัด'), onChanged: (v) => setState(() => _query = v))),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(children: [
                      if (q.isNotEmpty) ...[
                        if (results.isEmpty) const Padding(padding: EdgeInsets.all(30), child: Center(child: Text('ไม่พบสถานที่', style: TextStyle(color: Colors.grey)))),
                        ...results.map(_tile),
                      ] else ...[
                        if (_booked.isNotEmpty) ...[
                          const Padding(padding: EdgeInsets.fromLTRB(16, 4, 16, 4), child: Text('จากการจองของคุณ', style: TextStyle(fontWeight: FontWeight.bold))),
                          ..._booked.map((p) => _tile(p, icon: Icons.hotel)),
                        ],
                        if (_checkedIn.isNotEmpty) ...[
                          const Padding(padding: EdgeInsets.fromLTRB(16, 12, 16, 4), child: Text('ที่คุณเคยเช็กอิน', style: TextStyle(fontWeight: FontWeight.bold))),
                          ..._checkedIn.map((p) => _tile(p, icon: Icons.check_circle_outline)),
                        ],
                        const Padding(padding: EdgeInsets.fromLTRB(16, 12, 16, 4), child: Text('สถานที่ทั้งหมด', style: TextStyle(fontWeight: FontWeight.bold))),
                        ..._all.map(_tile),
                      ],
                    ]),
            ),
          ]),
        ),
      ),
    );
  }
}
