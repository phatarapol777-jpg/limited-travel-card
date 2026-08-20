import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../services/api_client.dart';
import '../services/app_state.dart';
import '../theme.dart';
import 'login_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  List<TravelHistoryEntry> _history = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      await context.read<AppState>().refreshStats();
      final data = await apiClient.get('/history');
      setState(() {
        _history = (data['history'] as List).map((e) => TravelHistoryEntry.fromJson(e)).toList();
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  String _levelFor(int cardCount) {
    if (cardCount >= 6) return 'นักสะสมระดับตำนาน';
    if (cardCount >= 3) return 'นักสะสมมือทอง';
    if (cardCount >= 1) return 'นักเดินทางมือใหม่';
    return 'ยังไม่มีการ์ด';
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final user = appState.currentUser;
    final stats = appState.stats;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () {
              context.read<AppState>().logout();
              Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (r) => false);
            },
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  Center(
                    child: Column(
                      children: [
                        CircleAvatar(radius: 40, backgroundColor: AppColors.navy, child: Text(
                          (user?.firstName.isNotEmpty ?? false) ? user!.firstName.substring(0, 1) : '?',
                          style: const TextStyle(color: Colors.white, fontSize: 28),
                        )),
                        const SizedBox(height: 12),
                        Text('${user?.firstName ?? ''} ${user?.lastName ?? ''}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        Text('@${user?.username ?? ''}', style: const TextStyle(color: Colors.grey)),
                        const SizedBox(height: 6),
                        Chip(
                          label: Text(_levelFor(stats?.cards ?? 0)),
                          backgroundColor: AppColors.gold.withValues(alpha: 0.18),
                          labelStyle: const TextStyle(color: AppColors.navyDark, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      _StatBox(label: 'การ์ด', value: '${stats?.cards ?? 0}'),
                      const SizedBox(width: 10),
                      _StatBox(label: 'สถานที่', value: '${stats?.placesVisited ?? 0}'),
                      const SizedBox(width: 10),
                      _StatBox(label: 'ภารกิจ', value: '${stats?.missionsCompleted ?? 0}'),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Text('ประวัติการเดินทาง', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  if (_history.isEmpty)
                    const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Text('ยังไม่มีประวัติการเดินทาง'))
                  else
                    ..._history.map((h) => Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: const Icon(Icons.location_on, color: AppColors.navy),
                            title: Text(h.locationName),
                            subtitle: Text('${h.province} · ${h.timestamp.substring(0, 10)}'),
                            trailing: Icon(h.status == 'success' ? Icons.check_circle : Icons.error, color: h.status == 'success' ? AppColors.success : Colors.red),
                          ),
                        )),
                ],
              ),
            ),
    );
  }
}

class _StatBox extends StatelessWidget {
  final String label;
  final String value;
  const _StatBox({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: const Color(0xFFE3E7EF))),
        child: Column(
          children: [
            Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppColors.navy)),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}
