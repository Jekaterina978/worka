import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../theme/worka_colors.dart';
import 'search/search_screen.dart';
import 'employer/candidate_search_screen.dart';

enum _HomeRole { worker, employer }

class AuthorizedHomeScreen extends StatefulWidget {
  const AuthorizedHomeScreen({super.key});

  @override
  State<AuthorizedHomeScreen> createState() => _AuthorizedHomeScreenState();
}

class _AuthorizedHomeScreenState extends State<AuthorizedHomeScreen> {
  _HomeRole _role = _HomeRole.worker;
  final _db = FirebaseFirestore.instance;

  Future<Map<String, dynamic>> _loadUserProfile() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return <String, dynamic>{};
    final snap = await _db.collection('users').doc(uid).get();
    return snap.data() ?? <String, dynamic>{};
  }

  String _initials(User? u, Map<String, dynamic> profile) {
    final fn = (profile['firstName'] ?? '').toString().trim();
    final ln = (profile['lastName'] ?? '').toString().trim();
    final name = (profile['name'] ?? '').toString().trim();
    final raw = ([fn, ln].where((e) => e.isNotEmpty).join(' ').trim().isNotEmpty
            ? [fn, ln].where((e) => e.isNotEmpty).join(' ')
            : (name.isNotEmpty ? name : (u?.displayName ?? u?.email ?? 'U')))
        .trim();
    if (raw.isEmpty) return 'U';
    final parts = raw.split(RegExp(r'\s+')).where((e) => e.trim().isNotEmpty).toList();
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts[1][0]}'.toUpperCase();
    }
    return raw[0].toUpperCase();
  }

  void _goStartSearch() {
    final isAuthed = FirebaseAuth.instance.currentUser != null;
    final screen = _role == _HomeRole.worker ? SearchScreen(testMode: !isAuthed) : const CandidateSearchScreen();
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final u = FirebaseAuth.instance.currentUser;
    return FutureBuilder<Map<String, dynamic>>(
      future: _loadUserProfile(),
      builder: (context, snap) {
        final profile = snap.data ?? <String, dynamic>{};
        return Scaffold(
          backgroundColor: WorkaColors.pageBg,
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  color: Colors.white,
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(22, 20, 22, 22),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(99),
                                  border: Border.all(color: WorkaColors.blue, width: 1.5),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  _initials(u, profile),
                                  style: const TextStyle(
                                    color: WorkaColors.blue,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              const Spacer(),
                            ],
                          ),
                          SizedBox(height: 58, child: Image.asset('assets/logo.png', fit: BoxFit.contain)),
                          const SizedBox(height: 22),
                          SizedBox(height: 240, child: Image.asset('assets/illustration.png', fit: BoxFit.contain)),
                          const SizedBox(height: 22),
                          const Text(
                            'Работа рядом\nи по всему миру',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 34, fontWeight: FontWeight.w900, color: WorkaColors.textDark, height: 1.05),
                          ),
                          const SizedBox(height: 14),
                          const Text(
                            'Вакансии и специалисты\nдля удалёнки и локально',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 21, fontWeight: FontWeight.w600, color: WorkaColors.textGrey, height: 1.3),
                          ),
                          const SizedBox(height: 22),
                          _RoleSlider(
                            value: _role,
                            onChanged: (r) => setState(() => _role = r),
                            height: 64,
                          ),
                          const SizedBox(height: 18),
                          SizedBox(
                            height: 64,
                            width: 320,
                            child: ElevatedButton(
                              onPressed: _goStartSearch,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: WorkaColors.orange,
                                elevation: 0,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(32)),
                              ),
                              child: const Text(
                                'Начать поиск',
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 22),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RoleSlider extends StatelessWidget {
  final _HomeRole value;
  final ValueChanged<_HomeRole> onChanged;
  final double height;

  const _RoleSlider({
    required this.value,
    required this.onChanged,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    final isWorker = value == _HomeRole.worker;
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final pillW = w / 2;
        return Container(
          height: height,
          decoration: BoxDecoration(
            color: WorkaColors.sliderGrey,
            borderRadius: BorderRadius.circular(32),
          ),
          child: Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                top: 0,
                bottom: 0,
                left: isWorker ? 0 : pillW,
                width: pillW,
                child: Container(
                  decoration: BoxDecoration(color: WorkaColors.blue, borderRadius: BorderRadius.circular(32)),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () => onChanged(_HomeRole.worker),
                      borderRadius: BorderRadius.circular(32),
                      child: Center(
                        child: Text(
                          'Работник',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: isWorker ? Colors.white : WorkaColors.textGreyDark,
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: InkWell(
                      onTap: () => onChanged(_HomeRole.employer),
                      borderRadius: BorderRadius.circular(32),
                      child: Center(
                        child: Text(
                          'Работодатель',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: isWorker ? WorkaColors.textGreyDark : Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
