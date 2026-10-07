import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'services/api_client.dart';
import 'services/app_state.dart';
import 'screens/login_screen.dart';
import 'theme.dart';

final _navigatorKey = GlobalKey<NavigatorState>();
final _messengerKey = GlobalKey<ScaffoldMessengerState>();

void main() {
  runApp(const TravelCardApp());
}

class TravelCardApp extends StatefulWidget {
  const TravelCardApp({super.key});

  @override
  State<TravelCardApp> createState() => _TravelCardAppState();
}

class _TravelCardAppState extends State<TravelCardApp> {
  final _appState = AppState();
  bool _handlingExpiry = false;

  @override
  void initState() {
    super.initState();
    // One place for every expired or ended session: forget it and go back to the login screen.
    apiClient.onUnauthorized = () {
      if (_handlingExpiry) return;
      _handlingExpiry = true;
      _appState.logout(callServer: false);
      _navigatorKey.currentState?.pushAndRemoveUntil(MaterialPageRoute(builder: (_) => const LoginScreen()), (route) => false);
      _messengerKey.currentState?.showSnackBar(const SnackBar(content: Text('หมดเวลาการเข้าสู่ระบบ กรุณาเข้าสู่ระบบใหม่')));
      Future.delayed(const Duration(seconds: 2), () => _handlingExpiry = false);
    };
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _appState,
      child: MaterialApp(
        title: 'Limited Travel Card',
        debugShowCheckedModeBanner: false,
        navigatorKey: _navigatorKey,
        scaffoldMessengerKey: _messengerKey,
        theme: buildAppTheme(),
        home: const LoginScreen(),
      ),
    );
  }
}
