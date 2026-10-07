import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/app_state.dart';
import '../services/api_client.dart';
import '../widgets/face_capture_widget.dart';
import '../widgets/google_sign_in_button.dart';
import 'home_shell.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullName = TextEditingController();
  final _phone = TextEditingController();
  final _email = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();

  FaceCapture? _face;
  bool _loading = false;
  String? _error;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final face = _face;
    if (face == null) {
      setState(() => _error = 'กรุณาสแกนใบหน้าก่อนสมัคร (ใช้ยืนยันตัวตนตอนเช็คอิน)');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final nameParts = _fullName.text.trim().split(RegExp(r'\s+'));
    final firstName = nameParts.isNotEmpty ? nameParts.first : _fullName.text;
    final lastName = nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '-';

    try {
      await context.read<AppState>().register(
            username: _username.text.trim(),
            password: _password.text,
            firstName: firstName,
            lastName: lastName,
            email: _email.text.trim(),
            phone: _phone.text.trim(),
            faceDescriptor: face.descriptor,
          );
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const HomeShell()), (route) => false);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'เชื่อมต่อเซิร์ฟเวอร์ไม่ได้ ตรวจสอบว่า backend รันอยู่');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _googleSignUp(String idToken) async {
    try {
      await context.read<AppState>().loginWithGoogle(idToken);
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const HomeShell()), (route) => false);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (e) {
      if (mounted) setState(() => _error = 'เชื่อมต่อเซิร์ฟเวอร์ไม่ได้ ตรวจสอบว่า backend รันอยู่');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Travel Registration')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GoogleSignInButton(onIdToken: _googleSignUp, onError: (m) => setState(() => _error = m)),
                const SizedBox(height: 12),
                const Row(children: [
                  Expanded(child: Divider()),
                  Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text('หรือสมัครด้วยอีเมล', style: TextStyle(color: Colors.grey, fontSize: 12))),
                  Expanded(child: Divider()),
                ]),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _fullName,
                  decoration: const InputDecoration(labelText: 'Full Name'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'กรอกชื่อ-นามสกุล' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Phone Number'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'กรอกเบอร์โทรศัพท์' : null,
                ),
                const SizedBox(height: 20),
                Center(
                  child: Column(
                    children: [
                      const Text('สแกนใบหน้าเพื่อใช้ยืนยันตัวตนตอนเช็คอิน', style: TextStyle(fontWeight: FontWeight.w500)),
                      const SizedBox(height: 10),
                      FaceCaptureWidget(onChanged: (c) => setState(() => _face = c)),
                      const SizedBox(height: 6),
                      const Text(
                        'การสมัครถือว่าคุณยินยอมให้จัดเก็บข้อมูลลักษณะใบหน้า (ข้อมูลส่วนบุคคลที่อ่อนไหว) เพื่อการยืนยันตัวตนเท่านั้น โดยไม่เก็บรูปถ่ายของคุณ',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email'),
                  validator: (v) => (v == null || !v.contains('@')) ? 'กรอกอีเมลให้ถูกต้อง' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _username,
                  decoration: const InputDecoration(labelText: 'Username'),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'กรอก Username' : null,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _password,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Password'),
                  validator: (v) => (v == null || v.length < 6) ? 'Password อย่างน้อย 6 ตัวอักษร' : null,
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: Colors.red)),
                ],
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: _loading ? null : _submit,
                  child: _loading
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Create Account'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
