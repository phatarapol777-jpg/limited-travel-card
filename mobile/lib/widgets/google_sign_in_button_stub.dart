import 'package:flutter/material.dart';

class GoogleSignInButton extends StatelessWidget {
  final Future<void> Function(String idToken) onIdToken;
  final void Function(String message) onError;
  const GoogleSignInButton({super.key, required this.onIdToken, required this.onError});

  @override
  Widget build(BuildContext context) {
    return const Text('การเข้าสู่ระบบด้วย Google รองรับเฉพาะบนเว็บ', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 12));
  }
}
