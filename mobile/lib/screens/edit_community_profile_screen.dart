import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/community_models.dart';
import '../services/api_client.dart';
import '../services/app_state.dart';
import '../services/image_tools.dart';
import '../theme.dart';
import '../widgets/community_widgets.dart';

/// Edit how you appear in the community: display name, bio, profile picture, cover, and which badge to wear (or none).
class EditCommunityProfileScreen extends StatefulWidget {
  const EditCommunityProfileScreen({super.key});

  @override
  State<EditCommunityProfileScreen> createState() => _EditCommunityProfileScreenState();
}

class _EditCommunityProfileScreenState extends State<EditCommunityProfileScreen> {
  final _name = TextEditingController();
  final _bio = TextEditingController();
  CommunityProfile? _p;
  String? _avatar; // data URL of a new picture
  String? _cover;
  bool _removeAvatar = false;
  bool _removeCover = false;
  bool _badgeVisible = true;
  String? _badgeId;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _bio.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final data = await apiClient.get('/community/me');
      final p = CommunityProfile.fromJson(data['profile'] as Map<String, dynamic>);
      if (!mounted) return;
      setState(() {
        _p = p;
        _name.text = p.author.displayName == p.author.username ? '' : p.author.displayName;
        _bio.text = p.bio;
        _badgeVisible = p.badgeVisible;
        _badgeId = p.selectedBadgeId;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'โหลดโปรไฟล์ไม่สำเร็จ: $e';
        });
      }
    }
  }

  Future<void> _pickAvatar() async {
    final url = await pickJpeg(maxSide: 256, maxChars: 24000);
    if (url != null && mounted) setState(() { _avatar = url; _removeAvatar = false; });
  }

  Future<void> _pickCover() async {
    final url = await pickJpeg(maxSide: 900, maxChars: 88000);
    if (url != null && mounted) setState(() { _cover = url; _removeCover = false; });
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await apiClient.put('/community/me', {
        'display_name': _name.text.trim(),
        'bio': _bio.text.trim(),
        if (_avatar != null) 'avatar': _avatar else if (_removeAvatar) 'avatar': null,
        if (_cover != null) 'cover': _cover else if (_removeCover) 'cover': null,
        'is_badge_visible': _badgeVisible,
        'selected_badge_id': _badgeId,
      });
      communityRefresh.value++;
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'บันทึกไม่สำเร็จ: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = _p;
    final username = context.read<AppState>().currentUser?.username ?? '';
    return Scaffold(
      appBar: AppBar(title: const Text('แก้ไขโปรไฟล์ชุมชน')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : p == null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error ?? 'โหลดไม่สำเร็จ')))
              : ListView(padding: const EdgeInsets.all(20), children: [
                  const Text('ภาพปก', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: _pickCover,
                    borderRadius: BorderRadius.circular(14),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: SizedBox(
                        height: 150,
                        width: double.infinity,
                        child: _cover != null
                            ? Image.memory(decodeDataUrl(_cover!), fit: BoxFit.cover)
                            : (p.hasCover && !_removeCover)
                                ? Image.network(p.cover!, fit: BoxFit.cover)
                                : const ColoredBox(color: Color(0xFFE3E7EF), child: Center(child: Icon(Icons.add_photo_alternate_outlined, size: 36, color: AppColors.navy))),
                      ),
                    ),
                  ),
                  if (_cover != null || (p.hasCover && !_removeCover))
                    Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => setState(() { _cover = null; _removeCover = true; }), child: const Text('ลบภาพปก'))),
                  const SizedBox(height: 10),
                  Row(children: [
                    GestureDetector(
                      onTap: _pickAvatar,
                      child: _avatar != null
                          ? CircleAvatar(radius: 40, backgroundImage: MemoryImage(decodeDataUrl(_avatar!)))
                          : (_removeAvatar ? CircleAvatar(radius: 40, backgroundColor: AppColors.navy, child: Text(username.isEmpty ? '?' : username[0].toUpperCase(), style: const TextStyle(color: Colors.white, fontSize: 30))) : AuthorAvatar(author: p.author, radius: 40)),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        OutlinedButton.icon(icon: const Icon(Icons.photo_camera_outlined), label: const Text('เปลี่ยนรูปโปรไฟล์'), onPressed: _pickAvatar),
                        if (_avatar != null || (p.author.hasAvatar && !_removeAvatar)) TextButton(onPressed: () => setState(() { _avatar = null; _removeAvatar = true; }), child: const Text('ลบรูปโปรไฟล์')),
                      ]),
                    ),
                  ]),
                  const SizedBox(height: 16),
                  TextField(controller: _name, maxLength: 30, decoration: InputDecoration(labelText: 'ชื่อที่แสดง (Display Name)', helperText: 'เว้นว่างไว้จะใช้ชื่อผู้ใช้ @$username')),
                  const SizedBox(height: 8),
                  TextField(controller: _bio, maxLength: 200, maxLines: 3, decoration: const InputDecoration(labelText: 'คำอธิบายตัวเอง (Bio)')),
                  const SizedBox(height: 16),
                  const Text('ตราสัญลักษณ์ (Badge)', style: TextStyle(fontWeight: FontWeight.bold)),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('แสดงตราสัญลักษณ์หลังชื่อ'),
                    subtitle: const Text('ใช้กับทุกหน้า เช่น โพสต์ คอมเมนต์ อันดับ'),
                    value: _badgeVisible,
                    onChanged: (v) => setState(() => _badgeVisible = v),
                  ),
                  if (p.badges.isEmpty)
                    const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('ยังไม่มีตราสัญลักษณ์ ติดอันดับนักเที่ยวประจำเดือนเพื่อรับตรา', style: TextStyle(color: Colors.grey)))
                  else
                    RadioGroup<String?>(
                      groupValue: _badgeId,
                      onChanged: (v) => setState(() => _badgeId = v),
                      child: Column(
                        children: p.badges
                            .map((b) => RadioListTile<String?>(
                                  contentPadding: EdgeInsets.zero,
                                  value: b.badgeId,
                                  secondary: Icon(Icons.workspace_premium, color: b.color),
                                  title: Text(b.title, style: const TextStyle(fontSize: 14)),
                                ))
                            .toList(),
                      ),
                    ),
                  if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: const TextStyle(color: Colors.red))),
                  const SizedBox(height: 16),
                  ElevatedButton(onPressed: _saving ? null : _save, child: _saving ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('บันทึก')),
                  const SizedBox(height: 30),
                ]),
    );
  }
}
