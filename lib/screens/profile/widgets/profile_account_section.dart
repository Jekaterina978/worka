part of 'package:worka/screens/profile_screen.dart';

class ProfileAccountSection extends StatelessWidget {
  const ProfileAccountSection({
    super.key,
    required this.displayNameWithAge,
    required this.profileTypeText,
    required this.privateAddress,
    required this.isBusiness,
    required this.menuCard,
    required this.creditsStateBlock,
  });

  final String displayNameWithAge;
  final String profileTypeText;
  final String privateAddress;
  final bool isBusiness;
  final Widget menuCard;
  final Widget creditsStateBlock;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 14),
        Text(
          displayNameWithAge,
          style: const TextStyle(
            color: Color(0xFF0C1C3F),
            fontWeight: FontWeight.w900,
            fontSize: 22,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          profileTypeText,
          style: const TextStyle(
            color: Color(0xFF5D6A85),
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        if (!isBusiness && privateAddress.isNotEmpty) ...[
          Text(
            privateAddress,
            style: const TextStyle(
              color: Color(0xFF3B4B70),
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
        ],
        menuCard,
        const SizedBox(height: 12),
        if (isBusiness) creditsStateBlock,
      ],
    );
  }
}
