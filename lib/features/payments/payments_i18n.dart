import 'package:flutter/widgets.dart';

class PaymentsI18n {
  PaymentsI18n._();

  static const Map<String, Map<String, String>> _dict = {
    'ru': {
      'contact_unlock': 'Открыть контакт',
      'buy_credits': 'Купить кредиты',
      'credits': 'Кредиты',
      'balance': 'Баланс',
      'history': 'История',
      'history_empty': 'Пока пусто',
      'promote_job': 'Продвижение вакансии',
      'verification': 'Верификация работодателя',
      'pay': 'Оплатить',
      'clear': 'Очистить',
      'done': 'Готово',
      'loading': 'Загрузка...',
      'failed': 'Ошибка',
      'success': 'Успешно',
      'upload_docs': 'Загрузить документы',
      'status_pending': 'На проверке',
      'status_approved': 'Одобрено',
      'status_rejected': 'Отклонено',
      'status_none': 'Не отправлено',
      'open_profile': 'Открыть профиль',
      'contact_unlocked': 'Контакт открыт',
      'buy_to_unlock': 'Для открытия контакта нужны кредиты',
      'credits_insufficient': 'Недостаточно кредитов',
      'close': 'Закрыть',
    },
    'en': {
      'contact_unlock': 'Unlock contact',
      'buy_credits': 'Buy credits',
      'credits': 'Credits',
      'balance': 'Balance',
      'history': 'History',
      'history_empty': 'No history yet',
      'promote_job': 'Promote job',
      'verification': 'Employer verification',
      'pay': 'Pay',
      'clear': 'Clear',
      'done': 'Done',
      'loading': 'Loading...',
      'failed': 'Error',
      'success': 'Success',
      'upload_docs': 'Upload documents',
      'status_pending': 'Pending',
      'status_approved': 'Approved',
      'status_rejected': 'Rejected',
      'status_none': 'Not submitted',
      'open_profile': 'Open profile',
      'contact_unlocked': 'Contact unlocked',
      'buy_to_unlock': 'Credits required to unlock contact',
      'credits_insufficient': 'Not enough credits',
      'close': 'Close',
    },
  };

  static String t(BuildContext context, String key) {
    final lang = Localizations.localeOf(context).languageCode.toLowerCase();
    final map = _dict[lang] ?? _dict['ru']!;
    return map[key] ?? _dict['ru']![key] ?? key;
  }
}
