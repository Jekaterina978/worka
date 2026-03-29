import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:worka/theme/worka_colors.dart';

import '../payments_i18n.dart';
import '../repository/payments_repository.dart';
import 'verification_status_screen.dart';

class VerificationUploadScreen extends StatefulWidget {
  const VerificationUploadScreen({super.key});

  @override
  State<VerificationUploadScreen> createState() =>
      _VerificationUploadScreenState();
}

class _VerificationUploadScreenState extends State<VerificationUploadScreen> {
  final _repo = PaymentsRepository();
  final _picker = ImagePicker();
  final _notes = TextEditingController();

  File? _file;
  bool _loading = false;

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  void _toast(String text, {bool error = false}) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? Colors.red.shade700 : WorkaColors.textDark,
      ),
    );
  }

  Future<void> _pick() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 92,
    );
    if (picked == null) return;
    setState(() => _file = File(picked.path));
  }

  Future<void> _upload() async {
    final file = _file;
    if (file == null) {
      _toast('Сначала выберите файл', error: true);
      return;
    }

    setState(() => _loading = true);
    try {
      await _repo.uploadVerificationFile(file: file, notes: _notes.text.trim());
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute(builder: (_) => const VerificationStatusScreen()),
      );
    } catch (e) {
      if (!mounted) return;
      _toast('${PaymentsI18n.t(context, 'failed')}: $e', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        title: Text(
          PaymentsI18n.t(context, 'upload_docs'),
          style: const TextStyle(
            color: WorkaColors.blue,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        children: [
          InkWell(
            onTap: _loading ? null : _pick,
            borderRadius: BorderRadius.circular(14),
            child: Ink(
              height: 140,
              decoration: BoxDecoration(
                color: WorkaColors.hoverBlueSoft,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: WorkaColors.fieldBorder),
              ),
              child: Center(
                child: Text(
                  _file == null
                      ? 'Нажмите, чтобы выбрать документ'
                      : _file!.path.split('/').last,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: WorkaColors.textDark,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            minLines: 3,
            maxLines: 5,
            decoration: InputDecoration(
              labelText: 'Комментарий (опционально)',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: WorkaColors.fieldBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: WorkaColors.fieldBorder),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: _loading ? null : _upload,
              style: ElevatedButton.styleFrom(
                backgroundColor: WorkaColors.blue,
                disabledBackgroundColor: WorkaColors.blue.withValues(
                  alpha: 0.35,
                ),
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              child: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      PaymentsI18n.t(context, 'done'),
                      style: const TextStyle(
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
