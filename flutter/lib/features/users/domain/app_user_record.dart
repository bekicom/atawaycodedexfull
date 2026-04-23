class AppUserRecord {
  const AppUserRecord({
    required this.id,
    required this.username,
    required this.role,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String username;
  final String role;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get roleLabel {
    switch (role.trim().toLowerCase()) {
      case 'admin':
        return 'Admin';
      default:
        return 'Kassir';
    }
  }

  factory AppUserRecord.fromJson(Map<String, dynamic> json) {
    return AppUserRecord(
      id: json['_id']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      role: json['role']?.toString() ?? 'cashier',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? ''),
      updatedAt: DateTime.tryParse(json['updatedAt']?.toString() ?? ''),
    );
  }
}
