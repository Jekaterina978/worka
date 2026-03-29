part of 'package:worka/screens/profile_screen.dart';

class _ProfileAvatar extends StatelessWidget {
  const _ProfileAvatar({
    required this.radius,
    required this.initials,
    this.isBusiness = false,
    this.avatarUrl,
    this.gender = _AvatarGender.unknown,
  });

  final double radius;
  final String initials;
  final bool isBusiness;
  final String? avatarUrl;
  final _AvatarGender gender;

  String? _sanitizeAvatarUrl(String? raw) {
    final value = (raw ?? '').trim();
    if (value.isEmpty) return null;
    final normalized = value.toLowerCase();
    const invalid = <String>{'', '-', 'null', 'undefined', 'n/a', 'placeholder'};
    if (invalid.contains(normalized)) return null;
    final uri = Uri.tryParse(value);
    if (uri == null) return null;
    final isHttp = uri.scheme == 'http' || uri.scheme == 'https';
    if (!isHttp || uri.host.trim().isEmpty) return null;
    return value;
  }

  @override
  Widget build(BuildContext context) {
    final size = radius * 2;
    final fallbackFontSize = (size * 0.33).clamp(14.0, 30.0).toDouble();
    final imageUrl = _sanitizeAvatarUrl(avatarUrl);
    final hasNetworkAvatar = imageUrl != null;
    final String? genderAsset = !isBusiness
        ? switch (gender) {
            _AvatarGender.female => 'assets/avatars/female.png',
            _AvatarGender.male => 'assets/avatars/male.png',
            _AvatarGender.unknown => null,
          }
        : null;

    Widget initialsFallback() {
      return Center(
        child: Text(
          initials,
          style: TextStyle(
            color: const Color(0xFF4A6FDB),
            fontSize: fallbackFontSize,
            fontWeight: FontWeight.w900,
          ),
        ),
      );
    }

    Widget privateFallback() {
      if (genderAsset != null) {
        return _genderAssetImage(genderAsset, width: size, height: size);
      }
      return initialsFallback();
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFFEAF0FF),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipOval(
        child: hasNetworkAvatar
            ? Image.network(
                imageUrl,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => isBusiness ? _buildBusinessAvatar(size) : privateFallback(),
              )
            : (isBusiness ? _buildBusinessAvatar(size) : privateFallback()),
      ),
    );
  }

  Widget _genderAssetImage(String asset, {double width = 80, double height = 80}) {
    return Image.asset(asset, width: width, height: height, fit: BoxFit.cover);
  }

  Widget _buildBusinessAvatar(double size) {
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        color: Color(0xFFEEF3FF),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Icon(
          Icons.business_rounded,
          size: size * 0.48,
          color: const Color(0xFF4A6FDB),
        ),
      ),
    );
  }

}
