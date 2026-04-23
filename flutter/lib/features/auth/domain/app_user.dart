class AppUser {
  const AppUser({
    required this.id,
    required this.username,
    required this.role,
    this.tenantId,
    this.tenantSlug,
  });

  final String id;
  final String username;
  final String role;
  final String? tenantId;
  final String? tenantSlug;

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: json['id']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      role: json['role']?.toString() ?? 'cashier',
      tenantId: json['tenantId']?.toString(),
      tenantSlug: json['tenantSlug']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'role': role,
      'tenantId': tenantId,
      'tenantSlug': tenantSlug,
    };
  }
}

extension AppUserRoleX on AppUser {
  bool get isCashier {
    final normalized = role.trim().toLowerCase();
    return normalized == 'cashier' || normalized == 'kassa';
  }
}
