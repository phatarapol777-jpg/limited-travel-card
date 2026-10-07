import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../models/collection_models.dart';
import '../models/community_models.dart';
import '../widgets/community_widgets.dart';
import '../models/models.dart';
import '../services/api_client.dart';
import '../services/app_state.dart';
import '../theme.dart';
import '../widgets/profile_widgets.dart';
import 'admin_screen.dart';
import 'card_detail_screen.dart';
import 'face_enroll_screen.dart';
import 'login_screen.dart';
import 'my_quests_screen.dart';
import 'my_bookings_screen.dart';
import 'my_shops_screen.dart';
import 'community_profile_screen.dart';
import 'edit_community_profile_screen.dart';
import 'leaderboard_screen.dart';
import 'notifications_screen.dart';
import 'pin_picker_screen.dart';
import 'trades_screen.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  List<TravelHistoryEntry> _history = [];
  ProfileData? _profile;
  CommunityProfile? _community; // how the community sees me: display name, picture, badge
  int _unread = 0;
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
      final profile = await apiClient.get('/profile/me');
      final data = await apiClient.get('/history');
      final notes = await apiClient.get('/notifications');
      CommunityProfile? community;
      try {
        community = CommunityProfile.fromJson((await apiClient.get('/community/me'))['profile'] as Map<String, dynamic>);
      } catch (_) {
        // the header falls back to the real name
      }
      if (!mounted) return;
      setState(() {
        _community = community;
        _profile = ProfileData.fromJson(profile);
        _history = (data['history'] as List).map((e) => TravelHistoryEntry.fromJson(e)).toList();
        _unread = notes['unread'] as int? ?? 0;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _confirmDeleteFace() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ลบข้อมูลใบหน้า?'),
        content: const Text('หลังลบ คุณจะเช็คอินที่ Kiosk ไม่ได้จนกว่าจะลงทะเบียนใบหน้าใหม่'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('ยกเลิก')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('ลบ')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await context.read<AppState>().deleteFace();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('ลบไม่สำเร็จ: $e')));
    }
  }

  Future<void> _changePassword() async {
    final current = TextEditingController();
    final next = TextEditingController();
    final again = TextEditingController();
    String? error;
    final done = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: const Text('เปลี่ยนรหัสผ่าน'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: current, obscureText: true, decoration: const InputDecoration(labelText: 'รหัสผ่านปัจจุบัน')),
              const SizedBox(height: 10),
              TextField(controller: next, obscureText: true, decoration: const InputDecoration(labelText: 'รหัสผ่านใหม่ (อย่างน้อย 8 ตัวอักษร)')),
              const SizedBox(height: 10),
              TextField(controller: again, obscureText: true, decoration: const InputDecoration(labelText: 'ยืนยันรหัสผ่านใหม่')),
              if (error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(error!, style: const TextStyle(color: Colors.red))),
              const SizedBox(height: 8),
              const Text('บัญชีที่เข้าด้วย Google ไม่มีรหัสผ่านให้เปลี่ยน อุปกรณ์อื่นที่ล็อกอินอยู่จะถูกออกจากระบบ', style: TextStyle(color: Colors.grey, fontSize: 12)),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('ยกเลิก')),
            TextButton(
              onPressed: () async {
                if (next.text != again.text) return setDialog(() => error = 'รหัสผ่านใหม่สองช่องไม่ตรงกัน');
                try {
                  await context.read<AppState>().changePassword(current.text, next.text);
                  if (ctx.mounted) Navigator.of(ctx).pop(true);
                } on ApiException catch (e) {
                  setDialog(() => error = e.message);
                } catch (e) {
                  setDialog(() => error = 'เชื่อมต่อเซิร์ฟเวอร์ไม่ได้');
                }
              },
              child: const Text('เปลี่ยน'),
            ),
          ],
        ),
      ),
    );
    if (done == true && mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('เปลี่ยนรหัสผ่านแล้ว')));
  }

  Future<void> _deleteAccount() async {
    final username = context.read<AppState>().currentUser?.username ?? '';
    final typed = TextEditingController();
    String? error;
    final done = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          icon: const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 36),
          title: const Text('ลบบัญชีของฉัน'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('ชื่อ อีเมล เบอร์โทร และข้อมูลใบหน้าของคุณจะถูกลบ ข้อเสนอแลกเปลี่ยนที่รออยู่จะถูกยกเลิก และกู้คืนไม่ได้'),
              const SizedBox(height: 10),
              Text('พิมพ์ Username "$username" เพื่อยืนยัน', style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              TextField(controller: typed, decoration: const InputDecoration(labelText: 'Username')),
              if (error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(error!, style: const TextStyle(color: Colors.red))),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('ยกเลิก')),
            TextButton(
              onPressed: () async {
                try {
                  await context.read<AppState>().deleteAccount(typed.text.trim());
                  if (ctx.mounted) Navigator.of(ctx).pop(true);
                } on ApiException catch (e) {
                  setDialog(() => error = e.message);
                } catch (e) {
                  setDialog(() => error = 'เชื่อมต่อเซิร์ฟเวอร์ไม่ได้');
                }
              },
              child: const Text('ลบบัญชีถาวร', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ),
    );
    if (done == true && mounted) {
      Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (r) => false);
    }
  }

  void _showMyQr(String username) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('QR โปรไฟล์ของฉัน'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(color: Colors.white, padding: const EdgeInsets.all(8), child: QrImageView(data: 'TRVUSER|$username', size: 220, backgroundColor: Colors.white)),
          const SizedBox(height: 10),
          Text('@$username', style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text('ให้เพื่อนสแกนด้วยปุ่มสแกนหลัก เพื่อดูโปรไฟล์และส่ง/แลกการ์ด', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 12)),
        ]),
        actions: [TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('ปิด'))],
      ),
    );
  }

  Future<void> _go(Widget screen) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
    if (mounted) _load();
  }

  Widget _menu(IconData icon, String title, {String? subtitle, Widget? trailing, required VoidCallback onTap}) => Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          leading: Icon(icon, color: AppColors.navy),
          title: Text(title),
          subtitle: subtitle == null ? null : Text(subtitle),
          trailing: trailing ?? const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<AppState>();
    final user = appState.currentUser;
    final p = _profile;

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
                    child: Column(children: [
                      if (_community != null)
                        AuthorAvatar(author: _community!.author, radius: 40)
                      else
                        CircleAvatar(
                          radius: 40,
                          backgroundColor: AppColors.navy,
                          child: Text((user?.firstName.isNotEmpty ?? false) ? user!.firstName.substring(0, 1) : '?', style: const TextStyle(color: Colors.white, fontSize: 28)),
                        ),
                      const SizedBox(height: 12),
                      if (_community != null)
                        AuthorName(author: _community!.author, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold))
                      else
                        Text('${user?.firstName ?? ''} ${user?.lastName ?? ''}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      Text('@${user?.username ?? ''}', style: const TextStyle(color: Colors.grey)),
                    ]),
                  ),
                  if (user?.usingDefaultPassword == true) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(color: const Color(0xFFFFF3CD), borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFE0B100))),
                      child: Row(children: [
                        const Icon(Icons.warning_amber_rounded, color: Color(0xFF8A6D00)),
                        const SizedBox(width: 10),
                        const Expanded(child: Text('บัญชีแอดมินยังใช้รหัสผ่านเริ่มต้น กรุณาเปลี่ยนทันที', style: TextStyle(color: Color(0xFF5C4400)))),
                        TextButton(onPressed: _changePassword, child: const Text('เปลี่ยน')),
                      ]),
                    ),
                  ],
                  if (p != null) ...[
                    const SizedBox(height: 18),
                    RankCard(stats: p.stats),
                    const SizedBox(height: 14),
                    StatBoxes(stats: p.stats),
                    const SizedBox(height: 22),
                    Row(children: [
                      const Expanded(child: Text('ตู้โชว์การ์ดเด่น', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                      TextButton.icon(onPressed: () => _go(const PinPickerScreen()), icon: const Icon(Icons.push_pin_outlined, size: 18), label: const Text('จัดการ')),
                    ]),
                    const SizedBox(height: 6),
                    Showcase(
                      pins: p.pins,
                      empty: 'ยังไม่ได้ปักหมุดการ์ด กด "จัดการ" เพื่อเลือกการ์ดที่ภูมิใจที่สุดได้สูงสุด 5 ใบ',
                      onTapCard: (c) => _go(CardDetailScreen(card: c)),
                    ),
                    const SizedBox(height: 22),
                    RegionProgressList(regions: p.stats.regions),
                  ],
                  const SizedBox(height: 22),
                  _menu(Icons.qr_code_2, 'QR โปรไฟล์ของฉัน', subtitle: 'ให้เพื่อนสแกนเพื่อส่ง/แลกการ์ด', onTap: () => _showMyQr(user?.username ?? '')),
                  _menu(Icons.swap_horiz, 'แลกเปลี่ยนการ์ด', subtitle: 'ข้อเสนอที่ได้รับ ส่งไป และประวัติ', onTap: () => _go(const TradesScreen())),
                  _menu(
                    Icons.notifications_outlined,
                    'การแจ้งเตือน',
                    trailing: _unread > 0 ? CircleAvatar(radius: 11, backgroundColor: Colors.red, child: Text('$_unread', style: const TextStyle(color: Colors.white, fontSize: 12))) : const Icon(Icons.chevron_right),
                    onTap: () => _go(const NotificationsScreen()),
                  ),
                  _menu(Icons.flag_outlined, 'ภารกิจของฉัน', subtitle: 'สร้างภารกิจ ติดตามสถานะ และดาวน์โหลด QR', onTap: () => _go(const MyQuestsScreen())),
                  _menu(Icons.public, 'โปรไฟล์ชุมชนของฉัน', subtitle: 'โพสต์ ผู้ติดตาม และตราสัญลักษณ์ ตามที่คนอื่นเห็น', onTap: () => _go(CommunityProfileScreen(username: user?.username ?? ''))),
                  _menu(Icons.manage_accounts_outlined, 'แก้ไขโปรไฟล์ชุมชน', subtitle: 'ชื่อที่แสดง รูป ภาพปก Bio และสวิตช์ตราสัญลักษณ์', onTap: () => _go(const EditCommunityProfileScreen())),
                  _menu(Icons.emoji_events_outlined, 'นักเที่ยวประจำเดือน', subtitle: 'อันดับผู้แท็กสถานที่ท่องเที่ยวมากที่สุดของเดือน', onTap: () => _go(const LeaderboardScreen())),
                  _menu(Icons.confirmation_number_outlined, 'การจองของฉัน', subtitle: 'ที่พัก เที่ยวบิน รถเช่า ดูสถานะและยกเลิกการจอง', onTap: () => _go(const MyBookingsScreen())),
                  _menu(Icons.storefront_outlined, 'ร้านค้าของฉัน', subtitle: 'ลงทะเบียนร้านพันธมิตร สิทธิประโยชน์การ์ด และติดตามสถานะ', onTap: () => _go(const MyShopsScreen())),
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: Icon(user?.hasFace == true ? Icons.face : Icons.face_retouching_off, color: user?.hasFace == true ? AppColors.success : Colors.orange),
                      title: Text(user?.hasFace == true ? 'ใบหน้าลงทะเบียนแล้ว' : 'ยังไม่ได้ลงทะเบียนใบหน้า'),
                      subtitle: Text(user?.hasFace == true ? 'แตะเพื่อสแกนใหม่' : 'จำเป็นสำหรับการเช็คอินที่ Kiosk'),
                      trailing: user?.hasFace == true
                          ? IconButton(icon: const Icon(Icons.delete_outline), tooltip: 'ลบข้อมูลใบหน้า', onPressed: _confirmDeleteFace)
                          : const Icon(Icons.chevron_right),
                      onTap: () => _go(const FaceEnrollScreen()),
                    ),
                  ),
                  if (user?.isAdmin == true) _menu(Icons.admin_panel_settings, 'จัดการสถานที่ (Admin)', onTap: () => _go(const AdminScreen())),
                  _menu(Icons.lock_outline, 'เปลี่ยนรหัสผ่าน', onTap: _changePassword),
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: const Icon(Icons.delete_forever_outlined, color: Colors.red),
                      title: const Text('ลบบัญชีของฉัน', style: TextStyle(color: Colors.red)),
                      subtitle: const Text('ลบข้อมูลส่วนตัวและข้อมูลใบหน้าถาวร'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: user?.isAdmin == true ? null : _deleteAccount,
                    ),
                  ),
                  const SizedBox(height: 16),
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
