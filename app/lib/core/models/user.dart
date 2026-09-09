import 'json.dart';

class AuthUser {
  const AuthUser({
    required this.id,
    required this.mobile,
    required this.role,
    this.name,
    this.email,
  });

  final int id;
  final String mobile;
  final String role; // 'customer' | 'driver'
  final String? name;
  final String? email;

  factory AuthUser.fromJson(Map<String, dynamic> j) => AuthUser(
        id: asInt(j['id']),
        mobile: j['mobile']?.toString() ?? '',
        role: j['role']?.toString() ?? 'customer',
        name: j['name']?.toString(),
        email: j['email']?.toString(),
      );
}
