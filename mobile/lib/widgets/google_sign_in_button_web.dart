import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:google_sign_in_web/web_only.dart' as web;

const String _googleClientId = String.fromEnvironment('GOOGLE_CLIENT_ID');

Future<void>? _initFuture;

Future<void> _ensureInitialized() {
  return _initFuture ??= GoogleSignIn.instance.initialize(clientId: _googleClientId);
}

class GoogleSignInButton extends StatefulWidget {
  final Future<void> Function(String idToken) onIdToken;
  final void Function(String message) onError;
  const GoogleSignInButton({super.key, required this.onIdToken, required this.onError});

  @override
  State<GoogleSignInButton> createState() => _GoogleSignInButtonState();
}

class _GoogleSignInButtonState extends State<GoogleSignInButton> {
  StreamSubscription<GoogleSignInAuthenticationEvent>? _sub;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    if (_googleClientId.isEmpty) return;
    _ensureInitialized().then((_) {
      if (!mounted) return;
      _sub = GoogleSignIn.instance.authenticationEvents.listen(_onEvent, onError: (Object e) {
        widget.onError(e is GoogleSignInException ? 'เข้าสู่ระบบด้วย Google ไม่สำเร็จ (${e.code.name})' : 'เข้าสู่ระบบด้วย Google ไม่สำเร็จ');
      });
      setState(() => _ready = true);
    }).catchError((Object e) {
      widget.onError('เริ่มต้น Google Sign-In ไม่สำเร็จ: $e');
    });
  }

  Future<void> _onEvent(GoogleSignInAuthenticationEvent event) async {
    if (event is! GoogleSignInAuthenticationEventSignIn) return;
    final idToken = event.user.authentication.idToken;
    if (idToken == null) {
      widget.onError('ไม่ได้รับ token จาก Google');
      return;
    }
    await widget.onIdToken(idToken);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_googleClientId.isEmpty) {
      return const Text('ยังไม่ได้ตั้งค่า GOOGLE_CLIENT_ID สำหรับปุ่ม Google', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 12));
    }
    if (!_ready) return const SizedBox(height: 44, child: Center(child: SizedBox(height: 18, width: 18, child: CircularProgressIndicator(strokeWidth: 2))));
    return Center(
      child: SizedBox(
        height: 44,
        child: web.renderButton(configuration: web.GSIButtonConfiguration(type: web.GSIButtonType.standard, size: web.GSIButtonSize.large, text: web.GSIButtonText.continueWith, shape: web.GSIButtonShape.pill)),
      ),
    );
  }
}
