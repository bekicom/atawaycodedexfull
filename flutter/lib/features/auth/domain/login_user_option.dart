class LoginUserOption {
  const LoginUserOption({required this.username, required this.role});

  final String username;
  final String role;

  String get roleLabel {
    switch (role.trim().toLowerCase()) {
      case 'admin':
        return 'Admin';
      default:
        return 'Kassir';
    }
  }

  String get displayLabel => '$username ($roleLabel)';

  factory LoginUserOption.fromJson(Map<String, dynamic> json) {
    return LoginUserOption(
      username: json['username']?.toString() ?? '',
      role: json['role']?.toString() ?? 'cashier',
    );
  }
}
