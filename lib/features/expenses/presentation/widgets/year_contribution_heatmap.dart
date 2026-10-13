import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../domain/entities/expense.dart';

class YearContributionHeatmap extends StatefulWidget {
  final List<Expense> expenses;
  final String cardName;
  final Color themeColor;
  final int? year;

  const YearContributionHeatmap({
    super.key,
    required this.expenses,
    required this.cardName,
    required this.themeColor,
    this.year,
  });

  @override
  State<YearContributionHeatmap> createState() =>
      _YearContributionHeatmapState();
}

class _YearContributionHeatmapState extends State<YearContributionHeatmap> {
  final ScrollController _scrollController = ScrollController();
  DateTime? _selectedDate;
  int _selectedCount = 0;
  double _selectedAmount = 0.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients &&
          _scrollController.position.maxScrollExtent > 0) {
        final targetYear = widget.year ?? DateTime.now().year;
        final now = DateTime.now();
        final currentWeekOfYear =
            ((now.difference(DateTime(targetYear, 1, 1)).inDays) / 7).floor();
        const columnWidthWithSpacing = 19.5; // 16px cell + 3.5px gap
        final maxScroll = _scrollController.position.maxScrollExtent;
        final targetOffset = (currentWeekOfYear * columnWidthWithSpacing - 140.0)
            .clamp(0.0, maxScroll);
        _scrollController.jumpTo(targetOffset);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final targetYear = widget.year ?? DateTime.now().year;

    // Aggregate daily data
    final Map<String, List<Expense>> dailyExpenses = {};
    double totalYearSpent = 0.0;
    int totalYearTransactions = 0;

    for (final e in widget.expenses) {
      if (e.date.year == targetYear) {
        final key = DateFormat('yyyy-MM-dd').format(e.date);
        dailyExpenses.putIfAbsent(key, () => []).add(e);
        totalYearSpent += e.amount;
        totalYearTransactions++;
      }
    }

    // Determine max daily transaction count for scaling levels
    int maxDailyCount = 1;
    for (final list in dailyExpenses.values) {
      if (list.length > maxDailyCount) {
        maxDailyCount = list.length;
      }
    }

    // Build 53 weeks starting from the Sunday on or before Jan 1
    final jan1 = DateTime(targetYear, 1, 1);
    final startSunday = jan1.subtract(Duration(days: (jan1.weekday % 7)));

    final List<List<DateTime>> weeks = [];
    DateTime cursor = startSunday;
    for (int w = 0; w < 53; w++) {
      final List<DateTime> week = [];
      for (int d = 0; d < 7; d++) {
        week.add(cursor);
        cursor = cursor.add(const Duration(days: 1));
      }
      weeks.add(week);
      if (cursor.year > targetYear && cursor.month > 1) {
        break;
      }
    }

    // Weekday labels (Sunday is row 0, Monday is row 1, etc.)
    final weekdayLabels = ['', 'Mon', '', 'Wed', '', 'Fri', ''];

    final numberFormat = NumberFormat('#,###');

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: total transactions in this year
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${numberFormat.format(totalYearTransactions)} contributions in ${targetYear == DateTime.now().year ? 'this year' : targetYear}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1E293B),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                decoration: BoxDecoration(
                  color: const Color(0xFF30A14E).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFF30A14E).withValues(alpha: 0.25),
                    width: 0.8,
                  ),
                ),
                child: Text(
                  '₹${numberFormat.format(totalYearSpent.toInt())}',
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF216E39),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Main Heatmap Grid with horizontal scroll
          Expanded(
            child: () {
              const double cellSize = 16.0;
              const double cellGap = 3.5;
              const double columnWidth = cellSize + cellGap; // 19.5

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Day of week labels column
                  Padding(
                    padding: const EdgeInsets.only(top: 24, right: 8),
                    child: SizedBox(
                      width: 26,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.start,
                        children: List.generate(7, (index) {
                          return Container(
                            height: cellSize,
                            margin: const EdgeInsets.only(bottom: cellGap),
                            alignment: Alignment.centerRight,
                            child: Text(
                              weekdayLabels[index],
                              style: const TextStyle(
                                fontSize: 9.5,
                                color: Color(0xFF64748B),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                  ),

                  // Scrollable weeks
                  Expanded(
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      scrollDirection: Axis.horizontal,
                      physics: const BouncingScrollPhysics(),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Month header row
                          SizedBox(
                            height: 18,
                            child: Row(
                              children: List.generate(weeks.length, (wIdx) {
                                final week = weeks[wIdx];
                                // Check if a new month starts in this week
                                String monthLabel = '';
                                for (final day in week) {
                                  if (day.year == targetYear && day.day == 1) {
                                    monthLabel = DateFormat('MMM').format(day);
                                    break;
                                  }
                                }
                                // First week label if Jan 1 is in it
                                if (wIdx == 0 &&
                                    monthLabel.isEmpty &&
                                    week.any((d) => d.year == targetYear)) {
                                  monthLabel = 'Jan';
                                }

                                return SizedBox(
                                  width: columnWidth,
                                  child: monthLabel.isNotEmpty
                                      ? OverflowBox(
                                          alignment: Alignment.centerLeft,
                                          maxWidth: 42,
                                          child: Text(
                                            monthLabel,
                                            style: const TextStyle(
                                              fontSize: 10,
                                              color: Color(0xFF64748B),
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        )
                                      : const SizedBox.shrink(),
                                );
                              }),
                            ),
                          ),
                          const SizedBox(height: 6),

                          // 7 rows of daily squares
                          Row(
                            children: List.generate(weeks.length, (wIdx) {
                              final week = weeks[wIdx];
                              return Padding(
                                padding: const EdgeInsets.only(right: cellGap),
                                child: Column(
                                  children: List.generate(7, (dIdx) {
                                    final date = week[dIdx];
                                    final isCurrentYear =
                                        date.year == targetYear;
                                    final dateKey =
                                        DateFormat('yyyy-MM-dd').format(date);
                                    final count =
                                        dailyExpenses[dateKey]?.length ?? 0;
                                    final amount = dailyExpenses[dateKey]?.fold(
                                            0.0, (s, e) => s + e.amount) ??
                                        0.0;

                                    // Level calculation (0 to 4)
                                    int level = 0;
                                    if (count > 0 && isCurrentYear) {
                                      if (maxDailyCount <= 1) {
                                        level = 2;
                                      } else {
                                        final ratio = count / maxDailyCount;
                                        if (ratio <= 0.25) {
                                          level = 1;
                                        } else if (ratio <= 0.50) {
                                          level = 2;
                                        } else if (ratio <= 0.75) {
                                          level = 3;
                                        } else {
                                          level = 4;
                                        }
                                      }
                                    }

                                    final cellColor = _getCellColor(
                                        level, widget.themeColor);
                                    final isToday = DateFormat('yyyy-MM-dd')
                                            .format(DateTime.now()) ==
                                        dateKey;
                                    final isSelected = _selectedDate != null &&
                                        DateFormat('yyyy-MM-dd')
                                                .format(_selectedDate!) ==
                                            dateKey;

                                    return GestureDetector(
                                      onTap: () {
                                        setState(() {
                                          _selectedDate = date;
                                          _selectedCount = count;
                                          _selectedAmount = amount;
                                        });
                                      },
                                      child: Container(
                                        width: cellSize,
                                        height: cellSize,
                                        margin: const EdgeInsets.only(
                                            bottom: cellGap),
                                        decoration: BoxDecoration(
                                          color: isCurrentYear
                                              ? cellColor
                                              : Colors.grey.shade50,
                                          borderRadius:
                                              BorderRadius.circular(3.5),
                                          border: Border.all(
                                            color: isSelected
                                                ? Colors.black87
                                                : (isToday
                                                    ? const Color(0xFF216E39)
                                                    : (level == 0
                                                        ? const Color(0xFFE2E8F0)
                                                        : Colors.transparent)),
                                            width: isSelected
                                                ? 1.5
                                                : (isToday ? 1.2 : 0.9),
                                          ),
                                        ),
                                      ),
                                    );
                                  }),
                                ),
                              );
                            }),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            }(),
          ),

          const SizedBox(height: 8),

          // Bottom Bar: Selected date detail + Legend
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Selected date description
              Expanded(
                child: Text(
                  _selectedDate != null
                      ? '${DateFormat('d MMM yyyy').format(_selectedDate!)}: ${_selectedCount == 0 ? "No activity" : "$_selectedCount txns (₹${_selectedAmount.toInt()})"}'
                      : 'Tap any day to view details',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: _selectedDate != null ? FontWeight.bold : FontWeight.normal,
                    color: _selectedDate != null ? const Color(0xFF1E293B) : Colors.grey.shade500,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              // Legend: Less [0] [1] [2] [3] [4] More
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Less',
                    style: TextStyle(
                      fontSize: 10,
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(width: 5),
                  ...List.generate(5, (lvl) {
                    return Container(
                      width: 13,
                      height: 13,
                      margin: const EdgeInsets.symmetric(horizontal: 1.5),
                      decoration: BoxDecoration(
                        color: _getCellColor(lvl),
                        borderRadius: BorderRadius.circular(2.5),
                        border: lvl == 0
                            ? Border.all(
                                color: const Color(0xFFE2E8F0),
                                width: 0.9,
                              )
                            : null,
                      ),
                    );
                  }),
                  const SizedBox(width: 5),
                  const Text(
                    'More',
                    style: TextStyle(
                      fontSize: 10,
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _getCellColor(int level, [Color? themeColor]) {
    switch (level) {
      case 0:
        return Colors.white;
      case 1:
        return const Color(0xFF9BE9A8); // GitHub Light Green
      case 2:
        return const Color(0xFF40C463); // GitHub Medium Green
      case 3:
        return const Color(0xFF30A14E); // GitHub Vibrant Green
      case 4:
      default:
        return const Color(0xFF216E39); // GitHub Deep Forest Green
    }
  }
}
