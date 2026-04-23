import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/login_user_option.dart';
import '../domain/session.dart';

class AuthRepository {
  AuthRepository(this._dio);

  final Dio _dio;

  static const _tokenKey = 'token';
  static const _userKey = 'user';

  Future<Session?> restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenKey);
    final userJson = prefs.getString(_userKey);

    if (token == null ||
        token.isEmpty ||
        userJson == null ||
        userJson.isEmpty) {
      return null;
    }

    return Session.fromStorage(token, userJson);
  }

  Future<List<LoginUserOption>> fetchLoginUsers() async {
    final response = await _dio.get<Map<String, dynamic>>('/auth/login-users');
    final rawUsers = (response.data?['users'] as List?) ?? const [];

    return rawUsers
        .map(
          (item) =>
              LoginUserOption.fromJson(Map<String, dynamic>.from(item as Map)),
        )
        .where((user) => user.username.trim().isNotEmpty)
        .toList();
  }

  Future<Session> login({
    required String username,
    required String password,
    String tenantSlug = '',
  }) async {
    final response = await _dio.post<Map<String, dynamic>>(
      '/auth/login',
      data: {
        'username': username.trim(),
        'password': password,
        if (tenantSlug.trim().isNotEmpty) 'tenantSlug': tenantSlug.trim(),
      },
    );

    final session = Session.fromJson(response.data ?? const {});
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_tokenKey, session.token);
    await prefs.setString(_userKey, jsonEncode(session.user.toJson()));
    return session;
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_tokenKey);
    await prefs.remove(_userKey);
  }
}
