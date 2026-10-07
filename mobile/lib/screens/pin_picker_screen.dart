import 'package:flutter/material.dart';
import '../models/models.dart';
import '../services/api_client.dart';
import '../theme.dart';
import '../widgets/card_widgets.dart';

/// Choose up to 5 cards to pin on top of your profile. The order you tap them is the order they are shown.
class PinPickerScreen extends StatefulWidget {
  const PinPickerScreen({super.key});

  @override
  State<PinPickerScreen> createState() => _PinPickerScreenState();
}

class _PinPickerScreenState extends State<PinPickerScreen> {
  List<TravelCard> _cards = [];
  final List<String> _selected = [];
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final cards = await apiClient.get('/cards');
      final profile = await apiClient.get('/profile/me');
      if (!mounted) return;
      setState(() {
        _cards = (cards['cards'] as List).map((e) => TravelCard.fromJson(e)).toList();
        _selected
          ..clear()
          ..addAll((profile['pins'] as List).map((e) => e['card_instance_id'] as String));
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toggle(TravelCard c) {
    setState(() {
      if (_selected.contains(c.cardInstanceId)) {
        _selected.remove(c.cardInstanceId);
      } else if (_selected.length < 5) {
        _selected.add(c.cardInstanceId);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ปักหมุดได้สูงสุด 5 ใบ')));
      }
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await apiClient.put('/profile/pins', {'card_instance_ids': _selected});
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('ตู้โชว์การ์ด (${_selected.length}/5)')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _cards.isEmpty
              ? const Center(child: Text('ยังไม่มีการ์ดในคลัง', style: TextStyle(color: Colors.grey)))
              : GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 130, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 0.71),
                  itemCount: _cards.length,
                  itemBuilder: (_, i) {
                    final c = _cards[i];
                    final order = _selected.indexOf(c.cardInstanceId);
                    return GestureDetector(
                      onTap: () => _toggle(c),
                      child: Stack(children: [
                        Positioned.fill(child: CardFace(card: c)),
                        if (order >= 0)
                          Positioned.fill(
                            child: Container(
                              decoration: BoxDecoration(border: Border.all(color: AppColors.gold, width: 4), borderRadius: BorderRadius.circular(14)),
                              alignment: Alignment.topRight,
                              padding: const EdgeInsets.all(5),
                              child: CircleAvatar(radius: 12, backgroundColor: AppColors.gold, child: Text('${order + 1}', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold))),
                            ),
                          ),
                      ]),
                    );
                  },
                ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'กำลังบันทึก...' : 'บันทึกตู้โชว์')),
        ),
      ),
    );
  }
}
