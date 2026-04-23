import 'dart:convert';

import 'app_user.dart';

class Session {
  const Session({required this.token, required this.user});

  final String token;
  final AppUser user;

  factory Session.fromJson(Map<String, dynamic> json) {
    return Session(
      token: json['token']?.toString() ?? '',
      user: AppUser.fromJson(Map<String, dynamic>.from(json['user'] as Map)),
    );
  }

  factory Session.fromStorage(String token, String userJson) {
    return Session(
      token: token,
      user: AppUser.fromJson(
        Map<String, dynamic>.from(jsonDecode(userJson) as Map),
      ),
    );
  }
}
