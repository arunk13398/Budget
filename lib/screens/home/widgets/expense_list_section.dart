import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../features/expenses/domain/entities/expense.dart';
import 'transaction_item.dart';

class ExpenseListSection extends StatefulWidget {
  final List<Expense> expenses;
  final int selectedMonth;
  final String cardName;
  final Map<String, String> categoryGroups;
  final Map<String, String> transactionGroups;
  final Map<String, int> groupColors;
  final bool isDueDateFiltered;
  final DateTime? cardDueDateVal;
  final List<String> selectedExpenseNames;
  final bool isSyncing;
  final VoidCallback onSync;
  final VoidCallback onAddMore;
  final VoidCallback onFilterMerchants;
  final Function(bool) onToggleDueDateFilter;
  final VoidCallback onResetFilters;
  final Function(String) onDeleteExpense;
  final Function(String) onGroupExpense;
  final Gradient gradient;

  const ExpenseListSection({
    super.key,
    required this.expenses,
    required this.selectedMonth,
    required this.cardName,
    required this.categoryGroups,
    required this.transactionGroups,
    required this.groupColors,
    required this.isDueDateFiltered,
    this.cardDueDateVal,
    required this.selectedExpenseNames,
    required this.isSyncing,
    required this.onSync,
    required this.onAddMore,
    required this.onFilterMerchants,
    required this.onToggleDueDateFilter,
    required this.onResetFilters,
    required this.onDeleteExpense,
    required this.onGroupExpense,
    required this.gradient,
  });

  @override
  State<ExpenseListSection> createState() => _ExpenseListSectionState();
}

class _ExpenseListSectionState extends State<ExpenseListSection> {
  int _transactionTabIndex = 0;

  @override
  Widget build(BuildContext context) {
    final filteredExpenses = widget.expenses.where((expense) {
      if (widget.isDueDateFiltered && widget.cardDueDateVal != null) {
        final endDate = DateTime(
          expense.date.year,
          widget.selectedMonth + 1,
          widget.cardDueDateVal!.day,
        );
        final startDate = DateTime(
          endDate.year,
          endDate.month - 1,
          endDate.day,
        );
        bool withinRange =
            (expense.date.isAfter(startDate) ||
                expense.date.isAtSameMomentAs(startDate)) &&
            (expense.date.isBefore(endDate) ||
                expense.date.isAtSameMomentAs(endDate));
        bool matchesBank =
            widget.cardName.isEmpty ||
            expense.bank.toUpperCase().contains(
              widget.cardName.toUpperCase(),
            ) ||
            widget.cardName.toUpperCase().contains(expense.bank.toUpperCase());
        final normalizedName = expense.name.trim().toUpperCase();
        final groupLabel = widget.transactionGroups[expense.id] ?? widget.categoryGroups[normalizedName];
        bool matchesFilter =
            widget.selectedExpenseNames.isEmpty ||
            widget.selectedExpenseNames.contains(normalizedName) ||
            (groupLabel != null &&
                widget.selectedExpenseNames.contains(groupLabel));
        return withinRange && matchesBank && matchesFilter;
      }
      bool matchesMonth = expense.date.month == (widget.selectedMonth + 1);
      bool matchesBank =
          widget.cardName.isEmpty ||
          expense.bank.toUpperCase().contains(widget.cardName.toUpperCase()) ||
          widget.cardName.toUpperCase().contains(expense.bank.toUpperCase());
      final normalizedName = expense.name.trim().toUpperCase();
      final groupLabel = widget.transactionGroups[expense.id] ?? widget.categoryGroups[normalizedName];
      bool matchesFilter =
          widget.selectedExpenseNames.isEmpty ||
          widget.selectedExpenseNames.contains(normalizedName) ||
          (groupLabel != null &&
              widget.selectedExpenseNames.contains(groupLabel));
      return matchesMonth && matchesBank && matchesFilter;
    }).toList()..sort((a, b) => b.date.compareTo(a.date));

    final debitExpenses = filteredExpenses
        .where((e) => e.type == 'spent' || e.type == 'debited')
        .toList();
    final creditExpenses = filteredExpenses
        .where((e) => e.type == 'credited')
        .toList();

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15),
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: DefaultTabController(
        length: 2,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(15, 15, 15, 0),
              child: Row(
                children: [
                  const Text(
                    'History',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () =>
                        widget.onToggleDueDateFilter(!widget.isDueDateFiltered),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(
                          color: Colors.grey.shade300,
                          width: 0.5,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.only(left: 10),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Due',
                              style: TextStyle(
                                color: Colors.black,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(
                              height: 27,
                              width: 25,
                              child: Checkbox(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                side: BorderSide(
                                  color: Colors.grey.shade400,
                                  width: 1.2,
                                ),
                                fillColor:
                                    WidgetStateProperty.resolveWith<Color>(
                                      (states) =>
                                          states.contains(WidgetState.selected)
                                          ? Colors.black
                                          : Colors.white,
                                    ),
                                checkColor: Colors.white,
                                value: widget.isDueDateFiltered,
                                onChanged: (val) =>
                                    widget.onToggleDueDateFilter(val ?? false),
                              ),
                            ),
                            const SizedBox(width: 5),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: widget.selectedExpenseNames.isNotEmpty
                        ? widget.onResetFilters
                        : widget.onSync,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: widget.selectedExpenseNames.isNotEmpty
                            ? Colors.red.shade50
                            : Colors.black,
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 15,
                          vertical: 6,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (widget.selectedExpenseNames.isEmpty &&
                                widget.isSyncing) ...[
                              const SizedBox(
                                width: 12,
                                height: 12,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 1.5,
                                ),
                              ),
                              const SizedBox(width: 6),
                            ],
                            Text(
                              widget.selectedExpenseNames.isNotEmpty
                                  ? 'Reset'
                                  : (widget.isSyncing ? '' : 'Sync'),
                              style: TextStyle(
                                color: widget.selectedExpenseNames.isNotEmpty
                                    ? Colors.red
                                    : Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: widget.onAddMore,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 15,
                          vertical: 6,
                        ),
                        child: const Text(
                          'Add More',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton(
                    onPressed: widget.onFilterMerchants,
                    icon: const Icon(Icons.filter_list_outlined, size: 20),
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.all(8),
                    tooltip: 'Filter Merchants',
                  ),
                  const SizedBox(width: 10),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 15),
              child: TabBar(
                onTap: (index) => setState(() => _transactionTabIndex = index),
                dividerColor: Colors.white,
                labelColor: Colors.black,
                unselectedLabelColor: Colors.grey,
                indicatorColor: Colors.black,
                indicatorSize: TabBarIndicatorSize.label,
                labelStyle: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
                tabs: [
                  Tab(text: 'DEBIT (${debitExpenses.length})'),
                  Tab(text: 'CREDIT (${creditExpenses.length})'),
                ],
              ),
            ),
            _transactionTabIndex == 0
                ? _buildTransactionList(debitExpenses)
                : _buildTransactionList(creditExpenses),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionList(List<Expense> expenses) {
    if (expenses.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(
          child: Text(
            'No transactions for this selection',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      itemCount: expenses.length,
      separatorBuilder: (context, index) {
        final current = expenses[index];
        final next = (index + 1 < expenses.length) ? expenses[index + 1] : null;
        if (next == null) return const SizedBox.shrink();
        return (current.date.day == next.date.day &&
                current.date.month == next.date.month &&
                current.date.year == next.date.year)
            ? Divider(color: Colors.grey.shade100)
            : const SizedBox.shrink();
      },
      itemBuilder: (context, index) {
        final expense = expenses[index];
        final bool showHeader =
            index == 0 ||
            expenses[index - 1].date.day != expense.date.day ||
            expenses[index - 1].date.month != expense.date.month ||
            expenses[index - 1].date.year != expense.date.year;

        return Column(
          children: [
            if (showHeader)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Expanded(child: Divider(color: Colors.grey.shade200)),
                    const SizedBox(width: 10),
                    Text(
                      DateFormat(
                        'dd/MMM/yyyy',
                      ).format(expense.date).toUpperCase(),
                      style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Divider(color: Colors.grey.shade200)),
                  ],
                ),
              ),
            TransactionItem(
              expense: expense,
              isDueDateFiltered: widget.isDueDateFiltered,
              categoryGroups: widget.categoryGroups,
              transactionGroups: widget.transactionGroups,
              groupColors: widget.groupColors,
              onDelete: widget.onDeleteExpense,
              onGroup: widget.onGroupExpense,
              gradient: widget.gradient,
            ),
          ],
        );
      },
    );
  }
}
