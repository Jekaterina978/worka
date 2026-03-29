// lib/screens/employer_contacts_screen.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../widgets/worka_header.dart';

class EmployerContactsScreen extends StatefulWidget {
  const EmployerContactsScreen({super.key});

  @override
  State<EmployerContactsScreen> createState() => _EmployerContactsScreenState();
}

class _EmployerContactsScreenState extends State<EmployerContactsScreen> {
  final _db = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  bool _saving = false;

  // Add-contact UI
  bool _showAdd = false;
  String _type = 'phone';
  final _valueCtrl = TextEditingController();

  @override
  void dispose() {
    _valueCtrl.dispose();
    super.dispose();
  }

  DocumentReference<Map<String, dynamic>> _meRefFor(String uid) =>
      _db.collection('users').doc(uid);

  String _typeLabel(String t) {
    switch (t) {
      case 'phone':
        return 'Телефон';
      case 'email':
        return 'Email';
      case 'telegram':
        return 'Telegram';
      case 'whatsapp':
        return 'WhatsApp';
      default:
        return t;
    }
  }

  Future<void> _toggleShowContacts(String uid, bool v) async {
    setState(() => _saving = true);
    try {
      await _meRefFor(uid).set({'showContacts': v}, SetOptions(merge: true));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addContact(String uid, Map<String, dynamic> current) async {
    final raw = _valueCtrl.text.trim();
    if (raw.isEmpty) return;

    final Map<String, dynamic> contacts =
        Map<String, dynamic>.from(current['contacts'] ?? {});
    final List<dynamic> list = List<dynamic>.from(contacts[_type] ?? []);

    if (!list.contains(raw)) list.add(raw);
    contacts[_type] = list;

    setState(() => _saving = true);
    try {
      await _meRefFor(uid).set({'contacts': contacts}, SetOptions(merge: true));
      _valueCtrl.clear();
      if (mounted) setState(() => _showAdd = false);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _removeContact(
    String uid,
    Map<String, dynamic> current,
    String type,
    String value,
  ) async {
    final Map<String, dynamic> contacts =
        Map<String, dynamic>.from(current['contacts'] ?? {});
    final List<dynamic> list = List<dynamic>.from(contacts[type] ?? []);
    list.removeWhere((e) => e.toString() == value);
    contacts[type] = list;

    setState(() => _saving = true);
    try {
      await _meRefFor(uid).set({'contacts': contacts}, SetOptions(merge: true));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = _auth.currentUser;

    // ✅ Разрешаем зайти без SMS, но сохранять нельзя
    if (user == null) {
      return Scaffold(
        backgroundColor: const Color(0xFF4A6FDB),
        body: Column(
          children: [
            WorkaHeader(
              title: 'Контакты работодателя',
              leading: IconButton(
                onPressed: () => Navigator.maybePop(context),
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
                child: Padding(
          padding: const EdgeInsets.all(16),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3E6),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFFFD8B3)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'Нужно войти по SMS',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                ),
                SizedBox(height: 8),
                Text(
                  'Чтобы добавлять и сохранять контакты, сначала войдите в аккаунт.',
                  style: TextStyle(height: 1.3),
                ),
              ],
            ),
          ),
        )),
            ),
          ],
        ),
      );
    }

    final uid = user.uid;

    return Scaffold(
      backgroundColor: const Color(0xFF4A6FDB),
      body: Column(
        children: [
          WorkaHeader(
            title: 'Контакты работодателя',
            leading: IconButton(
              onPressed: () => Navigator.maybePop(context),
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
              child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _meRefFor(uid).snapshots(),
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text('Ошибка: ${snap.error}'));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());

          final data = snap.data!.data() ?? {};
          final showContacts = (data['showContacts'] ?? false) == true;
          final contacts = Map<String, dynamic>.from(data['contacts'] ?? {});

          List<MapEntry<String, String>> flattened() {
            final out = <MapEntry<String, String>>[];
            for (final t in ['phone', 'email', 'telegram', 'whatsapp']) {
              final list = List<dynamic>.from(contacts[t] ?? []);
              for (final v in list) {
                out.add(MapEntry(t, v.toString()));
              }
            }
            return out;
          }

          final all = flattened();

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: const [
                          Text('Показывать контакты',
                              style: TextStyle(fontWeight: FontWeight.w900)),
                          SizedBox(height: 6),
                          Text(
                            'Если выключено — на вакансии будут только отклики.',
                            style: TextStyle(color: Colors.black54),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: showContacts,
                      onChanged: _saving ? null : (v) => _toggleShowContacts(uid, v),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 14),

              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Список контактов',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _saving ? null : () => setState(() => _showAdd = !_showAdd),
                    icon: const Icon(Icons.add),
                    label: const Text('Добавить'),
                  ),
                ],
              ),

              if (_showAdd) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.shade200),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 14,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            isExpanded: true,
                            value: _type,
                            items: const ['phone', 'email', 'telegram', 'whatsapp']
                                .map((t) => DropdownMenuItem(
                                      value: t,
                                      child: Text(
                                        t == 'phone'
                                            ? 'Телефон'
                                            : t == 'email'
                                                ? 'Email'
                                                : t == 'telegram'
                                                    ? 'Telegram'
                                                    : 'WhatsApp',
                                      ),
                                    ))
                                .toList(),
                            onChanged: _saving ? null : (v) => setState(() => _type = v ?? 'phone'),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: _valueCtrl,
                        decoration: InputDecoration(
                          labelText: 'Значение (${_typeLabel(_type)})',
                          hintText: _type == 'telegram'
                              ? 'username без @'
                              : _type == 'email'
                                  ? 'mail@example.com'
                                  : '+372 ...',
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        height: 46,
                        child: ElevatedButton(
                          onPressed: _saving ? null : () => _addContact(uid, data),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFF7A00),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          child: _saving
                              ? const SizedBox(
                                  height: 18,
                                  width: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text(
                                  'Сохранить контакт',
                                  style: TextStyle(fontWeight: FontWeight.w900, color: Colors.white),
                                ),
                        ),
                      )
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 10),

              if (all.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: Text('Контактов пока нет. Нажми “Добавить”.'),
                )
              else
                ...all.map((e) {
                  return Container(
                    margin: const EdgeInsets.only(top: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.grey.shade200),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 14,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        _ContactIcon(type: e.key),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_typeLabel(e.key),
                                  style: const TextStyle(fontWeight: FontWeight.w900)),
                              const SizedBox(height: 4),
                              Text(e.value),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: _saving ? null : () => _removeContact(uid, data, e.key, e.value),
                          icon: const Icon(Icons.delete_outline),
                        )
                      ],
                    ),
                  );
                }),
            ],
          );
        },
      )),
            ),
        ],
      ),
    );
  }
}

class _ContactIcon extends StatelessWidget {
  final String type;
  const _ContactIcon({required this.type});

  @override
  Widget build(BuildContext context) {
    IconData icon;
    switch (type) {
      case 'phone':
        icon = Icons.call;
        break;
      case 'email':
        icon = Icons.email_outlined;
        break;
      case 'telegram':
        icon = Icons.send_outlined;
        break;
      case 'whatsapp':
        icon = Icons.chat_bubble_outline;
        break;
      default:
        icon = Icons.contact_phone_outlined;
    }

    return Container(
      height: 42,
      width: 42,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Icon(icon),
    );
  }
}
