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

  void logout() {
    apiClient.token = null;
    currentUser = null;
    stats = null;
    notifyListeners();
  }
}
