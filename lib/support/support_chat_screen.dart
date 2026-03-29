import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../theme/worka_colors.dart';
import '../widgets/app_background.dart';
import '../widgets/worka_standard_screen_layout.dart';

class SupportChatScreen extends StatefulWidget {
  const SupportChatScreen({super.key});

  @override
  State<SupportChatScreen> createState() => _SupportChatScreenState();
}

class _SupportChatScreenState extends State<SupportChatScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final TextEditingController _messageCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();

  bool _sending = false;

  String _chatUid() {
    final uid = _auth.currentUser?.uid.trim() ?? '';
    return uid.isNotEmpty ? uid : 'guest_support';
  }

  String _time(dynamic rawTs) {
    DateTime? dt;
    if (rawTs is Timestamp) dt = rawTs.toDate();
    if (dt == null) return '';
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _messagesStream() {
    return _db
        .collection('supportChats')
        .doc(_chatUid())
        .collection('messages')
        .orderBy('createdAt', descending: false)
        .snapshots();
  }

  Future<void> _sendMessage() async {
    if (_sending) return;
    final text = _messageCtrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    try {
      await _db
          .collection('supportChats')
          .doc(_chatUid())
          .collection('messages')
          .add({
            'from': 'user',
            'text': text,
            'createdAt': FieldValue.serverTimestamp(),
          });
      _messageCtrl.clear();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_scrollCtrl.hasClients) return;
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent + 120,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка отправки: $e'),
          backgroundColor: WorkaColors.textDark,
        ),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  void dispose() {
    _messageCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inset = MediaQuery.of(context).viewInsets.bottom;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(gradient: AppBackground.gradient),
            ),
          ),
          Positioned.fill(
            child: WorkaStandardScreenLayout(
              header: _ChatHeader(onBack: () => Navigator.maybePop(context)),
              headerPadding: const EdgeInsets.fromLTRB(0, 8, 0, 8),
              body: Column(
                children: [
                  Expanded(
                    child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      stream: _messagesStream(),
                      builder: (context, snap) {
                        final docs = snap.data?.docs ?? const [];
                        if (docs.isEmpty) {
                          return ListView(
                            controller: _scrollCtrl,
                            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                            children: const [
                              _Bubble(
                                text: 'Здравствуйте! Чем можем помочь?',
                                time: '',
                                isUser: false,
                              ),
                              _TypingIndicator(),
                            ],
                          );
                        }
                        return ListView.builder(
                          controller: _scrollCtrl,
                          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                          itemCount: docs.length + 1,
                          itemBuilder: (context, index) {
                            if (index == docs.length) {
                              return const _TypingIndicator();
                            }
                            final m = docs[index].data();
                            return _Bubble(
                              text: (m['text'] ?? '').toString(),
                              time: _time(m['createdAt']),
                              isUser: (m['from'] ?? '').toString() == 'user',
                            );
                          },
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.fromLTRB(12, 6, 12, 10 + inset),
                    child: _InputBar(
                      controller: _messageCtrl,
                      sending: _sending,
                      onSend: _sendMessage,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatHeader extends StatelessWidget {
  final VoidCallback onBack;

  const _ChatHeader({required this.onBack});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 14),
      decoration: const BoxDecoration(),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back, color: WorkaColors.textDark),
          ),
          const SizedBox(
            width: 36,
            height: 36,
            child: Icon(Icons.support_agent, color: WorkaColors.textGreyDark),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Поддержка Worka',
                  style: TextStyle(
                    color: WorkaColors.textDark,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 2),
                Row(
                  children: [
                    _OnlineDot(),
                    SizedBox(width: 6),
                    Text(
                      'онлайн',
                      style: TextStyle(
                        color: WorkaColors.textGreyDark,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  const _InputBar({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: const BoxDecoration(),
      child: Row(
        children: [
          IconButton(
            onPressed: () {},
            icon: const Icon(
              Icons.attach_file_rounded,
              color: WorkaColors.textGreyDark,
            ),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => onSend(),
              style: const TextStyle(
                color: WorkaColors.textDark,
                fontWeight: FontWeight.w600,
              ),
              decoration: const InputDecoration(
                border: InputBorder.none,
                isCollapsed: true,
                hintText: 'Напишите сообщение...',
                hintStyle: TextStyle(
                  color: WorkaColors.textGrey,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          InkWell(
            onTap: sending ? null : onSend,
            borderRadius: BorderRadius.circular(999),
            child: Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(shape: BoxShape.circle),
              child: const Icon(
                Icons.send_rounded,
                color: WorkaColors.primaryBlue,
                size: 19,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final String text;
  final String time;
  final bool isUser;

  const _Bubble({required this.text, required this.time, required this.isUser});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Column(
          crossAxisAlignment: isUser
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Container(
              constraints: const BoxConstraints(maxWidth: 290),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: const BoxDecoration(),
              child: Text(
                text,
                style: TextStyle(
                  color: WorkaColors.textDark,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
            ),
            if (time.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                time,
                style: const TextStyle(
                  color: Color(0xFF94A3B8),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();

  @override
  Widget build(BuildContext context) {
    return const Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.fromLTRB(6, 6, 6, 8),
        child: _Bubble(text: 'Worka печатает...', time: '', isUser: false),
      ),
    );
  }
}

class _OnlineDot extends StatelessWidget {
  const _OnlineDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: const BoxDecoration(
        color: Color(0xFF22C55E),
        shape: BoxShape.circle,
      ),
    );
  }
}
