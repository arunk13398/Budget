import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/expense_provider.dart';
import '../providers/expense_state.dart';
import '../../domain/entities/expense.dart';
import '../dialogs/custom_blue_date_picker_dialog.dart';

Future<void> addAlertDialog({
  required BuildContext context,
  required WidgetRef ref,
  required List<String> visibleBanks,
  String? initialBank,
  Map<String, int>? groupColors,
  Function(String merchant, String group)? onGroupAssigned,
  Expense? expenseToEdit,
  String? initialGroup,
  Map<String, String>? categoryGroups,
}) async {
  if (visibleBanks.isEmpty) {
    return showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          elevation: 12,
          backgroundColor: Colors.white,
          child: Container(
            width: MediaQuery.of(context).size.width * 0.85,
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.credit_card_off_rounded,
                    color: Colors.amber.shade800,
                    size: 32,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'No Card Added',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'You must configure and select at least one active bank card in Settings before adding expenses.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Colors.grey.shade600,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0F172A),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      elevation: 4,
                      shadowColor: Colors.black.withValues(alpha: 0.3),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      'Got It',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        fontSize: 13.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  final expenseState = ref.read(expenseNotifierProvider);
  List<Expense> expenses = [];
  if (expenseState is ExpenseLoaded) {
    expenses = expenseState.data.expenses;
  }

  final merchantCounts = <String, int>{};
  for (final exp in expenses) {
    final name = exp.name.trim();
    if (name.isEmpty || name == 'Manual Entry') continue;
    merchantCounts[name] = (merchantCounts[name] ?? 0) + 1;
  }

  final mostUsedMerchants = merchantCounts.keys.toList()
    ..sort((a, b) => merchantCounts[b]!.compareTo(merchantCounts[a]!));
  final topMerchants = mostUsedMerchants.take(8).toList();

  final TextEditingController amountController = TextEditingController(
    text: expenseToEdit != null
        ? (expenseToEdit.amount % 1 == 0
            ? expenseToEdit.amount.toStringAsFixed(0)
            : expenseToEdit.amount.toString())
        : '',
  );
  final TextEditingController merchantController = TextEditingController(
    text: expenseToEdit != null ? expenseToEdit.name : '',
  );
  DateTime selectedDate = expenseToEdit != null ? expenseToEdit.date : DateTime.now();
  String? selectedBank = expenseToEdit != null ? expenseToEdit.bank : (initialBank ?? (visibleBanks.isNotEmpty ? visibleBanks.first : null));
  String? selectedGroup = initialGroup;
  String selectedTransactionType = expenseToEdit != null
      ? (expenseToEdit.type == 'credited' ? 'credited' : 'debited')
      : 'debited';

  String? amountError;
  String? bankError;

  return showDialog(
    context: context,
    barrierDismissible: true,
    builder: (BuildContext context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            elevation: 12,
            backgroundColor: Colors.white,
            child: Container(
              width: MediaQuery.of(context).size.width * 0.85,
              padding: const EdgeInsets.all(22),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            expenseToEdit != null ? Icons.edit_note_rounded : Icons.add_card_rounded,
                            color: Colors.black,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                expenseToEdit != null ? 'Edit Expense' : 'New Expense',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                  color: Color(0xFF0F172A),
                                  letterSpacing: -0.3,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Enter transaction details below',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    const Text(
                      'DETAILS',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF94A3B8),
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 10),

                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              TextFormField(
                                controller: amountController,
                                keyboardType: TextInputType.number,
                                onChanged: (_) {
                                  if (amountError != null) {
                                    setState(() => amountError = null);
                                  }
                                },
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF0F172A),
                                ),
                                decoration: InputDecoration(
                                  filled: true,
                                  fillColor: const Color(0xFFF8FAFC),
                                  prefixText: '₹ ',
                                  prefixStyle: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF0F172A),
                                  ),
                                  hintText: '0',
                                  hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 16),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 13,
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide(
                                      color: amountError != null ? Colors.red : const Color(0xFFE2E8F0),
                                      width: amountError != null ? 1.5 : 1.0,
                                    ),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide(
                                      color: amountError != null ? Colors.red : Colors.blue.shade600,
                                      width: 1.5,
                                    ),
                                  ),
                                ),
                              ),
                              if (amountError != null) ...[
                                const SizedBox(height: 4),
                                Text(
                                  amountError!,
                                  style: const TextStyle(color: Colors.red, fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),

                        InkWell(
                          onTap: () async {
                            final now = DateTime.now();
                            final date = await showDialog<DateTime>(
                              context: context,
                              builder: (context) => CustomBlueDatePickerDialog(
                                initialDate: selectedDate.isAfter(now) ? now : selectedDate,
                                firstDate: DateTime(2020),
                                lastDate: now,
                              ),
                            );
                            if (date != null) {
                              setState(() => selectedDate = date);
                            }
                          },
                          borderRadius: BorderRadius.circular(14),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: const Color(0xFFE2E8F0)),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.calendar_month_rounded,
                                  size: 18,
                                  color: Colors.black,
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  DateFormat('dd MMM').format(selectedDate),
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF1E293B),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    const Text(
                      'TRANSACTION TYPE',
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF94A3B8),
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                selectedTransactionType = 'debited';
                              });
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: selectedTransactionType == 'debited'
                                    ? const Color(0xFF0F172A)
                                    : const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: selectedTransactionType == 'debited'
                                      ? const Color(0xFF0F172A)
                                      : const Color(0xFFE2E8F0),
                                  width: selectedTransactionType == 'debited' ? 1.5 : 1.0,
                                ),
                                boxShadow: selectedTransactionType == 'debited'
                                    ? [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.15),
                                          blurRadius: 6,
                                          offset: const Offset(0, 3),
                                        ),
                                      ]
                                    : null,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.arrow_upward_rounded,
                                    size: 15,
                                    color: selectedTransactionType == 'debited'
                                        ? Colors.redAccent.shade100
                                        : Colors.red.shade400,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Debited',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: selectedTransactionType == 'debited'
                                          ? FontWeight.bold
                                          : FontWeight.w600,
                                      color: selectedTransactionType == 'debited'
                                          ? Colors.white
                                          : const Color(0xFF475569),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                selectedTransactionType = 'credited';
                              });
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(vertical: 10),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: selectedTransactionType == 'credited'
                                    ? const Color(0xFF0F172A)
                                    : const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: selectedTransactionType == 'credited'
                                      ? const Color(0xFF0F172A)
                                      : const Color(0xFFE2E8F0),
                                  width: selectedTransactionType == 'credited' ? 1.5 : 1.0,
                                ),
                                boxShadow: selectedTransactionType == 'credited'
                                    ? [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.15),
                                          blurRadius: 6,
                                          offset: const Offset(0, 3),
                                        ),
                                      ]
                                    : null,
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.arrow_downward_rounded,
                                    size: 15,
                                    color: selectedTransactionType == 'credited'
                                        ? Colors.greenAccent.shade200
                                        : Colors.green.shade600,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Credited',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: selectedTransactionType == 'credited'
                                          ? FontWeight.bold
                                          : FontWeight.w600,
                                      color: selectedTransactionType == 'credited'
                                          ? Colors.white
                                          : const Color(0xFF475569),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    TextFormField(
                      controller: merchantController,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                      onChanged: (val) => setState(() {}),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        hintText: selectedTransactionType == 'credited'
                            ? 'Where did you receive from?'
                            : 'Where did you spend?',
                        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
                        prefixIcon: const Icon(Icons.storefront_rounded, size: 20, color: Color(0xFF64748B)),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                          borderSide: BorderSide(color: Colors.blue.shade600, width: 1.5),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),

                    Row(
                      children: const [
                        Text(
                          'SOURCE',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF94A3B8),
                            letterSpacing: 1.2,
                          ),
                        ),
                        Text(
                          ' *',
                          style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: visibleBanks.map<Widget>((String bank) {
                        final isSelected = selectedBank == bank;
                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              selectedBank = isSelected ? null : bank;
                              if (bankError != null) bankError = null;
                            });
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: isSelected ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected ? const Color(0xFF0F172A) : const Color(0xFFE2E8F0),
                                width: isSelected ? 1.5 : 1.0,
                              ),
                              boxShadow: isSelected
                                  ? [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.2),
                                        blurRadius: 6,
                                        offset: const Offset(0, 3),
                                      ),
                                    ]
                                  : null,
                            ),
                            child: Text(
                              bank,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                color: isSelected ? Colors.white : const Color(0xFF334155),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    if (bankError != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        bankError!,
                        style: const TextStyle(color: Colors.red, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ],

                    if (selectedTransactionType == 'debited' && groupColors != null && groupColors.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      const Text(
                        'CATEGORY LABEL',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF94A3B8),
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: groupColors.keys.map<Widget>((String group) {
                          final color = Color(groupColors[group]!);
                          final isSelected = selectedGroup == group;
                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                selectedGroup = isSelected ? null : group;
                              });
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                              decoration: BoxDecoration(
                                color: isSelected ? color : color.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSelected ? color : color.withValues(alpha: 0.3),
                                  width: isSelected ? 1.5 : 1.0,
                                ),
                                boxShadow: isSelected
                                    ? [
                                        BoxShadow(
                                          color: color.withValues(alpha: 0.35),
                                          blurRadius: 6,
                                          offset: const Offset(0, 3),
                                        ),
                                      ]
                                    : null,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: isSelected ? Colors.white : color,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    group,
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                      color: isSelected ? Colors.white : color,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],

                    if (selectedTransactionType == 'debited' && topMerchants.isNotEmpty) ...[
                      const SizedBox(height: 20),
                      const Text(
                        'MOST USED MERCHANTS',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF94A3B8),
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: topMerchants.map<Widget>((String merchant) {
                          final isSelected = merchantController.text.trim().toUpperCase() == merchant.trim().toUpperCase();
                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                if (isSelected) {
                                  merchantController.clear();
                                } else {
                                  merchantController.text = merchant;
                                  final normalizedMerchant = merchant.trim().toUpperCase();
                                  if (categoryGroups != null && categoryGroups.containsKey(normalizedMerchant)) {
                                    selectedGroup = categoryGroups[normalizedMerchant];
                                  }
                                }
                              });
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                              decoration: BoxDecoration(
                                color: isSelected ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSelected ? const Color(0xFF0F172A) : const Color(0xFFE2E8F0),
                                  width: isSelected ? 1.5 : 1.0,
                                ),
                              ),
                              child: Text(
                                merchant,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                  color: isSelected ? Colors.white : const Color(0xFF475569),
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],

                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              side: const BorderSide(color: Color(0xFFCBD5E1)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            onPressed: () => Navigator.pop(context),
                            child: const Text(
                              'Cancel',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF475569),
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              backgroundColor: const Color(0xFF0F172A),
                              elevation: 4,
                              shadowColor: Colors.black.withValues(alpha: 0.3),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            onPressed: () {
                              final amountText = amountController.text.trim();
                              final parsedAmount = double.tryParse(amountText);

                              setState(() {
                                if (amountText.isEmpty) {
                                  amountError = 'Amount is required';
                                } else if (parsedAmount == null || parsedAmount <= 0) {
                                  amountError = 'Please enter a valid amount';
                                } else {
                                  amountError = null;
                                }
                                bankError = selectedBank == null ? 'Source bank is required' : null;
                              });

                              if (parsedAmount == null || parsedAmount <= 0 || selectedBank == null) {
                                return;
                              }

                              final expense = Expense(
                                id: expenseToEdit != null
                                    ? expenseToEdit.id
                                    : 'temp_${DateTime.now().millisecondsSinceEpoch}',
                                name: merchantController.text.trim().isEmpty
                                    ? selectedBank!
                                    : merchantController.text.trim(),
                                amount: parsedAmount,
                                date: selectedDate,
                                bank: selectedBank!,
                                category: 'Manual',
                                type: selectedTransactionType,
                              );
                              if (onGroupAssigned != null &&
                                  selectedGroup != null &&
                                  merchantController.text.isNotEmpty) {
                                onGroupAssigned(
                                  merchantController.text,
                                  selectedGroup!,
                                );
                              }
                              ref.read(expenseNotifierProvider.notifier).addExpense(expense);
                              Navigator.pop(context);
                            },
                            child: Text(
                              expenseToEdit != null ? 'Save Changes' : 'Add Expense',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                fontSize: 13,
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
          );
        },
      );
    },
  );
}
