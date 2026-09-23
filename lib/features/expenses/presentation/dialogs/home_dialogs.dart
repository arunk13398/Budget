import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import '../providers/expense_provider.dart';

void showDeleteConfirmation(BuildContext context, WidgetRef ref, String id) {
  showDialog(
    context: context,
    builder: (context) {
      return Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        elevation: 16,
        backgroundColor: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFFCA5A5), width: 1.2),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.2),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.delete_forever_rounded,
                  color: Color(0xFFEF4444),
                  size: 28,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Delete Transaction',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Are you sure you want to delete this transaction?\nThis action cannot be undone.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: const BorderSide(color: Color(0xFFE2E8F0)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        ref.read(expenseNotifierProvider.notifier).deleteExpense(id);
                        Navigator.pop(context);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFEF4444),
                        foregroundColor: Colors.white,
                        elevation: 4,
                        shadowColor: const Color(0xFFEF4444).withValues(alpha: 0.4),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        'Delete',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}

void showGroupingDialog({
  required BuildContext context,
  required List<String> namesToGroup,
  required Map<String, String> categoryGroups,
  required Map<String, int> groupColors,
  required Map<String, double> groupLimits,
  required Function(String label, int color, double? limit) onSave,
}) {
  final TextEditingController labelController = TextEditingController();
  final TextEditingController limitController = TextEditingController();
  int selectedColor = Colors.blue.toARGB32();

  final normalizedFirstName = namesToGroup.isNotEmpty ? namesToGroup[0].trim().toUpperCase() : null;
  if (normalizedFirstName != null && namesToGroup.length == 1 && categoryGroups.containsKey(normalizedFirstName)) {
    final existingGroup = categoryGroups[normalizedFirstName]!;
    labelController.text = existingGroup;
    selectedColor = groupColors[existingGroup] ?? Colors.blue.toARGB32();
    limitController.text = groupLimits[existingGroup]?.toStringAsFixed(0) ?? '';
  }

  final List<Color> colors = [
    const Color(0xFF3B82F6), // Blue
    const Color(0xFFEF4444), // Red
    const Color(0xFF10B981), // Emerald
    const Color(0xFFF97316), // Orange
    const Color(0xFF8B5CF6), // Purple
    const Color(0xFF14B8A6), // Teal
    const Color(0xFFEC4899), // Pink
    const Color(0xFF6366F1), // Indigo
  ];

  bool showCustomPicker =
      !colors.any((c) => c.toARGB32() == selectedColor);

  showDialog(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
            elevation: 16,
            backgroundColor: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: SizedBox(
                width: MediaQuery.of(context).size.width * 0.85,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF1E40AF), Color(0xFF3B82F6)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(14),
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF2563EB).withValues(alpha: 0.3),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: const Icon(
                              Icons.label_rounded,
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  namesToGroup.isEmpty ? 'Create Label' : 'Group Selection',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                    color: Color(0xFF0F172A),
                                    letterSpacing: -0.3,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                const Text(
                                  'Organize & budget your expenses',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: Color(0xFF2563EB),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'NAME & BUDGET',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF475569),
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: labelController,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF0F172A),
                        ),
                        decoration: InputDecoration(
                          hintText: 'e.g. Shopping, Rent',
                          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                          prefixIcon: const Icon(Icons.label_outlined, color: Color(0xFF2563EB), size: 20),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(color: Color(0xFF2563EB), width: 2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: limitController,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF0F172A),
                        ),
                        decoration: InputDecoration(
                          hintText: 'Optional monthly limit',
                          hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                          prefixIcon: const Icon(Icons.currency_rupee_rounded, color: Color(0xFF2563EB), size: 20),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(color: Color(0xFF2563EB), width: 2),
                          ),
                        ),
                      ),
                      if (groupColors.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                color: Color(0xFF2563EB),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            const Text(
                              'EXISTING LABELS',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF475569),
                                letterSpacing: 0.8,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: groupColors.keys.map((label) {
                            final color = Color(groupColors[label]!);
                            final isSelected = labelController.text == label;
                            return GestureDetector(
                              onTap: () {
                                setDialogState(() {
                                  labelController.text = label;
                                  selectedColor = groupColors[label]!;
                                  limitController.text = groupLimits[label]?.toStringAsFixed(0) ?? '';
                                });
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: isSelected ? color.withValues(alpha: 0.12) : const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: isSelected ? color : const Color(0xFFE2E8F0), width: 1.5),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      label,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                        color: isSelected ? color : const Color(0xFF334155),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF2563EB),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              const Text(
                                'THEME COLOR',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF475569),
                                  letterSpacing: 0.8,
                                ),
                              ),
                            ],
                          ),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: const Color(0xFFE2E8F0),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 12,
                                      height: 12,
                                      decoration: BoxDecoration(
                                        color: Color(selectedColor),
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: Colors.white,
                                          width: 1.5,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Color(selectedColor)
                                                .withValues(alpha: 0.3),
                                            blurRadius: 4,
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      '#${(selectedColor & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}',
                                      style: const TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.bold,
                                        fontFamily: 'monospace',
                                        color: Color(0xFF334155),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              InkWell(
                                onTap: () {
                                  setDialogState(() {
                                    showCustomPicker = !showCustomPicker;
                                  });
                                },
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: showCustomPicker
                                        ? const Color(0xFFEFF6FF)
                                        : const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: showCustomPicker
                                          ? const Color(0xFF3B82F6)
                                          : const Color(0xFFCBD5E1),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        showCustomPicker
                                            ? Icons.palette_outlined
                                            : Icons.colorize_rounded,
                                        size: 13,
                                        color: showCustomPicker
                                            ? const Color(0xFF2563EB)
                                            : const Color(0xFF475569),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        showCustomPicker
                                            ? 'Presets'
                                            : 'Color Picker',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: showCustomPicker
                                              ? const Color(0xFF2563EB)
                                              : const Color(0xFF475569),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      if (showCustomPicker) ...[
                        Container(
                          padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: const Color(0xFFE2E8F0),
                            ),
                          ),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              const areaHeightPercent = 0.48;
                              final pickerHeight =
                                  (constraints.maxWidth * areaHeightPercent) +
                                      62.0;
                              return SizedBox(
                                height: pickerHeight,
                                child: ClipRect(
                                  child: OverflowBox(
                                    alignment: Alignment.topCenter,
                                    maxHeight: double.infinity,
                                    child: ColorPicker(
                                      pickerColor: Color(selectedColor),
                                      onColorChanged: (newColor) {
                                        setDialogState(() {
                                          selectedColor = newColor.toARGB32();
                                        });
                                      },
                                      colorPickerWidth: constraints.maxWidth,
                                      pickerAreaHeightPercent:
                                          areaHeightPercent,
                                      enableAlpha: false,
                                      displayThumbColor: true,
                                      paletteType: PaletteType.hsvWithHue,
                                      labelTypes: const [],
                                      hexInputBar: false,
                                      pickerAreaBorderRadius:
                                          BorderRadius.circular(12),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ] else ...[
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            ...colors.map((color) {
                              final isSelected =
                                  selectedColor == color.toARGB32();
                              return GestureDetector(
                                onTap: () => setDialogState(
                                    () => selectedColor = color.toARGB32()),
                                child: Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: color,
                                    shape: BoxShape.circle,
                                    border: isSelected
                                        ? Border.all(
                                            color: const Color(0xFF0F172A),
                                            width: 2.5)
                                        : null,
                                    boxShadow: [
                                      if (isSelected)
                                        BoxShadow(
                                          color: color.withValues(alpha: 0.4),
                                          blurRadius: 8,
                                          offset: const Offset(0, 2),
                                        ),
                                    ],
                                  ),
                                  child: isSelected
                                      ? const Icon(Icons.check,
                                          color: Colors.white, size: 18)
                                      : null,
                                ),
                              );
                            }),
                            GestureDetector(
                              onTap: () {
                                setDialogState(() {
                                  showCustomPicker = true;
                                });
                              },
                              child: Tooltip(
                                message: 'Open Color Picker',
                                child: Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: const SweepGradient(
                                      colors: [
                                        Colors.red,
                                        Colors.amber,
                                        Colors.green,
                                        Colors.cyan,
                                        Colors.blue,
                                        Colors.purple,
                                        Colors.red,
                                      ],
                                    ),
                                    border: Border.all(
                                      color: !colors.any((c) =>
                                              c.toARGB32() == selectedColor)
                                          ? const Color(0xFF0F172A)
                                          : const Color(0xFFCBD5E1),
                                      width: !colors.any((c) =>
                                              c.toARGB32() == selectedColor)
                                          ? 2.5
                                          : 1.5,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black
                                            .withValues(alpha: 0.1),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Center(
                                    child: Container(
                                      width: 22,
                                      height: 22,
                                      decoration: BoxDecoration(
                                        color: !colors.any((c) =>
                                                c.toARGB32() ==
                                                selectedColor)
                                            ? Color(selectedColor)
                                            : Colors.white,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        !colors.any((c) =>
                                                c.toARGB32() ==
                                                selectedColor)
                                            ? Icons.check_rounded
                                            : Icons.colorize_rounded,
                                        size: 13,
                                        color: !colors.any((c) =>
                                                c.toARGB32() ==
                                                selectedColor)
                                            ? Colors.white
                                            : const Color(0xFF334155),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(context),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                side: const BorderSide(color: Color(0xFFE2E8F0)),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: const Text(
                                'Cancel',
                                style: TextStyle(
                                  color: Color(0xFF64748B),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFF0F172A),
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF0F172A).withValues(alpha: 0.3),
                                    blurRadius: 10,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: ElevatedButton(
                                onPressed: () {
                                  final label = labelController.text.trim();
                                  if (label.isNotEmpty) {
                                    onSave(label, selectedColor, double.tryParse(limitController.text));
                                    Navigator.pop(context);
                                  }
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.transparent,
                                  shadowColor: Colors.transparent,
                                  padding: const EdgeInsets.symmetric(vertical: 14),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                ),
                                child: const Text(
                                  'Save Changes',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
    },
  );
}
