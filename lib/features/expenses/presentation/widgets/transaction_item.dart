import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import '../../domain/entities/expense.dart';

class TransactionItem extends StatelessWidget {
  final Expense expense;
  final bool isDueDateFiltered;
  final Map<String, String> categoryGroups;
  final Map<String, String> transactionGroups;
  final Map<String, int> groupColors;
  final Function(String) onDelete;
  final Function(String) onGroup;
  final Function(Expense)? onEdit;
  final Gradient gradient;

  const TransactionItem({
    super.key,
    required this.expense,
    required this.isDueDateFiltered,
    required this.categoryGroups,
    required this.transactionGroups,
    required this.groupColors,
    required this.onDelete,
    required this.onGroup,
    this.onEdit,
    required this.gradient
  });

  IconData _getCategoryIcon(String category) {
    final cat = category.toUpperCase();
    if (cat.contains('FOOD') || cat.contains('DINING') || cat.contains('RESTAURANT') || cat.contains('CAFE')) {
      return Icons.restaurant_rounded;
    } else if (cat.contains('BILL') || cat.contains('RECHARGE') || cat.contains('UTILITY') || cat.contains('ELEC') || cat.contains('WATER') || cat.contains('RENT')) {
      return Icons.receipt_long_rounded;
    } else if (cat.contains('SHOP') || cat.contains('GROCERY') || cat.contains('STORE') || cat.contains('MARKET') || cat.contains('AMAZON') || cat.contains('FLIPKART')) {
      return Icons.shopping_bag_outlined;
    } else if (cat.contains('TRAVEL') || cat.contains('CAB') || cat.contains('FUEL') || cat.contains('RIDE') || cat.contains('AUTO') || cat.contains('METRO')) {
      return Icons.directions_car_rounded;
    } else if (cat.contains('ENT') || cat.contains('MOVIE') || cat.contains('SHOW') || cat.contains('PLAY') || cat.contains('GAME') || cat.contains('NETFLIX')) {
      return Icons.local_play_rounded;
    } else if (cat.contains('MEDICAL') || cat.contains('HEALTH') || cat.contains('DRUG') || cat.contains('HOSP') || cat.contains('PHARM')) {
      return Icons.medical_services_rounded;
    } else if (cat.contains('UNREAD') || cat.contains('NEW')) {
      return Icons.mark_chat_unread_rounded;
    }
    return Icons.credit_card_rounded;
  }

  Widget _buildMerchantAvatar(String merchantName, String? groupLabel, String type) {
    final isCredit = type == 'credited';
    final Color baseColor = isCredit
        ? gradient.colors.first
        : (groupLabel != null && groupColors.containsKey(groupLabel)
            ? Color(groupColors[groupLabel]!)
            : const Color(0xFF475569));

    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: baseColor.withValues(alpha: 0.08),
        shape: BoxShape.circle,
        border: Border.all(
          color: baseColor.withValues(alpha: 0.18),
          width: 1,
        ),
      ),
      child: Center(
        child: Icon(
          isCredit
              ? Icons.arrow_downward_rounded
              : (groupLabel != null
                  ? _getCategoryIcon(groupLabel)
                  : _getCategoryIcon(merchantName)),
          color: baseColor,
          size: 16,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final normalizedName = expense.name.trim().toUpperCase();
    final groupLabel = transactionGroups[expense.id] ?? categoryGroups[normalizedName];
    final isCredit = expense.type == 'credited';
    final bool isUpi = expense.name.toUpperCase().contains('UPI') || expense.bank.toUpperCase().contains('UPI');
    
    String displayName = expense.name.replaceAll(RegExp(r'\s*\(?UPI\)?', caseSensitive: false), '').trim();
    if (displayName.isEmpty || displayName == 'Manual Entry') {
      displayName = expense.bank.isNotEmpty ? expense.bank : 'Manual Entry';
    }

    final isManual = expense.category == 'Manual';

    return Slidable(
      key: ValueKey(expense.id),
      endActionPane: ActionPane(
        motion: const ScrollMotion(),
        extentRatio: (isManual && onEdit != null) ? 0.65 : 0.45,
        children: [
          if (isManual && onEdit != null) ...[
            SlidableAction(
              onPressed: (context) {
                HapticFeedback.lightImpact();
                onEdit!(expense);
              },
              label: 'Edit',
              backgroundColor: Colors.blue.withValues(alpha: 0.15),
              foregroundColor: Colors.blue,
              icon: Icons.edit_outlined,
              borderRadius: BorderRadius.circular(12),
              autoClose: true,
            ),
            const SizedBox(width: 4),
          ],
          SlidableAction(
            onPressed: (context) {
              HapticFeedback.lightImpact();
              onGroup(expense.name);
            },
            label: 'Grp',
            backgroundColor: gradient.colors.last.withValues(alpha: 0.15),
            foregroundColor: gradient.colors.last,
            icon: Icons.bubble_chart_rounded,
            borderRadius: BorderRadius.circular(14),
            autoClose: true,
          ),
          const SizedBox(width: 4),
          SlidableAction(
            onPressed: (context) {
              HapticFeedback.lightImpact();
              onDelete(expense.id);
            },
            label: 'Dlt',
            backgroundColor: Colors.red.withValues(alpha: 0.15),
            foregroundColor: Colors.red,
            icon: Icons.delete_outline,
            borderRadius: BorderRadius.circular(12),
            autoClose: true,
          ),
        ],
      ),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(
            color: Colors.grey.shade100,
            width: 1.0,
          ),
        ),
        child: Row(
          children: [
            _buildMerchantAvatar(expense.name, groupLabel, expense.type),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          displayName,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1E293B),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (groupLabel != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Color(
                              groupColors[groupLabel] ?? Colors.grey.value,
                            ).withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: Color(
                                groupColors[groupLabel] ?? Colors.grey.value,
                              ).withValues(alpha: 0.2),
                              width: 0.5,
                            ),
                          ),
                          child: Text(
                            groupLabel.toUpperCase(),
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: Color(
                                groupColors[groupLabel] ?? Colors.grey.value,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          expense.bank.isNotEmpty
                              ? (isUpi ? '(${expense.bank} • UPI)' : '(${expense.bank})')
                              : (isUpi ? '(UPI)' : '(TXN)'),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: isCredit
                                ? gradient.colors.first
                                : (isDueDateFiltered
                                    ? const Color(0xFFEF4444)
                                    : gradient.colors.first),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '•',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey.shade400,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        DateFormat('dd MMM yyyy, hh:mm a')
                            .format(expense.date)
                            .toUpperCase(),
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w500,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 14),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(15),
                color: isCredit
                    ? gradient.colors.first.withValues(alpha: 0.08)
                    : isDueDateFiltered ? Colors.red.shade50.withValues(alpha: 0.5) : gradient.colors.first.withValues(alpha: 0.04),
              ),
              child: Text(
                '${isCredit ? "+" : "-"} ₹${expense.amount.toStringAsFixed(0)}',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: isCredit
                      ? gradient.colors.last
                      : isDueDateFiltered ? Colors.red : gradient.colors.first,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Builder(
              builder: (buttonContext) {
                final slidable = Slidable.of(buttonContext);
                if (slidable == null) return const SizedBox.shrink();

                return AnimatedBuilder(
                  animation: slidable.animation,
                  builder: (context, child) {
                    final isOpen = slidable.animation.value > 0.1;
                    return GestureDetector(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        if (isOpen) {
                          slidable.close();
                        } else {
                          slidable.openEndActionPane();
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: isOpen
                              ? gradient.colors.last.withValues(alpha: 0.18)
                              : gradient.colors.last.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: gradient.colors.first.withValues(alpha: 0.25),
                            width: 0.8,
                          ),
                        ),
                        child: Icon(
                          isOpen
                              ? Icons.chevron_right_rounded
                              : Icons.chevron_left_rounded,
                          size: 14,
                          color: gradient.colors.first,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
