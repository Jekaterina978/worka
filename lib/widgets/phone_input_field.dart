import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/worka_colors.dart';
import 'contact_fields.dart';

class PhoneInputField extends StatelessWidget {
  final TextEditingController controller;
  final String countryCode;
  final ValueChanged<String> onCountryChanged;
  final ValueChanged<String>? onChanged;
  final String hintText;
  final bool enabled;
  final String? Function(String?)? validator;
  final TextInputAction textInputAction;

  const PhoneInputField({
    super.key,
    required this.controller,
    required this.countryCode,
    required this.onCountryChanged,
    this.onChanged,
    this.hintText = '5123 4567',
    this.enabled = true,
    this.validator,
    this.textInputAction = TextInputAction.done,
  });

  Future<void> _pickCountryCode(BuildContext context) async {
    final selected = defaultDialCodes.firstWhere(
      (d) => d.code == countryCode,
      orElse: () => defaultDialCodes.first,
    );

    final picked = await showModalBottomSheet<DialCodeOption>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Код страны',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: WorkaColors.textDark,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: MediaQuery.of(ctx).size.height * 0.62,
                  child: ListView.separated(
                    itemCount: defaultDialCodes.length,
                    separatorBuilder: (_, __) =>
                        const Divider(height: 1, color: WorkaColors.divider),
                    itemBuilder: (context, i) {
                      final c = defaultDialCodes[i];
                      final isSelected = c.code == selected.code;
                      final textColor =
                          isSelected ? WorkaColors.blue : WorkaColors.textGreyDark;

                      return InkWell(
                        onTap: () => Navigator.pop(ctx, c),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Row(
                            children: [
                              Text(c.flag, style: const TextStyle(fontSize: 20)),
                              const SizedBox(width: 6),
                              Text(
                                c.code,
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  color: textColor,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  c.country,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    color: textColor,
                                  ),
                                ),
                              ),
                              if (isSelected)
                                const Icon(Icons.check, color: WorkaColors.blue),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (picked != null) onCountryChanged(picked.code);
  }

  InputDecoration _decoration({
    required BuildContext context,
    required DialCodeOption selected,
  }) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: const TextStyle(
        color: Color(0xFFB3B3B3),
        fontWeight: FontWeight.w400,
      ),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(22),
        borderSide: const BorderSide(color: WorkaColors.fieldBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(22),
        borderSide: const BorderSide(color: WorkaColors.blue, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(22),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(22),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
      prefixIcon: InkWell(
        onTap: enabled ? () => _pickCountryCode(context) : null,
        borderRadius: BorderRadius.circular(22),
        child: Padding(
          padding: const EdgeInsets.only(left: 12, right: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(selected.flag, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 6),
              Text(
                selected.code,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  color: WorkaColors.textDark,
                ),
              ),
              const SizedBox(width: 2),
              const Icon(
                Icons.keyboard_arrow_down,
                color: WorkaColors.textGreyDark,
              ),
              const SizedBox(width: 6),
              Container(width: 1, height: 22, color: WorkaColors.divider),
            ],
          ),
        ),
      ),
      prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selected = defaultDialCodes.firstWhere(
      (d) => d.code == countryCode,
      orElse: () => defaultDialCodes.first,
    );
    return TextFormField(
      controller: controller,
      enabled: enabled,
      keyboardType: TextInputType.phone,
      textInputAction: textInputAction,
      inputFormatters: [
        FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]')),
        LengthLimitingTextInputFormatter(20),
      ],
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: WorkaColors.textDark,
      ),
      decoration: _decoration(context: context, selected: selected),
      validator: validator,
      onChanged: onChanged,
    );
  }
}
