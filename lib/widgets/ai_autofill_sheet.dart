import 'package:flutter/material.dart';

import '../services/ai_parser_service.dart';
import '../theme/worka_colors.dart';

/// Reusable bottom sheet that lets the user paste raw text (vacancy or CV)
/// or provide a URL (vacancy only) and triggers AI parsing via [AiParserService].
///
/// Usage:
/// ```dart
/// final result = await AiAutofillSheet.show(
///   context,
///   mode: AiAutofillMode.vacancy,
/// );
/// if (result != null) _applyAutofill(result);
/// ```
enum AiAutofillMode { vacancy, cv }

enum _InputTab { text, url }

class AiAutofillSheet extends StatefulWidget {
  const AiAutofillSheet({super.key, required this.mode});

  final AiAutofillMode mode;

  /// Convenience factory. Returns parsed data map or null if dismissed.
  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    required AiAutofillMode mode,
  }) {
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AiAutofillSheet(mode: mode),
    );
  }

  @override
  State<AiAutofillSheet> createState() => _AiAutofillSheetState();
}

class _AiAutofillSheetState extends State<AiAutofillSheet> {
  final _textCtrl = TextEditingController();
  final _urlCtrl  = TextEditingController();
  final _service  = AiParserService();

  // URL tab only available for vacancy mode.
  _InputTab _tab = _InputTab.text;
  bool _loading = false;
  String? _error;

  bool get _showUrlTab => widget.mode == AiAutofillMode.vacancy;

  String get _textHint => widget.mode == AiAutofillMode.vacancy
      ? 'Вставьте текст вакансии сюда…'
      : 'Вставьте текст резюме / CV сюда…';

  String get _title => widget.mode == AiAutofillMode.vacancy
      ? 'Заполнить из текста вакансии'
      : 'Заполнить из текста резюме';

  // ─── Parse helpers ─────────────────────────────────────────────────────────

  Future<void> _parse() async {
    if (_tab == _InputTab.url) {
      await _parseUrl();
    } else {
      await _parseText();
    }
  }

  Future<void> _parseText() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) {
      setState(() => _error = 'Вставьте текст для анализа');
      return;
    }
    await _run(() => widget.mode == AiAutofillMode.vacancy
        ? _service.parseVacancy(text)
        : _service.parseCv(text));
  }

  Future<void> _parseUrl() async {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) {
      setState(() => _error = 'Введите ссылку на вакансию');
      return;
    }
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme || !uri.host.contains('.')) {
      setState(() => _error = 'Неверная ссылка. Пример: https://hh.ru/vacancy/123');
      return;
    }
    await _run(() => _service.parseVacancyFromUrl(url));
  }

  Future<void> _run(Future<Map<String, dynamic>> Function() fn) async {
    setState(() {
      _loading = true;
      _error   = null;
    });

    try {
      final parsed = await fn();
      if (!mounted) return;
      Navigator.of(context).pop(parsed);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error   = _friendlyError(e);
      });
    }
  }

  String _friendlyError(Object e) {
    final raw = e.toString();
    assert(() {
      debugPrint(
        '[AiAutofillSheet] errorType=${e.runtimeType} raw=$raw',
      );
      return true;
    }());
    // StateError wraps the message — strip the prefix.
    final msg = raw.startsWith('Bad state: ') ? raw.substring('Bad state: '.length) : raw;
    if (msg.isNotEmpty) {
      // Keep detailed diagnostics in debug only.
      assert(() {
        debugPrint('[AiAutofillSheet] parse error: $msg');
        return true;
      }());
    }

    if (msg.contains('OPENAI_API_KEY') || msg.contains('not configured')) {
      return 'Сервис временно недоступен. Попробуйте позже.';
    }
    if (msg.contains('SocketException') || msg.contains('Failed host lookup') ||
        msg.contains('Failed to fetch') || msg.contains('NetworkException')) {
      return 'Нет подключения к интернету. Проверьте сеть и повторите.';
    }
    if (msg.contains('403') || msg.contains('401')) {
      return 'Ошибка авторизации. Перезайдите в приложение и попробуйте снова.';
    }
    if (msg.contains('503') || msg.contains('502') || msg.contains('500')) {
      return 'Сервер временно недоступен. Попробуйте через несколько секунд.';
    }
    if (msg.contains('timeout') || msg.contains('TimeoutException')) {
      return 'Запрос занял слишком много времени. Попробуйте позже.';
    }
    if (msg.contains('SSRF') || msg.contains('private') || msg.contains('blocked')) {
      return 'Эта ссылка недоступна для импорта. Попробуйте другую.';
    }
    if (msg.contains('не удалось получить') || msg.contains('Failed to fetch page')) {
      return 'Не удалось загрузить страницу. Проверьте ссылку или вставьте текст вручную.';
    }
    if (msg.contains('invalid JSON') || msg.contains('AI returned')) {
      return 'ИИ вернул неожиданный ответ. Попробуйте ещё раз.';
    }
    return 'Не удалось выполнить авто-заполнение. Попробуйте ещё раз позже.';
  }

  // ─── Lifecycle ─────────────────────────────────────────────────────────────

  @override
  void dispose() {
    _textCtrl.dispose();
    _urlCtrl.dispose();
    super.dispose();
  }

  // ─── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottom),
      decoration: const BoxDecoration(
        color: WorkaColors.cardBg,
        borderRadius: BorderRadius.all(Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Row(
            children: [
              const Icon(Icons.auto_awesome, size: 20, color: WorkaColors.blue),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: WorkaColors.textDark,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () => Navigator.of(context).pop(),
                color: WorkaColors.textGreyDark,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),

          const SizedBox(height: 4),
          Text(
            'ИИ автоматически заполнит поля формы. Вы сможете отредактировать данные перед публикацией.',
            style: TextStyle(fontSize: 13, color: WorkaColors.textGreyDark),
          ),

          // Tab bar (vacancy only)
          if (_showUrlTab) ...[
            const SizedBox(height: 14),
            _TabBar(
              selected: _tab,
              enabled: !_loading,
              onChanged: (t) => setState(() {
                _tab   = t;
                _error = null;
              }),
            ),
          ],

          const SizedBox(height: 14),

          // Input area
          if (_tab == _InputTab.text) _TextInput(ctrl: _textCtrl, hint: _textHint, enabled: !_loading)
          else                         _UrlInput(ctrl: _urlCtrl, enabled: !_loading),

          // Error
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: const TextStyle(fontSize: 13, color: Colors.redAccent),
            ),
          ],

          const SizedBox(height: 16),

          // Parse button
          SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _loading ? null : _parse,
              icon: _loading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.auto_awesome, size: 18),
              label: Text(_loading ? 'Анализирую…' : 'Заполнить автоматически'),
              style: ElevatedButton.styleFrom(
                backgroundColor: WorkaColors.blue,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Sub-widgets ─────────────────────────────────────────────────────────────

class _TabBar extends StatelessWidget {
  const _TabBar({
    required this.selected,
    required this.enabled,
    required this.onChanged,
  });

  final _InputTab selected;
  final bool enabled;
  final ValueChanged<_InputTab> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _Tab(label: 'Текст', icon: Icons.text_snippet_outlined,  tab: _InputTab.text, selected: selected, enabled: enabled, onTap: onChanged),
        const SizedBox(width: 8),
        _Tab(label: 'Ссылка', icon: Icons.link,                  tab: _InputTab.url,  selected: selected, enabled: enabled, onTap: onChanged),
      ],
    );
  }
}

class _Tab extends StatelessWidget {
  const _Tab({
    required this.label,
    required this.icon,
    required this.tab,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final _InputTab tab;
  final _InputTab selected;
  final bool enabled;
  final ValueChanged<_InputTab> onTap;

  @override
  Widget build(BuildContext context) {
    final isSelected = tab == selected;
    return GestureDetector(
      onTap: enabled ? () => onTap(tab) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? WorkaColors.blue : WorkaColors.pageBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? WorkaColors.blue : WorkaColors.divider,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: isSelected ? Colors.white : WorkaColors.textGreyDark),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: isSelected ? Colors.white : WorkaColors.textGreyDark,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TextInput extends StatelessWidget {
  const _TextInput({required this.ctrl, required this.hint, required this.enabled});

  final TextEditingController ctrl;
  final String hint;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: ctrl,
      minLines: 6,
      maxLines: 14,
      enabled: enabled,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: WorkaColors.textGreyDark, fontSize: 14),
        filled: true,
        fillColor: WorkaColors.pageBg,
        border:        _border(),
        enabledBorder: _border(),
        focusedBorder: _border(focused: true),
        contentPadding: const EdgeInsets.all(14),
      ),
    );
  }

  OutlineInputBorder _border({bool focused = false}) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: focused ? WorkaColors.blue : WorkaColors.divider,
          width: focused ? 1.5 : 1.0,
        ),
      );
}

class _UrlInput extends StatelessWidget {
  const _UrlInput({required this.ctrl, required this.enabled});

  final TextEditingController ctrl;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: ctrl,
      enabled: enabled,
      keyboardType: TextInputType.url,
      textInputAction: TextInputAction.done,
      decoration: InputDecoration(
        hintText: 'https://hh.ru/vacancy/12345678',
        hintStyle: TextStyle(color: WorkaColors.textGreyDark, fontSize: 14),
        prefixIcon: const Icon(Icons.link, size: 18, color: WorkaColors.textGreyDark),
        filled: true,
        fillColor: WorkaColors.pageBg,
        border:        _border(),
        enabledBorder: _border(),
        focusedBorder: _border(focused: true),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        helperText: 'Поддерживаются hh.ru, rabota.ee и другие сайты вакансий',
        helperStyle: TextStyle(fontSize: 12, color: WorkaColors.textGreyDark),
      ),
    );
  }

  OutlineInputBorder _border({bool focused = false}) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: focused ? WorkaColors.blue : WorkaColors.divider,
          width: focused ? 1.5 : 1.0,
        ),
      );
}
