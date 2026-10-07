import 'package:flutter/material.dart';
import '../models/models.dart';
import 'api_client.dart';

class AppState extends ChangeNotifier {
  AppUser? currentUser;
  UserStats? stats;
  bool get isLoggedIn => currentUser != null && apiClient.token != null;

  Future<void> register({
    required String username,
    required String password,
    required String firstName,
    required String lastName,
    required String email,
    required String phone,
    required List<double> faceDescriptor,
  }) async {
    final data = await apiClient.post('/auth/register', {
      'username': username,
      'password': password,
      'first_name': firstName,
      'last_name': lastName,
      'email': email,
      'phone': phone,
      'face_descriptor': faceDescriptor,
    });
    apiClient.token = data['token'];
    currentUser = AppUser.fromJson(data['user']);
    await refreshStats();
    notifyListeners();
  }

  Future<void> login(String username, String password) async {
    final data = await apiClient.post('/auth/login', {'username': username, 'password': password});
    apiClient.token = data['token'];
    currentUser = AppUser.fromJson(data['user']);
    await refreshStats();
    notifyListeners();
  }

  Future<void> loginWithGoogle(String idToken) async {
    final data = await apiClient.post('/auth/google', {'id_token': idToken});
    apiClient.token = data['token'];
    currentUser = AppUser.fromJson(data['user']);
    await refreshStats();
    notifyListeners();
  }

  Future<void> saveFace(List<double> faceDescriptor) async {
    await apiClient.put('/auth/face', {'face_descriptor': faceDescriptor});
    await refreshStats();
  }

  Future<void> deleteFace() async {
    await apiClient.delete('/auth/face');
    await refreshStats();
  }

  Future<void> refreshStats() async {
    final data = await apiClient.get('/auth/me');
    currentUser = AppUser.fromJson(data['user']);
    stats = UserStats.fromJson(data['stats']);
    notifyListeners();
  }

  Future<void> changePassword(String current, String next) async {
    await apiClient.post('/auth/change-password', {'current_password': current, 'new_password': next});
    await refreshStats();
  }

  /// Anonymises the account on the server, then signs out here.
  Future<void> deleteAccount(String confirmUsername) async {
    await apiClient.post('/auth/delete-account', {'confirm_username': confirmUsername});
    logout(callServer: false);
  }

  /// Signs out. By default the server is told too (best effort) so the token stops working everywhere.
  void logout({bool callServer = true}) {
    if (callServer && apiClient.token != null) {
      apiClient.post('/auth/logout', {}).catchError((_) => null);
    }
    apiClient.token = null;
    currentUser = null;
    stats = null;
    notifyListeners();
  }
}
