import 'package:flutter/widgets.dart';

class MonetizationI18n {
  static const Map<String, Map<String, String>> _map = {
    'ru': {
      'worker_plus': 'Worker Plus',
      'upgrade': 'Перейти на Pro',
      'locked_business_soon': 'Доступно в Business плане (скоро)',
      'learn_more': 'Узнать больше',
      'notify_me': 'Уведомить меня',
      'cv_limit_title': 'Лимит CV достигнут',
      'cv_limit_subtitle': 'Добавьте больше CV с Worker Plus.',
      'job_limit_title': 'Лимит вакансий достигнут',
      'job_limit_subtitle':
          'Выберите план для размещения большего числа вакансий.',
      'coming_soon': 'Скоро',
      'highlight_cv': 'Выделить CV',
      'highlight_job': 'Продвижение вакансии',
      'incomplete_cvs': 'Незаконченные CV',
      'incomplete_jobs': 'Незаконченные вакансии',
      'continue': 'Дополнить',
      'incomplete': 'Не закончено',
      'plans': 'Тарифы',
      'edit': 'Редактировать',
      'done': 'Готово',
      'highlighted_until': 'Выделено до',
    },
    'en': {
      'worker_plus': 'Worker Plus',
      'upgrade': 'Upgrade',
      'locked_business_soon': 'Available in Business plan (coming soon)',
      'learn_more': 'Learn more',
      'notify_me': 'Notify me',
      'cv_limit_title': 'CV limit reached',
      'cv_limit_subtitle': 'Add more CVs with Worker Plus.',
      'job_limit_title': 'Job limit reached',
      'job_limit_subtitle': 'Choose a plan to post more vacancies.',
      'coming_soon': 'Coming soon',
      'highlight_cv': 'Highlight CV',
      'highlight_job': 'Highlight job',
      'incomplete_cvs': 'Incomplete CVs',
      'incomplete_jobs': 'Incomplete jobs',
      'continue': 'Continue',
      'incomplete': 'Incomplete',
      'plans': 'Plans',
      'edit': 'Edit',
      'done': 'Done',
      'highlighted_until': 'Highlighted until',
    },
  };

  static String t(BuildContext context, String key) {
    final lang =
        Localizations.localeOf(
          context,
        ).languageCode.toLowerCase().startsWith('ru')
        ? 'ru'
        : 'en';
    return _map[lang]?[key] ?? _map['ru']?[key] ?? key;
  }
}
