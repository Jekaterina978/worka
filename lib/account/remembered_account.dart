class RememberedAccount {
  final String uid;
  final String? email;
  final String? phone;
  final String provider; // password | phone | google | facebook | unknown
  final String? displayName;
  final DateTime lastUsed;

  const RememberedAccount({
    required this.uid,
    required this.provider,
    required this.lastUsed,
    this.email,
    this.phone,
    this.displayName,
  });

  String get primaryLabel {
    final name = (displayName ?? '').trim();
    if (name.isNotEmpty) return name;
    final mail = (email ?? '').trim();
    if (mail.isNotEmpty) return mail;
    final tel = (phone ?? '').trim();
    if (tel.isNotEmpty) return tel;
    return uid;
  }

  String get secondaryLabel {
    final mail = (email ?? '').trim();
    final tel = (phone ?? '').trim();
    if (mail.isNotEmpty && tel.isNotEmpty) return '$mail · $tel';
    if (mail.isNotEmpty) return mail;
    if (tel.isNotEmpty) return tel;
    return provider;
  }

  String get stableKey {
    final mail = (email ?? '').trim().toLowerCase();
    final tel = (phone ?? '').trim();
    if (mail.isNotEmpty) return 'email:$mail';
    if (tel.isNotEmpty) return 'phone:$tel';
    return 'uid:$uid';
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'uid': uid,
      'email': email,
      'phone': phone,
      'provider': provider,
      'displayName': displayName,
      'lastUsed': lastUsed.toIso8601String(),
    };
  }

  static RememberedAccount? fromJson(Map<String, dynamic> json) {
    final uid = (json['uid'] ?? '').toString().trim();
    if (uid.isEmpty) return null;
    final provider = (json['provider'] ?? 'unknown').toString().trim();
    final raw = (json['lastUsed'] ?? '').toString().trim();
    final parsed =
        DateTime.tryParse(raw) ?? DateTime.fromMillisecondsSinceEpoch(0);
    return RememberedAccount(
      uid: uid,
      email: (json['email'] ?? '').toString().trim().isEmpty
          ? null
          : (json['email'] ?? '').toString().trim(),
      phone: (json['phone'] ?? '').toString().trim().isEmpty
          ? null
          : (json['phone'] ?? '').toString().trim(),
      provider: provider.isEmpty ? 'unknown' : provider,
      displayName: (json['displayName'] ?? '').toString().trim().isEmpty
          ? null
          : (json['displayName'] ?? '').toString().trim(),
      lastUsed: parsed,
    );
  }

  RememberedAccount copyWith({
    String? uid,
    String? email,
    String? phone,
    String? provider,
    String? displayName,
    DateTime? lastUsed,
  }) {
    return RememberedAccount(
      uid: uid ?? this.uid,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      provider: provider ?? this.provider,
      displayName: displayName ?? this.displayName,
      lastUsed: lastUsed ?? this.lastUsed,
    );
  }
}
