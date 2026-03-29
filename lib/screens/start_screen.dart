import 'package:flutter/material.dart';
import 'dart:math' as math;

import '../account/account_store.dart';
import '../account/account_switcher_screen.dart';
import '../account/remembered_account.dart';
import '../services/app_mode.dart';
import '../services/user_role_prefs.dart';
import '../theme/worka_colors.dart';
import 'auth/auth_entry_screen.dart';
import 'app_shell.dart';
import 'employer/candidate_search_screen.dart';
import 'home_screen.dart';

enum UserRole { worker, employer }

class StartScreen extends StatefulWidget {
  final bool inShell;
  final bool autoOpenSearch;
  final UserRole initialRole;

  const StartScreen({
    super.key,
    this.inShell = false,
    this.autoOpenSearch = false,
    this.initialRole = UserRole.worker,
  });

  @override
  State<StartScreen> createState() => _StartScreenState();
}

class _StartScreenState extends State<StartScreen> {
  static const double _frameMaxWidth = 480;
  static const double _contentGap = 16.744;
  static const double _bottomPadding = 40;
  static const Color _ctaBg = Color(0xFFFF8A00);
  static const Color _ruleColor = Color(0xFFE5E7EB);

  late UserRole _role = widget.initialRole;
  bool _isRu = true;
  List<RememberedAccount> _rememberedAccounts = const [];
  bool _accountsLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadRememberedAccounts();
    if (widget.autoOpenSearch) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _openSearchDirect();
      });
    }
  }

  Future<void> _loadRememberedAccounts() async {
    final accounts = await AccountStore.loadAccounts();
    if (!mounted) return;
    setState(() {
      _rememberedAccounts = accounts;
      _accountsLoaded = true;
    });
  }

  void _openSearchDirect() {
    final Widget screen = (_role == UserRole.worker)
        ? const HomeScreen(testMode: true)
        : const CandidateSearchScreen();

    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  Future<void> _goStartSearch() async {
    await AppMode.setTestProfileEnabled(true);
    await UserRolePrefs.setSelectedRole(
      _role == UserRole.worker ? UserRolePrefs.worker : UserRolePrefs.employer,
    );
    AppMode.setMode(
      _role == UserRole.worker ? AccountMode.personal : AccountMode.business,
    );
    if (!mounted) return;

    final Widget homeRoot = (_role == UserRole.worker)
        ? const HomeScreen(testMode: true)
        : const CandidateSearchScreen();

    if (widget.inShell) {
      _openSearchDirect();
      return;
    }

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => AppShell(initialIndex: 0, homeRoot: homeRoot),
      ),
    );
  }

  Future<void> _openAuthChooser() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const AuthEntryScreen()));
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: WorkaColors.textDark),
    );
  }

  String _initials(RememberedAccount account) {
    final name = (account.displayName ?? '').trim();
    if (name.isNotEmpty) {
      final parts = name
          .split(RegExp(r'\s+'))
          .where((e) => e.trim().isNotEmpty)
          .toList();
      if (parts.length >= 2) {
        return '${parts.first.characters.first}${parts[1].characters.first}'
            .toUpperCase();
      }
      return parts.first.characters.first.toUpperCase();
    }
    final email = (account.email ?? '').trim();
    if (email.isNotEmpty) return email.characters.first.toUpperCase();
    final phone = (account.phone ?? '').trim();
    if (phone.isNotEmpty) {
      return phone.replaceAll('+', '').characters.first.toUpperCase();
    }
    return 'U';
  }

  Future<void> _continueAs(RememberedAccount account) async {
    switch (account.provider) {
      case 'google':
      case 'facebook':
        _toast('Вход через ${account.provider} скоро');
        break;
      default:
        break;
    }
    await _openAuthChooser();
    await _loadRememberedAccounts();
  }

  Widget _rememberedAccountsBlock(double width) {
    if (!_accountsLoaded || _rememberedAccounts.isEmpty) {
      return const SizedBox.shrink();
    }
    final visible = _rememberedAccounts.take(3).toList();
    final hasMore = _rememberedAccounts.length > visible.length;

    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Продолжить как',
            style: TextStyle(
              color: WorkaColors.textDark,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          ...visible.map(
            (a) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => _continueAs(a),
                child: Ink(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: WorkaColors.fieldBorder),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: WorkaColors.blue,
                        ),
                        child: Text(
                          _initials(a),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              a.primaryLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: WorkaColors.textDark,
                                fontWeight: FontWeight.w700,
                                fontSize: 14,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              a.secondaryLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: WorkaColors.textGreyDark,
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right_rounded,
                        color: WorkaColors.textGrey,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              TextButton(
                onPressed: _openAuthChooser,
                child: const Text(
                  'Добавить аккаунт',
                  style: TextStyle(
                    color: WorkaColors.blue,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (hasMore || _rememberedAccounts.isNotEmpty)
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const AccountSwitcherScreen(),
                    ),
                  ),
                  child: Text(
                    hasMore ? 'Ещё' : 'Управлять аккаунтами',
                    style: const TextStyle(
                      color: WorkaColors.textGreyDark,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: _frameMaxWidth),
                  child: LayoutBuilder(
                    builder: (context, c) {
                      final controlWidth = math.min(384.0, c.maxWidth - 40);
                      return Padding(
                        padding: const EdgeInsets.fromLTRB(
                          20,
                          64,
                          20,
                          _bottomPadding,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            SizedBox(
                              height: 68,
                              child: Image.asset(
                                'assets/logo.png',
                                fit: BoxFit.contain,
                              ),
                            ),
                            const SizedBox(height: _contentGap),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxHeight: 268),
                              child: Image.asset(
                                'assets/illustration.png',
                                fit: BoxFit.contain,
                              ),
                            ),
                            const SizedBox(height: _contentGap),
                            const Text(
                              'Работа рядом\nи по всему миру',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 34,
                                fontWeight: FontWeight.w800,
                                height: 1.12,
                                color: WorkaColors.title,
                              ),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              'Вакансии и специалисты\nдля удалёнки и локально',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w500,
                                height: 1.32,
                                color: WorkaColors.subtitle,
                              ),
                            ),
                            const SizedBox(height: _contentGap),
                            _RoleSlider(
                              value: _role,
                              onChanged: (r) => setState(() {
                                _role = r;
                                UserRolePrefs.setSelectedRole(
                                  r == UserRole.worker
                                      ? UserRolePrefs.worker
                                      : UserRolePrefs.employer,
                                );
                                AppMode.setMode(
                                  r == UserRole.worker
                                      ? AccountMode.personal
                                      : AccountMode.business,
                                );
                              }),
                              height: 65,
                              width: controlWidth,
                            ),
                            const SizedBox(height: _contentGap),
                            SizedBox(
                              width: controlWidth,
                              height: 65,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: _ctaBg,
                                  borderRadius: BorderRadius.circular(9999),
                                  boxShadow: const [
                                    BoxShadow(
                                      color: Color.fromRGBO(0, 0, 0, 0.15),
                                      blurRadius: 6.47,
                                      offset: Offset(0, 6.47),
                                    ),
                                    BoxShadow(
                                      color: Color.fromRGBO(0, 0, 0, 0.12),
                                      blurRadius: 22.644,
                                      offset: Offset(0, 6.47),
                                    ),
                                  ],
                                ),
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: _goStartSearch,
                                    borderRadius: BorderRadius.circular(9999),
                                    child: const Padding(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 38.818,
                                      ),
                                      child: Align(
                                        alignment: Alignment.center,
                                        child: Text(
                                          'Начать поиск',
                                          style: TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w500,
                                            fontSize: 22.644,
                                            height: 1.2,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: _contentGap),
                            const Text(
                              'Новые вакансии каждый день',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 21.149,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF9CA3AF),
                                height: 1.4,
                              ),
                            ),
                            const SizedBox(height: _contentGap),
                            Container(width: 306, height: 2, color: _ruleColor),
                            const SizedBox(height: _contentGap),
                            _rememberedAccountsBlock(controlWidth),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                InkWell(
                                  onTap: _openAuthChooser,
                                  child: const Text(
                                    'Войти',
                                    style: TextStyle(
                                      color: Color(0xFF6B7280),
                                      fontWeight: FontWeight.w400,
                                      fontSize: 20,
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                                const Text(
                                  '  •  ',
                                  style: TextStyle(
                                    color: Color(0xFF6B7280),
                                    fontWeight: FontWeight.w400,
                                    fontSize: 20,
                                    height: 1.4,
                                  ),
                                ),
                                InkWell(
                                  onTap: _openAuthChooser,
                                  child: const Text(
                                    'Создать аккаунт',
                                    style: TextStyle(
                                      color: Color(0xFF3B82F6),
                                      fontWeight: FontWeight.w400,
                                      fontSize: 20,
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                InkWell(
                                  borderRadius: BorderRadius.circular(8),
                                  onTap: () => setState(() => _isRu = true),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    child: Text(
                                      'RU',
                                      style: TextStyle(
                                        color: _isRu
                                            ? const Color(0xFF6B7280)
                                            : const Color(0xFF9CA3AF),
                                        fontWeight: _isRu
                                            ? FontWeight.w400
                                            : FontWeight.w500,
                                        fontSize: 20,
                                        height: 1.4,
                                      ),
                                    ),
                                  ),
                                ),
                                const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 6),
                                  child: Text(
                                    '|',
                                    style: TextStyle(
                                      color: Color(0xFF9CA3AF),
                                      fontWeight: FontWeight.w500,
                                      fontSize: 20,
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                                InkWell(
                                  borderRadius: BorderRadius.circular(8),
                                  onTap: () => setState(() => _isRu = false),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    child: Text(
                                      'EN',
                                      style: TextStyle(
                                        color: !_isRu
                                            ? const Color(0xFF6B7280)
                                            : const Color(0xFF9CA3AF),
                                        fontWeight: !_isRu
                                            ? FontWeight.w400
                                            : FontWeight.w500,
                                        fontSize: 20,
                                        height: 1.4,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Container(
                height: 96,
                width: double.infinity,
                color: Colors.white,
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleSlider extends StatelessWidget {
  final UserRole value;
  final ValueChanged<UserRole> onChanged;
  final double height;
  final double width;

  const _RoleSlider({
    required this.value,
    required this.onChanged,
    required this.height,
    required this.width,
  });

  @override
  Widget build(BuildContext context) {
    final isWorker = value == UserRole.worker;
    final halfWidth = width / 2;

    return SizedBox(
      width: width,
      height: height,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: const Color(0xFFEAEFF4),
          borderRadius: BorderRadius.circular(9999),
          boxShadow: const [
            BoxShadow(
              color: Color.fromRGBO(0, 0, 0, 0.15),
              blurRadius: 6.47,
              offset: Offset(0, 6.47),
            ),
          ],
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            AnimatedAlign(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              alignment: isWorker
                  ? Alignment.centerLeft
                  : Alignment.centerRight,
              child: SizedBox(
                width: halfWidth,
                height: height,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFF3B82F6),
                    borderRadius: BorderRadius.circular(9999),
                  ),
                ),
              ),
            ),
            Row(
              children: [
                SizedBox(
                  width: halfWidth,
                  height: height,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(9999),
                    onTap: () => onChanged(UserRole.worker),
                    child: Align(
                      alignment: Alignment.center,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'Работник',
                          style: TextStyle(
                            fontSize: 22.644,
                            fontWeight: FontWeight.w500,
                            height: 1.2,
                            color: isWorker
                                ? Colors.white
                                : const Color(0xFF6B7280),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: halfWidth,
                  height: height,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(9999),
                    onTap: () => onChanged(UserRole.employer),
                    child: Align(
                      alignment: Alignment.center,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          'Работодатель',
                          style: TextStyle(
                            fontSize: 22.644,
                            fontWeight: FontWeight.w500,
                            height: 1.2,
                            color: !isWorker
                                ? Colors.white
                                : const Color(0xFF6B7280),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
