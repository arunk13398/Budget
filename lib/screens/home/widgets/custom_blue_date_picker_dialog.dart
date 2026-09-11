import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class CustomBlueDatePickerDialog extends StatefulWidget {
  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;
  final Color? primaryColor;

  const CustomBlueDatePickerDialog({
    super.key,
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
    this.primaryColor,
  });

  @override
  State<CustomBlueDatePickerDialog> createState() =>
      _CustomBlueDatePickerDialogState();
}

class _CustomBlueDatePickerDialogState
    extends State<CustomBlueDatePickerDialog> {
  late DateTime _selectedDate;
  late DateTime _displayedMonth;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate;
    _displayedMonth =
        DateTime(widget.initialDate.year, widget.initialDate.month, 1);
  }

  void _previousMonth() {
    setState(() {
      _displayedMonth =
          DateTime(_displayedMonth.year, _displayedMonth.month - 1, 1);
    });
  }

  void _nextMonth() {
    setState(() {
      _displayedMonth =
          DateTime(_displayedMonth.year, _displayedMonth.month + 1, 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final primaryBlue = widget.primaryColor ?? const Color(0xFF090909);
    final monthName = DateFormat('MMM').format(_displayedMonth);
    final yearStr = _displayedMonth.year.toString();

    final daysInMonth =
        DateTime(_displayedMonth.year, _displayedMonth.month + 1, 0).day;
    final firstWeekday =
        DateTime(_displayedMonth.year, _displayedMonth.month, 1).weekday; // 1 = Mon, 7 = Sun
    final prevMonthDays =
        DateTime(_displayedMonth.year, _displayedMonth.month, 0).day;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Inner White Card Body
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
            ),
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Month & Year Selector Pills Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: Icon(
                        Icons.chevron_left,
                        color: Colors.grey.shade600,
                        size: 20,
                      ),
                      onPressed: _previousMonth,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                    Row(
                      children: [
                        PopupMenuButton<int>(
                          initialValue: _displayedMonth.month,
                          onSelected: (month) {
                            setState(() {
                              _displayedMonth = DateTime(
                                _displayedMonth.year,
                                month,
                                1,
                              );
                            });
                          },
                          itemBuilder: (context) => List.generate(12, (i) {
                            final mName = DateFormat('MMMM').format(
                              DateTime(2026, i + 1, 1),
                            );
                            return PopupMenuItem(
                              value: i + 1,
                              child: Text(
                                mName,
                                style: const TextStyle(fontSize: 13),
                              ),
                            );
                          }),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              children: [
                                Text(
                                  monthName,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF1E293B),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(
                                  Icons.keyboard_arrow_down,
                                  size: 16,
                                  color: Color(0xFF64748B),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        PopupMenuButton<int>(
                          initialValue: _displayedMonth.year,
                          onSelected: (year) {
                            setState(() {
                              _displayedMonth = DateTime(
                                year,
                                _displayedMonth.month,
                                1,
                              );
                            });
                          },
                          itemBuilder: (context) => List.generate(11, (i) {
                            final y = 2020 + i;
                            return PopupMenuItem(
                              value: y,
                              child: Text(
                                '$y',
                                style: const TextStyle(fontSize: 13),
                              ),
                            );
                          }),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              children: [
                                Text(
                                  yearStr,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF1E293B),
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(
                                  Icons.keyboard_arrow_down,
                                  size: 16,
                                  color: Color(0xFF64748B),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.chevron_right,
                        color: Colors.grey.shade600,
                        size: 20,
                      ),
                      onPressed: _nextMonth,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Weekdays Header (MO, TU, WE, TH, FR, SA, SU)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: const ['MO', 'TU', 'WE', 'TH', 'FR', 'SA', 'SU']
                      .map((day) {
                        return Expanded(
                          child: Center(
                            child: Text(
                              day,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF94A3B8),
                              ),
                            ),
                          ),
                        );
                      })
                      .toList(),
                ),
                const SizedBox(height: 10),

                // Calendar Days Grid (7 columns)
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 7,
                        childAspectRatio: 1.1,
                        crossAxisSpacing: 4,
                        mainAxisSpacing: 4,
                      ),
                  itemCount: 42,
                  itemBuilder: (context, index) {
                    int dayNumber;
                    bool isCurrentMonth = true;

                    int offsetIndex = index - (firstWeekday - 1);

                    if (offsetIndex < 0) {
                      dayNumber = prevMonthDays + offsetIndex + 1;
                      isCurrentMonth = false;
                    } else if (offsetIndex >= daysInMonth) {
                      dayNumber = offsetIndex - daysInMonth + 1;
                      isCurrentMonth = false;
                    } else {
                      dayNumber = offsetIndex + 1;
                    }

                    final cellDate = DateTime(_displayedMonth.year, _displayedMonth.month, dayNumber);
                    final today = DateTime.now();
                    final todayMidnight = DateTime(today.year, today.month, today.day);
                    final isFuture = isCurrentMonth && cellDate.isAfter(todayMidnight);

                    final isSelected =
                        isCurrentMonth &&
                        !isFuture &&
                        _selectedDate.year == _displayedMonth.year &&
                        _selectedDate.month == _displayedMonth.month &&
                        _selectedDate.day == dayNumber;

                    return GestureDetector(
                      onTap: (isCurrentMonth && !isFuture)
                          ? () {
                              setState(() {
                                _selectedDate = cellDate;
                              });
                            }
                          : null,
                      child: Container(
                        decoration: BoxDecoration(
                          color: isSelected
                              ? primaryBlue
                              : (isFuture ? const Color(0xFFF8FAFC) : Colors.transparent),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isFuture ? const Color(0xFFF1F5F9) : const Color(0xFFF1F5F9),
                            width: 0.5,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '$dayNumber',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.w500,
                            color: isSelected
                                ? Colors.white
                                : (isCurrentMonth
                                    ? (isFuture
                                        ? const Color(0xFFCBD5E1)
                                        : const Color(0xFF1E293B))
                                    : const Color(0xFFCBD5E1)),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),

                // Action Buttons: Confirm & Cancel
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    TextButton(
                      onPressed: () {
                        Navigator.pop(context, null);
                      },
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF475569),
                        ),
                      ),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primaryBlue,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      onPressed: () {
                        Navigator.pop(context, _selectedDate);
                      },
                      child: const Text(
                        'Confirm',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
