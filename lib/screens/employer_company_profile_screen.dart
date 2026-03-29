import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:worka/theme/worka_colors.dart';
import 'package:worka/services/app_mode.dart';
import 'package:worka/services/effective_uid.dart';
import 'package:worka/services/navigation_return_snapshot.dart';
import 'package:worka/screens/edit_account_screen.dart';
import 'package:worka/widgets/worka_header.dart';
import 'package:worka/features/payments/screens/contact_unlock_paywall_sheet.dart';
import 'package:worka/services/ownership_context.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class EmployerCompanyProfileScreen extends StatefulWidget {
  final String? initialEmployerType;

  const EmployerCompanyProfileScreen({super.key, this.initialEmployerType});

  @override
  State<EmployerCompanyProfileScreen> createState() =>
      _EmployerCompanyProfileScreenState();
}

class _EmployerCompanyProfileScreenState
    extends State<EmployerCompanyProfileScreen> {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final OwnershipContext _ownership = OwnershipContext();

  final _company = TextEditingController();
  final _reg = TextEditingController();
  final _site = TextEditingController();

  bool _saving = false;
  bool _loadedOnce = false;
  String? _resolvedUid;

  @override
  void dispose() {
    _company.dispose();
    _reg.dispose();
    _site.dispose();
    super.dispose();
  }

  void _toast(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(t), backgroundColor: WorkaColors.textDark),
    );
  }

  DocumentReference<Map<String, dynamic>> _meRef(String uid) =>
      _db.collection('users').doc(uid);

  String _s(dynamic v) => (v ?? '').toString().trim();

  Set<String> _rolesFromUserDoc(Map<String, dynamic> data) {
    final roles = <String>{};
    final rawRoles = data['roles'];
    if (rawRoles is Iterable) {
      for (final item in rawRoles) {
        final v = (item ?? '').toString().trim().toLowerCase();
        if (v.isNotEmpty) roles.add(v);
      }
    }
    final role = _s(data['role']).toLowerCase();
    if (role == 'worker') roles.add('worker');
    if (role == 'employer') roles.add('employer_private');
    if (role == 'employer_private' || role == 'employer_company') {
      roles.add(role);
    }
    return roles;
  }

  Future<void> _initUid() async {
    final uid = await getEffectiveUid(ensureAnonymousIfMissing: true);
    if (!mounted) return;
    setState(() => _resolvedUid = uid?.trim());
  }

  @override
  void initState() {
    super.initState();
    _initUid();
  }

  Future<void> _saveCompany(String uid, {required bool isPrivate}) async {
    // ✅ companyName обязательно только если company
    if (!isPrivate && _company.text.trim().isEmpty) {
      _toast('Введите название компании');
      return;
    }

    setState(() => _saving = true);
    try {
      final doc = await _meRef(uid).get();
      final current = doc.data() ?? const <String, dynamic>{};
      final personal = current['personal'] is Map
          ? Map<String, dynamic>.from(current['personal'] as Map)
          : const <String, dynamic>{};
      final firstName = _s(current['firstName']).isNotEmpty
          ? _s(current['firstName'])
          : _s(personal['firstName']);
      final lastName = _s(current['lastName']).isNotEmpty
          ? _s(current['lastName'])
          : _s(personal['lastName']);
      final email = _s(current['email']).isNotEmpty
          ? _s(current['email'])
          : _s(personal['email']);
      final phone = _s(current['phone']).isNotEmpty
          ? _s(current['phone'])
          : _s(personal['phone']);
      final mergedRoles = _rolesFromUserDoc(current);
      mergedRoles.add(isPrivate ? 'employer_private' : 'employer_company');

      if (firstName.isEmpty ||
          lastName.isEmpty ||
          email.isEmpty ||
          phone.isEmpty) {
        _toast(
          'Заполните контакты физлица в аккаунте (имя, фамилия, email, телефон)',
        );
        return;
      }

      await _meRef(uid).set({
        'role': 'employer',
        'roles': mergedRoles.toList(),
        'employerType': isPrivate ? 'private' : 'company',
        'firstName': firstName,
        'lastName': lastName,
        'email': email,
        'phone': phone,
        // сохраняем поля компании, даже если private — но UI их блокирует
        'companyName': _company.text.trim(),
        'companyRegNumber': _reg.text.trim(),
        'companyWebsite': _site.text.trim(),
        'business': {
          'employerType': isPrivate ? 'private' : 'company',
          'companyName': _company.text.trim(),
          'companyRegNumber': _reg.text.trim(),
          'companyWebsite': _site.text.trim(),
        },
        'businessProfileCompleted': true,
        'businessProfileCompletedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!isPrivate) {
        await _createCompanyBackend(uid);
      }

      _toast('Профиль работодателя сохранён ✅');
      AppMode.setMode(AccountMode.business);
      if (!mounted) return;
      NavigationReturnSnapshot.captureTab(2);
      Navigator.of(
        context,
        rootNavigator: true,
      ).popUntil((route) => route.isFirst);
    } catch (e) {
      _toast('Ошибка: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _openContactPackageSheet() async {
    final purchased = await ContactUnlockPaywallSheet.open(
      context,
      entryPoint: 'employer_profile_credits_cta',
      mode: PaywallMode.creditsOnly,
    );
    if (!purchased) return;
    _toast('Покупка выполнена ✅');
  }

  Future<void> _createCompanyBackend(String uid) async {
    const base = String.fromEnvironment('WORKA_API_BASE_URL', defaultValue: '');
    assert(base.trim().isNotEmpty, 'WORKA_API_BASE_URL is required');
    final uri = Uri.parse('${base.trim().replaceAll(RegExp(r'/+$'), '')}/api/companies');

    final token = await _auth.currentUser?.getIdToken();
    if (token == null || token.isEmpty) {
      debugPrint('[company_profile] missing auth token for POST /api/companies');
      return;
    }

    final body = {
      'name': _company.text.trim(),
      'created_by_user_id': uid,
    };

    try {
      debugPrint('[company_profile] POST $uri body=$body');
      final resp = await http.post(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
        body: jsonEncode(body),
      );
      debugPrint(
        '[company_profile] POST /api/companies status=${resp.statusCode} body=${resp.body}',
      );
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        final data = jsonDecode(resp.body);
        final companyId = (data?['company']?['id'] ?? '').toString().trim();
        if (companyId.isNotEmpty) {
          _ownership.setActiveCompanyId(companyId);
          debugPrint('[company_profile] activeCompanyId set to $companyId');
        }
      }
    } catch (e, st) {
      debugPrint('[company_profile] POST /api/companies error=$e');
      debugPrint('[company_profile] stack=$st');
    }
  }

  InputDecoration _deco(String label, IconData icon, {bool disabled = false}) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(
        fontWeight: FontWeight.w600,
        color: disabled ? WorkaColors.textGrey : WorkaColors.textGreyDark,
        fontSize: 15,
      ),
      prefixIcon: Icon(
        icon,
        color: disabled ? WorkaColors.textGrey : WorkaColors.blue,
      ),
      filled: true,
      fillColor: disabled ? Colors.grey.shade100 : Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: WorkaColors.fieldBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: WorkaColors.blue, width: 1.6),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final u = _auth.currentUser;
    final uid = (_resolvedUid ?? '').trim();

    return Scaffold(
      backgroundColor: const Color(0xFF4A6FDB),
      body: Column(
        children: [
          WorkaHeader(
            title: 'Профиль работодателя',
            leading: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back, color: Colors.white),
            ),
          ),
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(24),
                  topRight: Radius.circular(24),
                ),
              ),
              child: uid.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Не удалось подготовить профиль. Попробуйте ещё раз.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: WorkaColors.textGreyDark,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 12),
                            OutlinedButton(
                              onPressed: _initUid,
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(
                                  color: WorkaColors.fieldBorder,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text(
                                'Повторить',
                                style: TextStyle(
                                  color: WorkaColors.blue,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                      stream: _meRef(uid).snapshots(),
                      builder: (context, snap) {
                        if (snap.hasError) {
                          return Center(child: Text('Ошибка: ${snap.error}'));
                        }
                        if (!snap.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          );
                        }

                        final m = snap.data!.data() ?? {};

                        final employerType = _s(m['employerType']).isNotEmpty
                            ? _s(m['employerType'])
                            : _s(widget.initialEmployerType);
                        final isPrivate = employerType == 'private';

                        // ✅ 1 раз заполняем контроллеры компании
                        if (!_loadedOnce) {
                          _company.text = _s(m['companyName']);
                          _reg.text = _s(m['companyRegNumber']);
                          _site.text = _s(m['companyWebsite']);
                          _loadedOnce = true;
                        }

                        final firstName = _s(m['firstName']).isNotEmpty
                            ? _s(m['firstName'])
                            : _s(m['name']);
                        final lastName = _s(m['lastName']);
                        final fullNameRaw = ('$firstName $lastName').trim();
                        final fullName = fullNameRaw.isEmpty
                            ? 'Не указано'
                            : fullNameRaw;

                        // ✅ null-safe для auth
                        final phone = _s(m['phone']).isNotEmpty
                            ? _s(m['phone'])
                            : _s(u?.phoneNumber ?? '');
                        final email = _s(m['email']).isNotEmpty
                            ? _s(m['email'])
                            : _s(u?.email ?? '');
                        String pickContact(String key) {
                          final contacts = (m['contacts'] is Map)
                              ? Map<String, dynamic>.from(m['contacts'] as Map)
                              : const <String, dynamic>{};
                          final socialLinks = (m['socialLinks'] is Map)
                              ? Map<String, dynamic>.from(
                                  m['socialLinks'] as Map,
                                )
                              : const <String, dynamic>{};
                          final business = (m['business'] is Map)
                              ? Map<String, dynamic>.from(m['business'] as Map)
                              : const <String, dynamic>{};
                          final values = <String>[
                            _s(m[key]),
                            _s(contacts[key]),
                            _s(socialLinks[key]),
                            _s(business[key]),
                          ];
                          for (final value in values) {
                            if (value.isNotEmpty) return value;
                          }
                          return '';
                        }

                        final whatsapp = pickContact('whatsapp');
                        final telegram = pickContact('telegram');
                        final viber = pickContact('viber');
                        final messenger = pickContact('messenger');

                        return ListView(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
                          children: [
                            // ✅ блок данных аккаунта + ✏️
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: WorkaColors.divider),
                                boxShadow: [
                                  BoxShadow(
                                    blurRadius: 14,
                                    offset: const Offset(0, 6),
                                    color: Colors.black.withValues(alpha: 0.05),
                                  ),
                                ],
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          isPrivate
                                              ? 'Контактное лицо (частное лицо)'
                                              : 'Контактное лицо (компания)',
                                          style: const TextStyle(
                                            color: WorkaColors.textGrey,
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14,
                                          ),
                                        ),
                                        const SizedBox(height: 6),
                                        Text(
                                          fullName,
                                          style: const TextStyle(
                                            color: WorkaColors.textDark,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 18,
                                            height: 1.15,
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        _InfoRow(
                                          label: 'Телефон',
                                          value: phone.isEmpty
                                              ? 'Не указан'
                                              : phone,
                                        ),
                                        const SizedBox(height: 6),
                                        _InfoRow(
                                          label: 'Email',
                                          value: email.isEmpty
                                              ? 'Не указан'
                                              : email,
                                        ),
                                        if (whatsapp.isNotEmpty) ...[
                                          const SizedBox(height: 6),
                                          _InfoRow(
                                            label: 'WhatsApp',
                                            value: whatsapp,
                                          ),
                                        ],
                                        if (telegram.isNotEmpty) ...[
                                          const SizedBox(height: 6),
                                          _InfoRow(
                                            label: 'Telegram',
                                            value: telegram,
                                          ),
                                        ],
                                        if (viber.isNotEmpty) ...[
                                          const SizedBox(height: 6),
                                          _InfoRow(
                                            label: 'Viber',
                                            value: viber,
                                          ),
                                        ],
                                        if (messenger.isNotEmpty) ...[
                                          const SizedBox(height: 6),
                                          _InfoRow(
                                            label: 'Messenger',
                                            value: messenger,
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'Редактировать аккаунт',
                                    onPressed: () => Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => EditAccountScreen(),
                                      ),
                                    ),
                                    icon: const Icon(
                                      Icons.edit,
                                      color: WorkaColors.blue,
                                    ),
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 14),

                            if (isPrivate)
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: WorkaColors.hoverBlueSoft,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: WorkaColors.fieldBorder,
                                  ),
                                ),
                                child: const Row(
                                  children: [
                                    Icon(
                                      Icons.info_outline,
                                      color: WorkaColors.blue,
                                    ),
                                    SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        'Вы выбрали “Частное лицо”. Данные компании не требуются и закрыты.',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w800,
                                          color: WorkaColors.textDark,
                                          height: 1.2,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                            if (isPrivate) const SizedBox(height: 12),

                            // ✅ поля компании (disabled если private)
                            TextField(
                              controller: _company,
                              enabled: !isPrivate,
                              decoration: _deco(
                                isPrivate
                                    ? 'Название компании (закрыто)'
                                    : 'Название компании *',
                                Icons.business_outlined,
                                disabled: isPrivate,
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _reg,
                              enabled: !isPrivate,
                              decoration: _deco(
                                isPrivate
                                    ? 'Регистрационный номер (закрыто)'
                                    : 'Регистрационный номер',
                                Icons.confirmation_number_outlined,
                                disabled: isPrivate,
                              ),
                            ),
                            const SizedBox(height: 12),
                            TextField(
                              controller: _site,
                              enabled: !isPrivate,
                              decoration: _deco(
                                isPrivate ? 'Веб-сайт (закрыто)' : 'Веб-сайт',
                                Icons.language,
                                disabled: isPrivate,
                              ),
                            ),

                            const SizedBox(height: 16),

                            SizedBox(
                              height: 56,
                              child: ElevatedButton(
                                onPressed: _saving
                                    ? null
                                    : () => _saveCompany(
                                        uid,
                                        isPrivate: isPrivate,
                                      ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: WorkaColors.orange,
                                  foregroundColor: WorkaColors.onColored,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(28),
                                  ),
                                ),
                                child: _saving
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Text(
                                        'Сохранить',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w900,
                                          fontSize: 16,
                                        ),
                                      ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              height: 56,
                              child: ElevatedButton(
                                onPressed: _openContactPackageSheet,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: WorkaColors.blue,
                                  foregroundColor: Colors.white,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(28),
                                  ),
                                ),
                                child: const Text(
                                  'Купить кредиты',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 16,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          '$label: ',
          style: const TextStyle(
            color: WorkaColors.textGrey,
            fontWeight: FontWeight.w600,
            fontSize: 15,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: WorkaColors.textGreyDark,
              fontWeight: FontWeight.w600,
              fontSize: 15,
            ),
          ),
        ),
      ],
    );
  }
}
