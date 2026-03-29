class UserProfile {
  final String uid;
  final String firstName;
  final String lastName;
  final String email;
  final String phone;

  const UserProfile({
    required this.uid,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.phone,
  });

  factory UserProfile.fromMap(Map<String, dynamic>? map, {String uid = ''}) {
    final data = map ?? const <String, dynamic>{};
    return UserProfile(
      uid: uid.trim(),
      firstName: (data['firstName'] ?? '').toString().trim(),
      lastName: (data['lastName'] ?? '').toString().trim(),
      email: (data['email'] ?? '').toString().trim(),
      phone: (data['phone'] ?? '').toString().trim(),
    );
  }
}
