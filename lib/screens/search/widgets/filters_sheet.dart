import 'multi_select_sheet.dart';

import 'package:flutter/material.dart';

import '../../../theme/worka_colors.dart';
import '../../../widgets/worka_header.dart';
import '../models/search_filters.dart';
import 'search_filters_config.dart';
import 'worka_filters_ui.dart';

class FiltersScreen extends StatefulWidget {
  final SearchFilters initial;
  const FiltersScreen({super.key, required this.initial});

  @override
  State<FiltersScreen> createState() => _FiltersScreenState();
}

class _FiltersScreenState extends State<FiltersScreen> {
  late Set<String> _categories;
  late Set<String> _employment;
  late Set<String> _languages;
  late Set<String> _experience;

  // salary
  final _salaryCtrl = TextEditingController();
  String _salaryPeriod = 'В месяц';
  String _salaryCurrency = 'EUR';

  bool _housing = false;
  bool _transport = false;
  bool _teen = false;
  bool _disability = false;
  bool _helpsWithDocuments = false;
  bool _noLanguageRequired = false;

  static const Map<String, IconData> _categoryIcons = {
    'Строительство и рабочие специальности': Icons.construction,
    'Строитель': Icons.handyman,
    'Сварщик': Icons.precision_manufacturing,
    'Маляр': Icons.format_paint,
    'Сантехник': Icons.plumbing,
    'Электрик': Icons.electrical_services,
    'Плиточник': Icons.grid_view,
    'Плотник / столяр': Icons.carpenter,
    'Кровельщик': Icons.roofing,
    'Каменщик': Icons.domain,
    'Монтажник': Icons.build,
    'Слесарь': Icons.build_circle,
    'Разнорабочий': Icons.construction,
    'Мастер по ремонту': Icons.home_repair_service,
    'Логистика и производство': Icons.local_shipping,
    'Склад': Icons.warehouse,
    'Комплектовщик': Icons.inventory_2,
    'Грузчик': Icons.move_up,
    'Водитель': Icons.local_shipping,
    'Курьер': Icons.delivery_dining,
    'Производство': Icons.factory,
    'Оператор станка': Icons.precision_manufacturing,
    'Упаковщик': Icons.inventory,
    'Контроль качества': Icons.fact_check,
    'Продажи и сервис': Icons.shopping_bag,
    'Продавец': Icons.shopping_bag,
    'Кассир': Icons.point_of_sale,
    'Менеджер по продажам': Icons.sell,
    'Оператор call-центра': Icons.support_agent,
    'Администратор': Icons.badge,
    'Официант': Icons.restaurant,
    'Бариста': Icons.coffee,
    'Бармен': Icons.local_bar,
    'Офис и администрирование': Icons.business_center,
    'Офис-менеджер': Icons.business_center,
    'Секретарь': Icons.assignment_ind,
    'Бухгалтер': Icons.account_balance,
    'HR / рекрутер': Icons.group,
    'Юрист': Icons.gavel,
    'Ассистент': Icons.work_outline,
    'Оператор ПК': Icons.keyboard,
    'IT и digital': Icons.terminal,
    'Разработчик': Icons.terminal,
    'Тестировщик': Icons.bug_report,
    'Системный администратор': Icons.dns,
    'Дизайнер': Icons.palette,
    'Маркетолог': Icons.campaign,
    'Аналитик': Icons.query_stats,
    'Техподдержка': Icons.headset_mic,
    'Медицина': Icons.medical_services,
    'Врач': Icons.medical_services,
    'Медсестра': Icons.vaccines,
    'Фармацевт': Icons.local_pharmacy,
    'Лаборант': Icons.biotech,
    'Сиделка': Icons.elderly,
    'Красота и спорт': Icons.content_cut,
    'Парикмахер': Icons.content_cut,
    'Мастер маникюра': Icons.back_hand,
    'Косметолог': Icons.face,
    'Массажист': Icons.self_improvement,
    'Фитнес-тренер': Icons.fitness_center,
    'Дом и сервис': Icons.home,
    'Уборка': Icons.cleaning_services,
    'Няня': Icons.child_friendly,
    'Охранник': Icons.security,
    'Садовник': Icons.yard,
    'Домработница': Icons.home,
    'Общественное питание': Icons.restaurant_menu,
    'Повар': Icons.restaurant_menu,
    'Пекарь': Icons.bakery_dining,
    'Кондитер': Icons.cake,
    'Транспорт и авто': Icons.local_taxi,
    'Такси': Icons.local_taxi,
    'Автослесарь': Icons.car_repair,
    'Автомойка': Icons.local_car_wash,
    'Автоэлектрик': Icons.electric_car,
    'Финансы': Icons.payments,
    'Финансист': Icons.payments,
    'Кредитный специалист': Icons.credit_score,
    'Страхование': Icons.verified_user,
  };

  @override
  void initState() {
    super.initState();
    _categories = {...widget.initial.categories};
    _employment = {...widget.initial.employment};
    _languages = {...widget.initial.languages};
    _experience = {...widget.initial.experience};

    _salaryPeriod = widget.initial.salaryPeriod;
    _salaryCurrency = widget.initial.salaryCurrency;
    _salaryCtrl.text = widget.initial.salaryAmount?.toString() ?? '';

    _housing = widget.initial.housing;
    _transport = widget.initial.transport;
    _teen = widget.initial.teen;
    _disability = widget.initial.disability;
    _helpsWithDocuments = widget.initial.helpsWithDocuments;
    _noLanguageRequired = widget.initial.noLanguageRequired;
  }

  @override
  void dispose() {
    _salaryCtrl.dispose();
    super.dispose();
  }

  void _clear() {
    setState(() {
      _categories.clear();
      _employment.clear();
      _languages.clear();
      _experience.clear();

      _salaryCtrl.clear();
      _salaryPeriod = 'В месяц';
      _salaryCurrency = 'EUR';

      _housing = false;
      _transport = false;
      _teen = false;
      _disability = false;
      _helpsWithDocuments = false;
      _noLanguageRequired = false;
    });
  }

  void _done() {
    final salaryAmount = double.tryParse(
      _salaryCtrl.text.trim().replaceAll(',', '.'),
    );
    Navigator.pop(
      context,
      widget.initial.copyWith(
        categories: _categories,
        employment: _employment,
        languages: _languages,
        experience: _experience,
        salaryAmount: salaryAmount,
        clearSalaryAmount: _salaryCtrl.text.trim().isEmpty,
        salaryPeriod: _salaryPeriod,
        salaryCurrency: _salaryCurrency,
        clearSalaryFromEur: true, // пересчёт сделает SearchScreen/сервис
        housing: _housing,
        transport: _transport,
        teen: _teen,
        disability: _disability,
        helpsWithDocuments: _helpsWithDocuments,
        noLanguageRequired: _noLanguageRequired,
      ),
    );
  }

  Future<void> _openMulti({
    required String title,
    required List<String> items,
    required Set<String> selected,
    Map<String, List<String>>? grouped,
  }) async {
    IconData? categoryIconBuilder(String label) =>
        _categoryIcons[label] ?? Icons.category;

    final res = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      showDragHandle: true,
      builder: (_) => MultiSelectSheet(
        title: title,
        items: items,
        selected: selected,
        grouped: grouped,
        itemIconBuilder: title == 'Категория' ? categoryIconBuilder : null,
      ),
    );

    if (res == null) return;
    setState(() {
      selected
        ..clear()
        ..addAll(res);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF4A6FDB),
      body: Column(
        children: [
          WorkaHeader(
            title: 'Фильтры',
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
          ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                children: [
                  WorkaFilterSectionCard(
                    icon: Icons.payments,
                    title: 'Salary',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _FilterLabel(
                          title: 'Зарплата от',
                          icon: const Icon(
                            Icons.payments,
                            color: WorkaColors.orange,
                            size: 20,
                          ),
                          trailing: Text(
                            _salaryCurrency,
                            style: const TextStyle(
                              color: WorkaColors.textGreyDark,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        WorkaFilterInputShell(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SizedBox(
                                height: 56,
                                child: TextField(
                                  controller: _salaryCtrl,
                                  keyboardType: TextInputType.number,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: WorkaColors.textGreyDark,
                                  ),
                                  decoration: InputDecoration(
                                    hintText: 'Например 70',
                                    hintStyle: const TextStyle(
                                      color: WorkaColors.textGrey,
                                      fontWeight: FontWeight.w700,
                                    ),
                                    filled: true,
                                    fillColor: Colors.white,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 12,
                                    ),
                                    enabledBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      borderSide: const BorderSide(
                                        color: WorkaColors.fieldBorder,
                                      ),
                                    ),
                                    focusedBorder: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(16),
                                      borderSide: const BorderSide(
                                        color: WorkaColors.blue,
                                        width: 1.8,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: WorkaFilterInputShell(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const _FilterLabel(
                                      title: 'Период',
                                      icon: Icon(
                                        Icons.calendar_today_outlined,
                                        color: WorkaColors.orange,
                                        size: 22,
                                      ),
                                      isDropdown: true,
                                    ),
                                    _SmallDropdown(
                                      value: _salaryPeriod,
                                      items: SearchFiltersConfig.salaryPeriods,
                                      onChanged: (v) =>
                                          setState(() => _salaryPeriod = v),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: WorkaFilterInputShell(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const _FilterLabel(
                                      title: 'Валюта',
                                      icon: Icon(
                                        Icons.currency_exchange,
                                        color: WorkaColors.orange,
                                        size: 22,
                                      ),
                                      isDropdown: true,
                                    ),
                                    _SmallDropdown(
                                      value: _salaryCurrency,
                                      items: SearchFiltersConfig.currencies,
                                      onChanged: (v) =>
                                          setState(() => _salaryCurrency = v),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  WorkaFilterSectionCard(
                    icon: Icons.work_outline,
                    title: 'Job type',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _FilterLabel(
                          title: 'Категория',
                          icon: Icon(
                            Icons.work_outline,
                            color: WorkaColors.orange,
                            size: 20,
                          ),
                          isDropdown: true,
                        ),
                        WorkaFilterSelectRow(
                          label: '',
                          value: _categories.isEmpty
                              ? 'Не выбрано'
                              : 'Выбрано: ${_categories.length}',
                          hasValue: _categories.isNotEmpty,
                          onTap: () => _openMulti(
                            title: 'Категория',
                            items: const [],
                            selected: _categories,
                            grouped: SearchFiltersConfig.categoryGroups,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const _FilterLabel(
                          title: 'График',
                          icon: Icon(
                            Icons.work_outline,
                            color: WorkaColors.orange,
                            size: 20,
                          ),
                        ),
                        WorkaFilterInputShell(
                          child: Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            children: SearchFiltersConfig.employmentTypes.map((
                              v,
                            ) {
                              final sel = _employment.contains(v);
                              return WorkaFilterPill(
                                text: v,
                                selected: sel,
                                onTap: () {
                                  setState(() {
                                    if (sel) {
                                      _employment.remove(v);
                                    } else {
                                      _employment.add(v);
                                    }
                                  });
                                },
                              );
                            }).toList(),
                          ),
                        ),
                      ],
                    ),
                  ),

                  WorkaFilterSectionCard(
                    icon: Icons.rule_folder_outlined,
                    title: 'Requirements',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const _FilterLabel(
                          title: 'Язык',
                          icon: Icon(
                            Icons.translate,
                            color: WorkaColors.orange,
                            size: 20,
                          ),
                          isDropdown: true,
                        ),
                        WorkaFilterSelectRow(
                          label: '',
                          value: _languages.isEmpty
                              ? 'Не выбрано'
                              : 'Выбрано: ${_languages.length}',
                          hasValue: _languages.isNotEmpty,
                          onTap: () => _openMulti(
                            title: 'Язык',
                            items: SearchFiltersConfig.languages,
                            selected: _languages,
                          ),
                        ),
                        const SizedBox(height: 12),
                        WorkaFilterInputShell(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Padding(
                                padding: EdgeInsets.only(bottom: 8),
                                child: Text(
                                  'Опыт работы',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                    color: WorkaColors.textDark,
                                  ),
                                ),
                              ),
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: SearchFiltersConfig.experiences.map((
                                  v,
                                ) {
                                  final sel = _experience.contains(v);
                                  return WorkaFilterPill(
                                    text: v,
                                    selected: sel,
                                    onTap: () {
                                      setState(() {
                                        if (sel) {
                                          _experience.remove(v);
                                        } else {
                                          _experience.add(v);
                                        }
                                      });
                                    },
                                  );
                                }).toList(),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  WorkaFilterSectionCard(
                    icon: Icons.card_giftcard_outlined,
                    title: 'Benefits',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SwitchFilterRow(
                          title: 'Жильё',
                          icon: const Icon(
                            Icons.home_outlined,
                            color: WorkaColors.orange,
                            size: 20,
                          ),
                          value: _housing,
                          onChanged: (v) => setState(() => _housing = v),
                        ),
                        const SizedBox(height: 10),
                        _SwitchFilterRow(
                          title: 'Развозка',
                          icon: const Icon(
                            Icons.directions_car_outlined,
                            color: WorkaColors.orange,
                            size: 20,
                          ),
                          value: _transport,
                          onChanged: (v) => setState(() => _transport = v),
                        ),
                        const SizedBox(height: 10),
                        _SwitchFilterRow(
                          title: 'Подходит подросткам',
                          icon: const Image(
                            image: AssetImage('assets/icons/icon_teens.png'),
                            width: 20,
                            height: 20,
                          ),
                          value: _teen,
                          onChanged: (v) => setState(() => _teen = v),
                        ),
                        const SizedBox(height: 10),
                        _SwitchFilterRow(
                          title: 'Подходит для инвалидов',
                          icon: const Icon(
                            Icons.accessible_outlined,
                            color: WorkaColors.orange,
                            size: 20,
                          ),
                          value: _disability,
                          onChanged: (v) => setState(() => _disability = v),
                        ),
                        const SizedBox(height: 10),
                        SwitchListTile(
                          value: _helpsWithDocuments,
                          onChanged: (v) =>
                              setState(() => _helpsWithDocuments = v),
                          contentPadding: EdgeInsets.zero,
                          activeThumbColor: WorkaColors.orange,
                          title: const Text(
                            'Помощь с документами',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: WorkaColors.textDark,
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        SwitchListTile(
                          value: _noLanguageRequired,
                          onChanged: (v) =>
                              setState(() => _noLanguageRequired = v),
                          contentPadding: EdgeInsets.zero,
                          activeThumbColor: WorkaColors.orange,
                          title: const Text(
                            'Без языка',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: WorkaColors.textDark,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            WorkaFilterBottomActions(
              clearLabel: 'Очистить',
              doneLabel: 'Готово',
              onClear: _clear,
              onDone: _done,
            ),
          ],
        ),
    );
  }
}

class _SmallDropdown extends StatelessWidget {
  final String value;
  final List<String> items;
  final ValueChanged<String> onChanged;

  const _SmallDropdown({
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: WorkaColors.fieldBorder),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: items.contains(value) ? value : items.first,
          dropdownColor: Colors.white,
          iconEnabledColor: WorkaColors.textGreyDark,
          style: const TextStyle(
            color: WorkaColors.textGreyDark,
            fontWeight: FontWeight.w900,
          ),
          items: items.map((e) {
            return DropdownMenuItem(
              value: e,
              child: Text(
                e,
                style: const TextStyle(
                  color: WorkaColors.textGreyDark,
                  fontWeight: FontWeight.w900,
                ),
              ),
            );
          }).toList(),
          onChanged: (v) {
            if (v == null) return;
            onChanged(v);
          },
        ),
      ),
    );
  }
}

class _SwitchFilterRow extends StatelessWidget {
  final String title;
  final Widget icon;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchFilterRow({
    required this.title,
    required this.icon,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: Row(
        children: [
          SizedBox(width: 22, height: 22, child: Center(child: icon)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 16,
                color: WorkaColors.textDark,
              ),
            ),
          ),
          Transform.scale(
            scale: 0.78,
            child: Switch(
              value: value,
              onChanged: onChanged,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              thumbColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return Colors.white;
                }
                return WorkaColors.blue;
              }),
              trackColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return WorkaColors.blue;
                }
                return Colors.white;
              }),
              trackOutlineColor: WidgetStateProperty.all(WorkaColors.blue),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterLabel extends StatelessWidget {
  final String title;
  final Widget icon;
  final Widget? trailing;
  final bool isDropdown;

  const _FilterLabel({
    required this.title,
    required this.icon,
    this.trailing,
    this.isDropdown = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(width: 22, height: 22, child: Center(child: icon)),
          const SizedBox(width: 10),
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: WorkaColors.textDark,
            ),
          ),
          const Spacer(),
          if (trailing != null) trailing!,
          if (isDropdown)
            const Icon(
              Icons.keyboard_arrow_down,
              size: 20,
              color: WorkaColors.textGrey,
            ),
        ],
      ),
    );
  }
}


class _MultiSelectSheet extends StatefulWidget {
  final String title;
  final List<String> items;
  final Set<String> selected;

  const _MultiSelectSheet({
    required this.title,
    required this.items,
    required this.selected,
  });

  @override
  State<_MultiSelectSheet> createState() => _MultiSelectSheetState();
}

class _MultiSelectSheetState extends State<_MultiSelectSheet> {
  late final Set<String> _sel;
  static const Color _clearInactiveBg = Color(0xFFFFD9AE);

  @override
  void initState() {
    super.initState();
    _sel = {...widget.selected};
  }

  void _toggle(String v) {
    setState(() {
      if (_sel.contains(v)) {
        _sel.remove(v);
      } else {
        _sel.add(v);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasSelection = _sel.isNotEmpty;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.78,
        child: Column(
          children: [
            const SizedBox(height: 8),
            Text(
              widget.title,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 18,
                color: WorkaColors.textGreyDark,
              ),
            ),
            const SizedBox(height: 12),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  for (final it in widget.items)
                    _CheckRow(
                      label: it,
                      checked: _sel.contains(it),
                      onToggle: () => _toggle(it),
                    ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: () => setState(_sel.clear),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: hasSelection
                              ? WorkaColors.orange
                              : _clearInactiveBg,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: Text(
                          'Очистить',
                          style: TextStyle(
                            color: hasSelection
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.85),
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pop(context, _sel),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: WorkaColors.blue,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: const Text(
                          'Готово',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CheckRow extends StatelessWidget {
  final String label;
  final bool checked;
  final VoidCallback onToggle;
  const _CheckRow({
    required this.label,
    required this.checked,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onToggle,
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(
          children: [
            Checkbox(
              value: checked,
              activeColor: WorkaColors.blue,
              onChanged: (_) => onToggle(),
            ),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: checked ? FontWeight.w900 : FontWeight.w800,
                  color: WorkaColors.textGreyDark,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
