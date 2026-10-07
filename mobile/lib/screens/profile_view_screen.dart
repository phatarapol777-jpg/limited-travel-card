import 'package:flutter/material.dart';
import 'community_profile_screen.dart';

/// Another traveler's page (kept under its old name for the places that open it by username, such as the profile QR scan).
class ProfileViewScreen extends StatelessWidget {
  final String username;
  const ProfileViewScreen({super.key, required this.username});

  @override
  Widget build(BuildContext context) => CommunityProfileScreen(username: username);
}
