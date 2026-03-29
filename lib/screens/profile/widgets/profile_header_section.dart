part of 'package:worka/screens/profile_screen.dart';

class ProfileHeaderSection extends StatelessWidget {
  const ProfileHeaderSection({
    super.key,
    required this.leading,
    required this.body,
    this.backgroundColor = const Color(0xFF4A6FDB),
  });

  final Widget leading;
  final Widget body;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      body: WorkaStandardScreenLayout(
        header: WorkaHeader(title: 'Профиль', leading: leading),
        headerPadding: EdgeInsets.zero,
        body: body,
      ),
    );
  }
}
