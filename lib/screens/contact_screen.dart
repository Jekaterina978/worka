import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../theme/worka_colors.dart';
import '../widgets/burger_drawer.dart';
import '../widgets/profile_avatar_button.dart';
import 'support/support_chat_screen.dart';

class ContactScreen extends StatefulWidget {
  const ContactScreen({super.key});

  @override
  State<ContactScreen> createState() => _ContactScreenState();
}

class _ContactScreenState extends State<ContactScreen> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();
  String _selectedTopic = '';

  static const _topics = <_TopicItem>[
    _TopicItem('Ошибка в приложении', Icons.settings_outlined),
    _TopicItem('Проблема с аккаунтом', Icons.lock_outline_rounded),
    _TopicItem('Вопрос по вакансии', Icons.work_outline_rounded),
    _TopicItem('Предложение', Icons.lightbulb_outline_rounded),
  ];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _messageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF4A6FDB),
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          // Gradient background visible behind header row
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF4A6FDB), Color(0xFF5A80FF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header row
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 8, 4, 12),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () =>
                            BurgerDrawer.open(context, testMode: true),
                        icon: const Icon(
                          Icons.menu_rounded,
                          color: Colors.white,
                        ),
                      ),
                      const Expanded(
                        child: Text(
                          'Контакт',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ),
                      const ProfileAvatarButton(testMode: true),
                    ],
                  ),
                ),
                // Content card with top border radius (creates "card over header" effect)
                Expanded(
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(24),
                        topRight: Radius.circular(24),
                      ),
                    ),
                    child: ClipRRect(
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(24),
                        topRight: Radius.circular(24),
                      ),
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(16, 24, 16, 120),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Напишите нам',
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w300,
                                color: Color(0xFF000000),
                              ),
                            ),
                            const SizedBox(height: 16),
                            // Input fields — each as a separate box
                            Column(
                              children: [
                                _inputBox(
                                  controller: _nameCtrl,
                                  hint: 'Имя',
                                  icon: Icons.person_outline_rounded,
                                ),
                                const SizedBox(height: 10),
                                _inputBox(
                                  controller: _emailCtrl,
                                  hint: 'Эл. почта',
                                  icon: Icons.mail_outline_rounded,
                                  keyboardType: TextInputType.emailAddress,
                                  iconColor: const Color(0xFFFF8904),
                                ),
                                const SizedBox(height: 10),
                                _inputBox(
                                  controller: _phoneCtrl,
                                  hint: 'Телефон',
                                  icon: Icons.phone_outlined,
                                  keyboardType: TextInputType.phone,
                                ),
                              ],
                            ),
                            const SizedBox(height: 18),
                            const Text(
                              'Тема',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF000000),
                              ),
                            ),
                            const SizedBox(height: 10),
                            // Chips: 2 columns, fixed 45px height
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final chipWidth =
                                    (constraints.maxWidth - 8) / 2;
                                return Column(
                                  children: [
                                    Row(
                                      children: [
                                        SizedBox(
                                          width: chipWidth,
                                          height: 45,
                                          child: _buildChip(_topics[0]),
                                        ),
                                        const SizedBox(width: 8),
                                        SizedBox(
                                          width: chipWidth,
                                          height: 45,
                                          child: _buildChip(_topics[1]),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        SizedBox(
                                          width: chipWidth,
                                          height: 45,
                                          child: _buildChip(_topics[2]),
                                        ),
                                        const SizedBox(width: 8),
                                        SizedBox(
                                          width: chipWidth,
                                          height: 45,
                                          child: _buildChip(_topics[3]),
                                        ),
                                      ],
                                    ),
                                  ],
                                );
                              },
                            ),
                            const SizedBox(height: 18),
                            const Text(
                              'Сообщение',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF000000),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Container(
                              height: 150,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 14,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.06),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: TextField(
                                controller: _messageCtrl,
                                maxLines: null,
                                expands: true,
                                decoration: const InputDecoration(
                                  hintText: 'Опишите свою проблему',
                                  hintStyle: TextStyle(
                                    color: Color(0xFF99A1AF),
                                    fontStyle: FontStyle.italic,
                                  ),
                                  border: InputBorder.none,
                                  enabledBorder: InputBorder.none,
                                  focusedBorder: InputBorder.none,
                                  isDense: true,
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Center(
                              child: SizedBox(
                                width: 340.0,
                                height: 48,
                                child: ElevatedButton(
                                  onPressed: () {},
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFFFF8904),
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(25),
                                    ),
                                    elevation: 2,
                                    shadowColor: const Color(
                                      0xFFFF8904,
                                    ).withValues(alpha: 0.3),
                                    textStyle: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15,
                                    ),
                                  ),
                                  child: const Text('Отправить сообщение'),
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            const Text(
                              'Связаться напрямую',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF000000),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Column(
                              children: [
                                _simpleContactCard(
                                  'Чат поддержки',
                                  () => Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => const SupportChatScreen(),
                                    ),
                                  ),
                                  outlined: true,
                                  backgroundColor: WorkaColors.blue,
                                  icon: const Icon(
                                    Icons.chat_bubble_outline_rounded,
                                    size: 22,
                                    color: WorkaColors.blue,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                _simpleContactCard(
                                  'Telegram',
                                  () {},
                                  backgroundColor: const Color(0xFF229ED9),
                                  icon: const FaIcon(
                                    FontAwesomeIcons.telegram,
                                    size: 28,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                _simpleContactCard(
                                  'WhatsApp',
                                  () {},
                                  backgroundColor: const Color(0xFF25D366),
                                  icon: const FaIcon(
                                    FontAwesomeIcons.whatsapp,
                                    size: 28,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                _simpleContactCard(
                                  'Viber',
                                  () {},
                                  backgroundColor: const Color(0xFF7360F2),
                                  icon: const FaIcon(
                                    FontAwesomeIcons.viber,
                                    size: 28,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                _simpleContactCard(
                                  'Email',
                                  () {},
                                  outlined: true,
                                  backgroundColor: const Color(0xFFFF8A00),
                                  icon: const Icon(
                                    Icons.mail_outline_rounded,
                                    size: 22,
                                    color: WorkaColors.blue,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChip(_TopicItem item) {
    final selected = _selectedTopic == item.title;
    return GestureDetector(
      onTap: () => setState(() => _selectedTopic = item.title),
      child: Container(
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFE6EFFF) : const Color(0xFFEEF4FF),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? const Color(0xFFC7D9FF) : const Color(0xFFD8E5FF),
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF4A6FDB).withValues(alpha: 0.18),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(item.icon, size: 16, color: const Color(0xFF3F6FE5)),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  item.title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF3F6FE5),
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _inputBox({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    Color iconColor = const Color(0xFF3F6FE5),
  }) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE5E5EA)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: iconColor),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: controller,
              keyboardType: keyboardType,
              style: const TextStyle(fontSize: 15, color: Color(0xFF101828)),
              decoration: InputDecoration(
                hintText: hint,
                hintStyle: const TextStyle(
                  color: Color(0xFF667085),
                  fontWeight: FontWeight.w600,
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                isDense: true,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _simpleContactCard(
    String title,
    VoidCallback onTap, {
    required Widget icon,
    required Color backgroundColor,
    bool outlined = false,
  }) {
    final isLightBlueAction = outlined;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 50,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: isLightBlueAction ? const Color(0xFFEEF4FF) : backgroundColor,
          borderRadius: BorderRadius.circular(16),
          border: null,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(
                alpha: isLightBlueAction ? 0.13 : 0.18,
              ),
              blurRadius: isLightBlueAction ? 12 : 10,
              offset: isLightBlueAction
                  ? const Offset(0, 5)
                  : const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            SizedBox(width: 20, child: Center(child: icon)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: isLightBlueAction ? WorkaColors.blue : Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopicItem {
  final String title;
  final IconData icon;
  const _TopicItem(this.title, this.icon);
}
