import 'package:flutter/material.dart';
import '../services/api_client.dart';
import '../theme.dart';
import '../utils/icon_map.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  List<Map<String, dynamic>> _locations = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await apiClient.get('/admin/locations');
      setState(() {
        _locations = List<Map<String, dynamic>>.from(data['locations']);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'โหลดข้อมูลไม่สำเร็จ: $e';
        _loading = false;
      });
    }
  }

  Future<void> _openForm({Map<String, dynamic>? existing}) async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => AdminLocationFormScreen(existing: existing)),
    );
    if (saved == true) _load();
  }

  Future<void> _delete(Map<String, dynamic> loc) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ยืนยันการลบ'),
        content: Text('ต้องการลบ "${loc['name']}" ใช่หรือไม่?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('ยกเลิก')),
          TextButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('ลบ', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await apiClient.delete('/admin/locations/${loc['location_id']}');
      _load();
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('จัดการสถานที่ (Admin)')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openForm(),
        icon: const Icon(Icons.add),
        label: const Text('เพิ่มสถานที่'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!, textAlign: TextAlign.center)))
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _locations.length,
                    itemBuilder: (ctx, i) {
                      final loc = _locations[i];
                      final mission = loc['mission'] as Map<String, dynamic>?;
                      final card = loc['card'] as Map<String, dynamic>?;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          leading: CircleAvatar(backgroundColor: AppColors.navy, child: Icon(iconFor(loc['icon'] ?? 'place'), color: Colors.white)),
                          title: Text(loc['name'] ?? ''),
                          subtitle: Text(
                            '${loc['province'] ?? ''}\nภารกิจ: ${mission?['title'] ?? '-'}\nการ์ด: ${card?['name'] ?? '-'} (${card?['rarity'] ?? '-'})',
                          ),
                          isThreeLine: true,
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(icon: const Icon(Icons.edit, size: 20), onPressed: () => _openForm(existing: loc)),
                              IconButton(icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red), onPressed: () => _delete(loc)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}

const _kIcons = [
  'temple_buddhist', 'landscape', 'beach_access', 'account_balance', 'train',
  'terrain', 'restaurant', 'local_cafe', 'store', 'checkroom', 'pedal_bike', 'star', 'auto_awesome', 'place',
];
const _kRarities = ['common', 'rare', 'epic'];

class AdminLocationFormScreen extends StatefulWidget {
  final Map<String, dynamic>? existing;
  const AdminLocationFormScreen({super.key, this.existing});

  @override
  State<AdminLocationFormScreen> createState() => _AdminLocationFormScreenState();
}

class _AdminLocationFormScreenState extends State<AdminLocationFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?['name'] ?? '');
  late final _description = TextEditingController(text: widget.existing?['description'] ?? '');
  late final _province = TextEditingController(text: widget.existing?['province'] ?? '');
  late final _latitude = TextEditingController(text: widget.existing?['latitude']?.toString() ?? '');
  late final _longitude = TextEditingController(text: widget.existing?['longitude']?.toString() ?? '');
  late final _missionTitle = TextEditingController(text: widget.existing?['mission']?['title'] ?? '');
  late final _missionDescription = TextEditingController(text: widget.existing?['mission']?['description'] ?? '');
  late final _cardName = TextEditingController(text: widget.existing?['card']?['name'] ?? '');
  late final _cardColorHex = TextEditingController(text: widget.existing?['card']?['color_hex'] ?? '#4C6B8A');

  late String _icon = widget.existing?['icon'] ?? _kIcons.first;
  late String _cardIcon = widget.existing?['card']?['icon'] ?? _kIcons.first;
  late String _rarity = widget.existing?['card']?['rarity'] ?? 'common';
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final payload = {
      'name': _name.text.trim(),
      'description': _description.text.trim(),
      'province': _province.text.trim(),
      'latitude': double.tryParse(_latitude.text.trim()),
      'longitude': double.tryParse(_longitude.text.trim()),
      'icon': _icon,
      'mission_title': _missionTitle.text.trim(),
      'mission_description': _missionDescription.text.trim(),
      'card_name': _cardName.text.trim(),
      'card_icon': _cardIcon,
      'card_color_hex': _cardColorHex.text.trim(),
      'card_rarity': _rarity,
    };
    try {
      if (_isEdit) {
        await apiClient.put('/admin/locations/${widget.existing!['location_id']}', payload);
      } else {
        await apiClient.post('/admin/locations', payload);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
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
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? 'แก้ไขสถานที่' : 'เพิ่มสถานที่ใหม่')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('ข้อมูลสถานที่', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'ชื่อสถานที่'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'กรอกชื่อสถานที่' : null,
                ),
                const SizedBox(height: 10),
                TextFormField(controller: _description, decoration: const InputDecoration(labelText: 'คำอธิบาย'), maxLines: 2),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _province,
                  decoration: const InputDecoration(labelText: 'จังหวัด'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'กรอกจังหวัด' : null,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _latitude,
                        decoration: const InputDecoration(labelText: 'ละติจูด'),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                        validator: (v) => double.tryParse(v ?? '') == null ? 'ตัวเลขไม่ถูกต้อง' : null,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextFormField(
                        controller: _longitude,
                        decoration: const InputDecoration(labelText: 'ลองจิจูด'),
                        keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                        validator: (v) => double.tryParse(v ?? '') == null ? 'ตัวเลขไม่ถูกต้อง' : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _IconDropdown(label: 'ไอคอนสถานที่', value: _icon, onChanged: (v) => setState(() => _icon = v)),

                const SizedBox(height: 24),
                const Text('ภารกิจ (Mission)', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _missionTitle,
                  decoration: const InputDecoration(labelText: 'ชื่อภารกิจ'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'กรอกชื่อภารกิจ' : null,
                ),
                const SizedBox(height: 10),
                TextFormField(controller: _missionDescription, decoration: const InputDecoration(labelText: 'คำอธิบายภารกิจ'), maxLines: 2),

                const SizedBox(height: 24),
                const Text('การ์ดที่ระลึก (Card)', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _cardName,
                  decoration: const InputDecoration(labelText: 'ชื่อการ์ด'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'กรอกชื่อการ์ด' : null,
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _cardColorHex,
                  decoration: const InputDecoration(labelText: 'สี (hex เช่น #4C6B8A)'),
                ),
                const SizedBox(height: 10),
                _IconDropdown(label: 'ไอคอนการ์ด', value: _cardIcon, onChanged: (v) => setState(() => _cardIcon = v)),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: _rarity,
                  decoration: const InputDecoration(labelText: 'ความหายาก'),
                  items: _kRarities.map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
                  onChanged: (v) => setState(() => _rarity = v ?? 'common'),
                ),

                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _saving ? null : _submit,
                  child: _saving
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : Text(_isEdit ? 'บันทึกการแก้ไข' : 'สร้างสถานที่'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _IconDropdown extends StatelessWidget {
  final String label;
  final String value;
  final ValueChanged<String> onChanged;
  const _IconDropdown({required this.label, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      items: _kIcons
          .map((i) => DropdownMenuItem(value: i, child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(iconFor(i), size: 18), const SizedBox(width: 8), Text(i)])))
          .toList(),
      onChanged: (v) => onChanged(v ?? _kIcons.first),
    );
  }
}
