import 'dart:math' show min;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/app_mode.dart';
import 'burger_drawer.dart';

/// A small circular avatar button shown in the top-right of every screen.
/// Blue border = Private profile. Orange border = Business profile.
/// Tapping opens the BurgerDrawer.
class ProfileAvatarButton extends StatelessWidget {
  const ProfileAvatarButton({super.key, this.testMode = true});

  final bool testMode;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<AccountMode>(
      valueListenable: AppMode.modeNotifier,
      builder: (context, mode, _) {
        final isBusiness = mode == AccountMode.business;
        final borderColor = isBusiness
            ? const Color(0xFFFF8904)
            : const Color(0xFF4A6FDB);
        final user = FirebaseAuth.instance.currentUser;
        if (user == null) {
          return _AvatarCircle(
            label: '?',
            borderColor: borderColor,
            onTap: () => BurgerDrawer.open(context, testMode: testMode),
          );
        }
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .snapshots(),
          builder: (context, snap) {
            final data = snap.data?.data() ?? const <String, dynamic>{};
            final label = isBusiness
                ? _businessLabel(data)
                : _personalLabel(data);
            return _AvatarCircle(
              label: label,
              borderColor: borderColor,
              onTap: () => BurgerDrawer.open(context, testMode: testMode),
            );
          },
        );
      },
    );
  }

  static String _personalLabel(Map<String, dynamic> data) {
    final personal = data['personal'] is Map
        ? Map<String, dynamic>.from(data['personal'] as Map)
        : const <String, dynamic>{};
    final first = _str(
      personal['firstName'] ?? data['firstName'],
    );
    final last = _str(
      personal['lastName'] ?? data['lastName'],
    );
    if (first.isNotEmpty && last.isNotEmpty) {
      return '${first[0]}${last[0]}'.toUpperCase();
    }
    if (first.isNotEmpty) return first.substring(0, min(2, first.length)).toUpperCase();
    if (last.isNotEmpty) return last.substring(0, min(2, last.length)).toUpperCase();
    final email = _str(data['email']);
    if (email.isNotEmpty) return email.substring(0, min(2, email.length)).toUpperCase();
    return '?';
  }

  static String _businessLabel(Map<String, dynamic> data) {
    final business = data['business'] is Map
        ? Map<String, dynamic>.from(data['business'] as Map)
        : const <String, dynamic>{};
    final company = _str(
      business['companyName'] ??
          business['company'] ??
          data['companyName'] ??
          data['company'],
    );
    if (company.isNotEmpty) return company[0].toUpperCase();
    return _personalLabel(data);
  }

  static String _str(dynamic v) => (v ?? '').toString().trim();
}

class _AvatarCircle extends StatelessWidget {
  const _AvatarCircle({
    required this.label,
    required this.borderColor,
    required this.onTap,
  });

  final String label;
  final Color borderColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: borderColor.withValues(alpha: 0.18),
          border: Border.all(color: borderColor, width: 2),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: borderColor,
            fontSize: 13,
            fontWeight: FontWeight.w800,
            height: 1,
          ),
        ),
      ),
    );
  }
}
