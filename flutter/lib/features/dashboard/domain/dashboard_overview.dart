class DashboardOverview {
  const DashboardOverview({
    required this.message,
    required this.productsCount,
    required this.usersCount,
    required this.adminUsername,
    required this.adminRole,
  });

  final String message;
  final int productsCount;
  final int usersCount;
  final String adminUsername;
  final String adminRole;

  factory DashboardOverview.fromJson(Map<String, dynamic> json) {
    final stats = Map<String, dynamic>.from(
      (json['stats'] as Map?) ?? const {},
    );
    final admin = Map<String, dynamic>.from(
      (json['admin'] as Map?) ?? const {},
    );

    return DashboardOverview(
      message: json['message']?.toString() ?? '',
      productsCount: (stats['products'] as num?)?.toInt() ?? 0,
      usersCount: (stats['users'] as num?)?.toInt() ?? 0,
      adminUsername: admin['username']?.toString() ?? '-',
      adminRole: admin['role']?.toString() ?? '-',
    );
  }
}
