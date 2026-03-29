import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../screens/auth/auth_entry_screen.dart';
import '../services/navigation_return_snapshot.dart';
import '../theme/worka_colors.dart';
import 'account_store.dart';
import 'remembered_account.dart';

class AccountSwitcherScreen extends StatefulWidget {
  const AccountSwitcherScreen({super.key});

  @override
  State<AccountSwitcherScreen> createState() => _AccountSwitcherScreenState();
}

class _AccountSwitcherScreenState extends State<AccountSwitcherScreen> {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  bool _busy = false;
  List<RememberedAccount> _accounts = <RememberedAccount>[];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    NavigationReturnSnapshot.finishAccountSwitch();
    super.dispose();
  }

  Future<void> _load() async {
    final list = await AccountStore.loadAccounts();
    if (!mounted) return;
    setState(() => _accounts = list);
  }

  void _toast(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), backgroundColor: WorkaColors.textDark),
    );
  }

  String _initials(RememberedAccount a) {
    final name = (a.displayName ?? '').trim();
    if (name.isNotEmpty) {
      final parts = name
          .split(RegExp(r'\s+'))
          .where((e) => e.isNotEmpty)
          .toList();
      if (parts.length >= 2) {
        return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
      }
      return parts.first[0].toUpperCase();
    }
    final email = (a.email ?? '').trim();
    if (email.isNotEmpty) return email[0].toUpperCase();
    final phone = (a.phone ?? '').trim();
    if (phone.isNotEmpty) return phone.replaceAll('+', '').substring(0, 1);
    return 'U';
  }

  Future<void> _signOutOnly() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      debugPrint('[AUTH] signOut requested from AccountSwitcherScreen');
      await _auth.signOut();
    } catch (e) {
      _toast('Не удалось выйти: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openAddAccount() async {
    await _signOutOnly();
    if (!mounted) return;
    await Navigator.of(
      context,
      rootNavigator: true,
    ).push(MaterialPageRoute(builder: (_) => const AuthEntryScreen()));
    if (!mounted) return;
    if (_auth.currentUser != null && Navigator.of(context).canPop()) {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _switchTo(RememberedAccount account) async {
    if (_busy) return;
    final currentUid = _auth.currentUser?.uid;
    if (currentUid != null && currentUid == account.uid) {
      _toast('Этот аккаунт уже активен');
      return;
    }

    await _signOutOnly();
    if (!mounted) return;

    switch (account.provider) {
      case 'google':
      case 'facebook':
        _toast(
          'Продолжите вход через ${account.provider == 'google' ? 'Google' : 'Facebook'}',
        );
        break;
      default:
        break;
    }
    await Navigator.of(
      context,
      rootNavigator: true,
    ).push(MaterialPageRoute(builder: (_) => const AuthEntryScreen()));
    if (!mounted) return;
    final switchedUid = _auth.currentUser?.uid;
    if (switchedUid != null && switchedUid == account.uid) {
      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop(true);
      }
    }
  }

  Future<void> _remove(RememberedAccount account) async {
    await AccountStore.removeAccount(account.uid);
    if (!mounted) return;
    setState(() {
      _accounts.removeWhere((a) => a.uid == account.uid);
    });
  }

  @override
  Widget build(BuildContext context) {
    final currentUid = _auth.currentUser?.uid;
    RememberedAccount? current;
    for (final a in _accounts) {
      if (a.uid == currentUid) {
        current = a;
        break;
      }
    }
    final others = _accounts.where((a) => a.uid != currentUid).toList();

    return Scaffold(
      backgroundColor: WorkaColors.bg,
      appBar: AppBar(
        backgroundColor: WorkaColors.bg,
        surfaceTintColor: WorkaColors.bg,
        elevation: 0,
        title: const Text(
          'Сменить аккаунт',
          style: TextStyle(
            color: WorkaColors.textDark,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        children: [
          if (current != null) ...[
            const Text(
              'Текущий аккаунт',
              style: TextStyle(
                color: WorkaColors.textGreyDark,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            _AccountTile(
              initials: _initials(current),
              title: current.primaryLabel,
              subtitle: current.secondaryLabel,
              trailing: const Icon(Icons.check_circle, color: WorkaColors.blue),
              onTap: null,
            ),
            const SizedBox(height: 16),
          ],
          const Text(
            'Другие аккаунты',
            style: TextStyle(
              color: WorkaColors.textGreyDark,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          if (others.isEmpty)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: WorkaColors.fieldBorder),
              ),
              child: const Text(
                'Сохранённых аккаунтов пока нет',
                style: TextStyle(
                  color: WorkaColors.textGreyDark,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ...others.map(
            (a) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _AccountTile(
                initials: _initials(a),
                title: a.primaryLabel,
                subtitle: '${a.secondaryLabel} · ${a.provider}',
                trailing: IconButton(
                  tooltip: 'Удалить',
                  onPressed: () => _remove(a),
                  icon: const Icon(
                    Icons.delete_outline,
                    color: WorkaColors.textGreyDark,
                  ),
                ),
                onTap: () => _switchTo(a),
              ),
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 52,
            child: OutlinedButton.icon(
              onPressed: _busy ? null : _openAddAccount,
              icon: const Icon(Icons.person_add_alt_1_rounded),
              label: const Text(
                'Добавить аккаунт',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: WorkaColors.blue,
                side: const BorderSide(color: WorkaColors.blue),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: _busy ? null : _signOutOnly,
              style: ElevatedButton.styleFrom(
                backgroundColor: WorkaColors.orange,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text(
                'Выйти',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountTile extends StatelessWidget {
  final String initials;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _AccountTile({
    required this.initials,
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: WorkaColors.fieldBorder),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: WorkaColors.blue,
              ),
              child: Text(
                initials,
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
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: WorkaColors.textDark,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
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
            trailing ?? const SizedBox.shrink(),
          ],
        ),
      ),
    );
  }
}
