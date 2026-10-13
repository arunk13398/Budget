import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../domain/entities/expense.dart';

class ExpenseLineChart extends StatefulWidget {
  final List<Expense> debitExpenses;
  final List<Expense> creditExpenses;
  final double totalAmount;
  final double limit;
  final double? boundaryLimit;

  final int? selectedMonth;
  final bool? isDueDateFiltered;
  final int? dueDate;
  final int? selectedWeek;
  final String? cardTheme;

  const ExpenseLineChart({
    super.key,
    required this.debitExpenses,
    required this.creditExpenses,
    required this.totalAmount,
    required this.limit,
    this.boundaryLimit,
    this.selectedMonth,
    this.isDueDateFiltered,
    this.dueDate,
    this.selectedWeek,
    this.cardTheme,
  });

  @override
  State<ExpenseLineChart> createState() => _ExpenseLineChartState();
}

class _ExpenseLineChartState extends State<ExpenseLineChart> {
  late String _selectedFilter;
  bool _showDebit = true;
  bool _showCredit = true;
  bool _showCumulative = true;

  @override
  void initState() {
    super.initState();
    if (widget.selectedWeek != null) {
      _selectedFilter = 'Week ${widget.selectedWeek}';
    } else {
      _selectedFilter = 'Full Month';
    }
  }

  @override
  void didUpdateWidget(covariant ExpenseLineChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedWeek != oldWidget.selectedWeek) {
      if (widget.selectedWeek != null) {
        _selectedFilter = 'Week ${widget.selectedWeek}';
      } else {
        _selectedFilter = 'Full Month';
      }
    }
  }

  Map<int, double> _computeWeeklyTotals(List<Expense> list) {
    final Map<int, double> totals = {1: 0.0, 2: 0.0, 3: 0.0, 4: 0.0, 5: 0.0};
    for (final expense in list) {
      final week = ((expense.date.day - 1) ~/ 7) + 1;
      final bucket = week.clamp(1, 5);
      totals[bucket] = (totals[bucket] ?? 0.0) + expense.amount;
    }
    return totals;
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final targetYear = now.year;
    final targetMonth = (widget.selectedMonth ?? (now.month - 1)) + 1;
    final daysInMonth = DateTime(targetYear, targetMonth + 1, 0).day;

    final isFullMonth = _selectedFilter == 'Full Month';

    // 1. Monthly totals for W1..W5
    final debitWeekly = _computeWeeklyTotals(widget.debitExpenses);
    final creditWeekly = _computeWeeklyTotals(widget.creditExpenses);
    final Map<int, double> cumulativeWeekly = {};
    double runningWeeklySum = 0.0;
    for (int w = 1; w <= 5; w++) {
      runningWeeklySum += debitWeekly[w] ?? 0.0;
      cumulativeWeekly[w] = runningWeeklySum;
    }

    // 2. Daily totals for a selected week
    int selectedWeekNum = 1;
    if (_selectedFilter.startsWith('Week ')) {
      selectedWeekNum =
          int.tryParse(_selectedFilter.replaceFirst('Week ', '')) ?? 1;
    }
    final weekStartDay = (selectedWeekNum - 1) * 7 + 1;
    final weekEndDay = (selectedWeekNum * 7).clamp(1, daysInMonth);
    final numDaysInWeek =
        weekEndDay >= weekStartDay ? (weekEndDay - weekStartDay + 1) : 1;

    final Map<int, double> debitDay = {};
    final Map<int, double> creditDay = {};
    final Map<int, double> cumulativeDay = {};
    final Map<int, DateTime> dayDates = {};

    double runningDailySum = 0.0;
    for (int i = 1; i <= numDaysInWeek; i++) {
      final day = weekStartDay + (i - 1);
      final date = DateTime(targetYear, targetMonth, day);
      dayDates[i] = date;

      double spent = 0.0;
      for (final e in widget.debitExpenses) {
        if (e.date.year == targetYear &&
            e.date.month == targetMonth &&
            e.date.day == day) {
          spent += e.amount;
        }
      }
      debitDay[i] = spent;

      double credit = 0.0;
      for (final e in widget.creditExpenses) {
        if (e.date.year == targetYear &&
            e.date.month == targetMonth &&
            e.date.day == day) {
          credit += e.amount;
        }
      }
      creditDay[i] = credit;

      runningDailySum += spent;
      cumulativeDay[i] = runningDailySum;
    }

    // Spots based on view mode (Full Month vs Week)
    final List<FlSpot> debitSpots = [];
    final List<FlSpot> creditSpots = [];
    final List<FlSpot> cumulativeSpots = [];

    if (isFullMonth) {
      for (int w = 1; w <= 5; w++) {
        debitSpots.add(FlSpot(w.toDouble(), (debitWeekly[w] ?? 0.0) / 1000.0));
        creditSpots
            .add(FlSpot(w.toDouble(), (creditWeekly[w] ?? 0.0) / 1000.0));
        cumulativeSpots
            .add(FlSpot(w.toDouble(), (cumulativeWeekly[w] ?? 0.0) / 1000.0));
      }
    } else {
      for (int i = 1; i <= numDaysInWeek; i++) {
        debitSpots.add(FlSpot(i.toDouble(), (debitDay[i] ?? 0.0) / 1000.0));
        creditSpots.add(FlSpot(i.toDouble(), (creditDay[i] ?? 0.0) / 1000.0));
        cumulativeSpots
            .add(FlSpot(i.toDouble(), (cumulativeDay[i] ?? 0.0) / 1000.0));
      }
    }

    final hasCredit = isFullMonth
        ? creditWeekly.values.any((v) => v > 0)
        : creditDay.values.any((v) => v > 0);

    // Calculate max Y based on active lines and mode
    double maxAmount = 0.0;
    if (isFullMonth) {
      if (_showDebit) {
        for (var v in debitWeekly.values) {
          if (v > maxAmount) maxAmount = v;
        }
      }
      if (_showCredit) {
        for (var v in creditWeekly.values) {
          if (v > maxAmount) maxAmount = v;
        }
      }
      if (_showCumulative) {
        for (var v in cumulativeWeekly.values) {
          if (v > maxAmount) maxAmount = v;
        }
      }
    } else {
      if (_showDebit) {
        for (var v in debitDay.values) {
          if (v > maxAmount) maxAmount = v;
        }
      }
      if (_showCredit) {
        for (var v in creditDay.values) {
          if (v > maxAmount) maxAmount = v;
        }
      }
      if (_showCumulative) {
        for (var v in cumulativeDay.values) {
          if (v > maxAmount) maxAmount = v;
        }
      }
    }

    final boundary = widget.boundaryLimit;
    if (boundary != null && boundary > maxAmount) {
      maxAmount = boundary;
    }

    if (maxAmount <= 0.0) {
      maxAmount = widget.limit > 0 ? widget.limit : 5000.0;
    }

    double maxK = maxAmount / 1000.0;
    if (maxK <= 0) maxK = 5.0;

    double interval;
    if (maxK <= 5) {
      interval = 1.0;
    } else if (maxK <= 10) {
      interval = 2.0;
    } else if (maxK <= 25) {
      interval = 5.0;
    } else if (maxK <= 50) {
      interval = 10.0;
    } else if (maxK <= 100) {
      interval = 25.0;
    } else if (maxK <= 200) {
      interval = 50.0;
    } else {
      interval = (maxK / 4).ceilToDouble();
      if (interval <= 0) interval = 5.0;
    }

    final double maxY = ((maxK / interval).ceil() + 0.3) * interval;

    // Display amount & label
    // Display amount & label
    double displayedAmount;
    String spendLabel;
    if (!_showDebit && _showCredit) {
      if (isFullMonth) {
        displayedAmount = creditWeekly.values.fold(0.0, (s, v) => s + v);
        spendLabel = 'Total Credit';
      } else {
        displayedAmount = creditWeekly[selectedWeekNum] ?? 0.0;
        spendLabel = 'Week $selectedWeekNum Credit';
      }
    } else {
      if (isFullMonth) {
        displayedAmount = debitWeekly.values.fold(0.0, (s, v) => s + v);
        spendLabel = 'Current Spend';
      } else {
        displayedAmount = debitWeekly[selectedWeekNum] ?? 0.0;
        spendLabel = 'Week $selectedWeekNum Spend';
      }
    }

    // Dynamic Trend calculation
    final dataSourceWeekly =
        (!_showDebit && _showCredit) ? creditWeekly : debitWeekly;
    final dataSourceDay = (!_showDebit && _showCredit) ? creditDay : debitDay;

    final isCurrentMonth = (targetYear == now.year && targetMonth == now.month);
    final currentWeekNum = isCurrentMonth
        ? (((now.day - 1) ~/ 7) + 1).clamp(1, 5)
        : 5;

    double currentTrendVal = 0.0;
    double previousTrendVal = 0.0;
    String trendSubtitle = '';

    if (isFullMonth) {
      int latestWeek = currentWeekNum;
      if (!isCurrentMonth) {
        latestWeek = 1;
        for (int w = 5; w >= 1; w--) {
          if ((dataSourceWeekly[w] ?? 0.0) > 0) {
            latestWeek = w;
            break;
          }
        }
      }

      if (latestWeek > 1) {
        currentTrendVal = dataSourceWeekly[latestWeek] ?? 0.0;
        previousTrendVal = dataSourceWeekly[latestWeek - 1] ?? 0.0;
        trendSubtitle = 'vs last week';
      } else {
        final todayDay = isCurrentMonth ? now.day.clamp(1, 7) : 7;
        if (todayDay > 1) {
          currentTrendVal = dataSourceDay[todayDay] ?? 0.0;
          previousTrendVal = dataSourceDay[todayDay - 1] ?? 0.0;
          trendSubtitle = 'vs yesterday';
        } else {
          currentTrendVal = dataSourceWeekly[1] ?? 0.0;
          previousTrendVal = 0.0;
          trendSubtitle = 'vs last week';
        }
      }
    } else {
      if (selectedWeekNum > 1) {
        currentTrendVal = dataSourceWeekly[selectedWeekNum] ?? 0.0;
        previousTrendVal = dataSourceWeekly[selectedWeekNum - 1] ?? 0.0;
        trendSubtitle = 'vs Week ${selectedWeekNum - 1}';
      } else {
        int latestDayInW1 = 1;
        for (int d = numDaysInWeek; d >= 1; d--) {
          if ((dataSourceDay[d] ?? 0.0) > 0) {
            latestDayInW1 = d;
            break;
          }
        }
        if (latestDayInW1 > 1) {
          currentTrendVal = dataSourceDay[latestDayInW1] ?? 0.0;
          previousTrendVal = dataSourceDay[latestDayInW1 - 1] ?? 0.0;
          trendSubtitle = 'vs prev day';
        } else {
          currentTrendVal = dataSourceDay[1] ?? 0.0;
          previousTrendVal = 0.0;
          trendSubtitle = 'Week 1';
        }
      }
    }

    double trendPct = 0.0;
    bool isTrendUp = true;
    bool isTrendNeutral = false;

    if (previousTrendVal == 0.0 && currentTrendVal == 0.0) {
      trendPct = 0.0;
      isTrendNeutral = true;
    } else if (previousTrendVal == 0.0) {
      trendPct = 100.0;
      isTrendUp = true;
    } else {
      final diff = currentTrendVal - previousTrendVal;
      trendPct = (diff / previousTrendVal) * 100.0;
      if (trendPct.abs() < 0.05) {
        trendPct = 0.0;
        isTrendNeutral = true;
      } else {
        isTrendUp = trendPct > 0;
      }
    }

    String trendPctString;
    if (isTrendNeutral) {
      trendPctString = '0.0%';
    } else {
      final sign = isTrendUp ? '+' : '';
      if (trendPct.abs() >= 1000) {
        trendPctString = '$sign${trendPct.toStringAsFixed(0)}%';
      } else if (trendPct.abs() >= 10) {
        trendPctString = '$sign${trendPct.toStringAsFixed(1)}%';
      } else {
        trendPctString = '$sign${trendPct.toStringAsFixed(2)}%';
      }
    }

    final Color trendColor;
    final IconData trendIcon;
    if (isTrendNeutral) {
      trendColor = const Color(0xFF64748B);
      trendIcon = Icons.remove_rounded;
    } else if (isTrendUp) {
      trendColor = const Color(0xFF10B981);
      trendIcon = Icons.arrow_upward_rounded;
    } else {
      trendColor = const Color(0xFFEF4444);
      trendIcon = Icons.arrow_downward_rounded;
    }

    final double minX = 1.0;
    final double maxX = isFullMonth ? 5.0 : numDaysInWeek.toDouble();

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row: Report title + Filter buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                isFullMonth ? 'Monthly report' : 'Weekly report',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                  letterSpacing: -0.2,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Filter lines menu button
                  PopupMenuButton<String>(
                    tooltip: 'Filter Lines',
                    elevation: 8,
                    offset: const Offset(0, 32),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    color: Colors.white,
                    onSelected: (val) {
                      setState(() {
                        if (val == 'toggle_debit') {
                          if (_showDebit && !_showCredit && !_showCumulative) {
                            return;
                          }
                          _showDebit = !_showDebit;
                        } else if (val == 'toggle_credit') {
                          if (_showCredit && !_showDebit && !_showCumulative) {
                            return;
                          }
                          _showCredit = !_showCredit;
                        } else if (val == 'toggle_cumulative') {
                          if (_showCumulative &&
                              !_showDebit &&
                              !_showCredit) {
                            return;
                          }
                          _showCumulative = !_showCumulative;
                        } else if (val == 'show_all') {
                          _showDebit = true;
                          _showCredit = true;
                          _showCumulative = true;
                        }
                      });
                    },
                    itemBuilder: (context) => [
                      _buildFilterItem(
                        value: 'toggle_debit',
                        label: isFullMonth ? 'Weekly Spent' : 'Daily Spent',
                        color: const Color(0xFF2563EB),
                        isChecked: _showDebit,
                      ),
                      if (hasCredit)
                        _buildFilterItem(
                          value: 'toggle_credit',
                          label: 'Credit/Repay',
                          color: const Color(0xFF10B981),
                          isChecked: _showCredit,
                        ),
                      _buildFilterItem(
                        value: 'toggle_cumulative',
                        label: 'Cumulative',
                        color: const Color(0xFF059669),
                        isChecked: _showCumulative,
                      ),
                      const PopupMenuDivider(height: 8),
                      PopupMenuItem<String>(
                        value: 'show_all',
                        height: 32,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.done_all_rounded,
                                size: 14,
                                color: Color(0xFF2563EB),
                              ),
                              SizedBox(width: 6),
                              Text(
                                'Show All Lines',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF2563EB),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFFE2E8F0),
                          width: 1,
                        ),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.tune_rounded,
                            size: 13,
                            color: Color(0xFF64748B),
                          ),
                          SizedBox(width: 4),
                          Text(
                            'Filter',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),

                  // Week/Month Dropdown
                  PopupMenuButton<String>(
                    elevation: 8,
                    offset: const Offset(0, 32),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    color: Colors.white,
                    onSelected: (val) {
                      setState(() {
                        _selectedFilter = val;
                      });
                    },
                    itemBuilder: (context) => [
                      _buildWeekMenuItem(
                        value: 'Full Month',
                        label: 'Full Month',
                        icon: Icons.calendar_view_month_rounded,
                      ),
                      _buildWeekMenuItem(
                        value: 'Week 1',
                        label: 'Week 1',
                        icon: Icons.view_week_rounded,
                      ),
                      _buildWeekMenuItem(
                        value: 'Week 2',
                        label: 'Week 2',
                        icon: Icons.view_week_rounded,
                      ),
                      _buildWeekMenuItem(
                        value: 'Week 3',
                        label: 'Week 3',
                        icon: Icons.view_week_rounded,
                      ),
                      _buildWeekMenuItem(
                        value: 'Week 4',
                        label: 'Week 4',
                        icon: Icons.view_week_rounded,
                      ),
                      _buildWeekMenuItem(
                        value: 'Week 5',
                        label: 'Week 5',
                        icon: Icons.view_week_rounded,
                      ),
                    ],
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: const Color(0xFFE2E8F0),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _selectedFilter,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF334155),
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 15,
                            color: Color(0xFF64748B),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),

          // Subtitle & Spend Amount
          Text(
            spendLabel,
            style: const TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
              color: Color(0xFF64748B),
            ),
          ),
          const SizedBox(height: 1),
          Text(
            '₹${NumberFormat('#,##0.00').format(displayedAmount)}',
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A),
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 2),

          // Dynamic Trend chip
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 13,
                height: 13,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: trendColor,
                ),
                child: Icon(
                  trendIcon,
                  size: 9,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                trendPctString,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: trendColor,
                ),
              ),
              if (trendSubtitle.isNotEmpty) ...[
                const SizedBox(width: 5),
                Text(
                  trendSubtitle,
                  style: const TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF94A3B8),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),

          // Dynamic Line Chart (Changes based on Filter!)
          Expanded(
            child: LineChart(
              LineChartData(
                minX: minX,
                maxX: maxX,
                minY: 0,
                maxY: maxY,
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: interval,
                  getDrawingHorizontalLine: (value) => const FlLine(
                    color: Color(0xFFF1F5F9),
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 32,
                      interval: interval,
                      getTitlesWidget: (value, meta) {
                        if (value < 0 || value > maxY) {
                          return const SizedBox.shrink();
                        }
                        final remainder = (value % interval);
                        if (remainder.abs() > 0.1 &&
                            (interval - remainder).abs() > 0.1) {
                          return const SizedBox.shrink();
                        }
                        final valInt = value.toInt();
                        if (valInt == 0) {
                          return SideTitleWidget(
                            meta: meta,
                            space: 4,
                            child: const Text(
                              '₹0',
                              style: TextStyle(
                                color: Color(0xFFCBD5E1),
                                fontSize: 9,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          );
                        }
                        return SideTitleWidget(
                          meta: meta,
                          space: 4,
                          child: Text(
                            '₹${valInt}k',
                            style: const TextStyle(
                              color: Color(0xFFCBD5E1),
                              fontSize: 9,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: isFullMonth ? 20 : 26,
                      interval: 1,
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();

                        if (isFullMonth) {
                          if (idx < 1 || idx > 5) {
                            return const SizedBox.shrink();
                          }
                          return SideTitleWidget(
                            meta: meta,
                            space: 4,
                            child: Text(
                              'W$idx',
                              style: const TextStyle(
                                color: Color(0xFF64748B),
                                fontWeight: FontWeight.bold,
                                fontSize: 10,
                              ),
                            ),
                          );
                        } else {
                          // Single week: show Weekday + Day of month!
                          final date = dayDates[idx];
                          if (date == null) return const SizedBox.shrink();
                          final weekday = DateFormat('E').format(date);
                          final dayNum = date.day;

                          return SideTitleWidget(
                            meta: meta,
                            space: 2,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  weekday,
                                  style: const TextStyle(
                                    color: Color(0xFF64748B),
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  '$dayNum',
                                  style: const TextStyle(
                                    color: Color(0xFF94A3B8),
                                    fontSize: 8,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }
                      },
                    ),
                  ),
                ),
                extraLinesData: boundary != null
                    ? ExtraLinesData(
                        horizontalLines: [
                          HorizontalLine(
                            y: boundary / 1000.0,
                            color: Colors.deepOrange,
                            strokeWidth: 1.1,
                            dashArray: [4, 4],
                            label: HorizontalLineLabel(
                              show: true,
                              alignment: Alignment.topRight,
                              padding: const EdgeInsets.only(
                                right: 8,
                                bottom: 4,
                              ),
                              style: const TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                                fontSize: 8,
                              ),
                              labelResolver: (line) =>
                                  'TARGET: ₹${line.y.toStringAsFixed(0)}k',
                            ),
                          ),
                        ],
                      )
                    : null,
                lineTouchData: LineTouchData(
                  enabled: true,
                  handleBuiltInTouches: true,
                  getTouchedSpotIndicator: (barData, spotIndexes) {
                    return spotIndexes.map((index) {
                      final color = barData.gradient?.colors.first ??
                          barData.color ??
                          const Color(0xFF2563EB);
                      return TouchedSpotIndicatorData(
                        FlLine(
                          color: color.withValues(alpha: 0.25),
                          strokeWidth: 1.5,
                          dashArray: [4, 4],
                        ),
                        FlDotData(
                          getDotPainter: (spot, percent, barData, index) =>
                              FlDotCirclePainter(
                            radius: 5,
                            color: Colors.white,
                            strokeWidth: 3,
                            strokeColor: color,
                          ),
                        ),
                      );
                    }).toList();
                  },
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (touchedSpot) => Colors.white,
                    tooltipBorderRadius: BorderRadius.circular(12),
                    tooltipPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    tooltipMargin: 10,
                    fitInsideHorizontally: true,
                    fitInsideVertically: true,
                    tooltipBorder: const BorderSide(
                      color: Color(0xFFE2E8F0),
                      width: 1,
                    ),
                    getTooltipItems: (touchedSpots) {
                      if (touchedSpots.isEmpty) return [];
                      final idx = touchedSpots.first.x.toInt();

                      String title;
                      double spent;
                      double credit;
                      double cum;

                      if (isFullMonth) {
                        title = 'WEEK $idx SUMMARY';
                        spent = debitWeekly[idx] ?? 0.0;
                        credit = creditWeekly[idx] ?? 0.0;
                        cum = cumulativeWeekly[idx] ?? 0.0;
                      } else {
                        final date = dayDates[idx] ??
                            DateTime(targetYear, targetMonth, 1);
                        final dateFormatted =
                            DateFormat('d MMM (E)').format(date);
                        title = '$dateFormatted SUMMARY';
                        spent = debitDay[idx] ?? 0.0;
                        credit = creditDay[idx] ?? 0.0;
                        cum = cumulativeDay[idx] ?? 0.0;
                      }

                      return touchedSpots.map((spot) {
                        if (spot == touchedSpots.first) {
                          final List<TextSpan> spans = [];

                          if (_showDebit) {
                            spans.add(
                              TextSpan(
                                text:
                                    '● Spent: ₹${NumberFormat('#,##0').format(spent.toInt())}\n',
                                style: const TextStyle(
                                  color: Color(0xFF2563EB),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 10,
                                ),
                              ),
                            );
                          }
                          if (_showCredit && hasCredit) {
                            spans.add(
                              TextSpan(
                                text:
                                    '● Credit: ₹${NumberFormat('#,##0').format(credit.toInt())}\n',
                                style: const TextStyle(
                                  color: Color(0xFF10B981),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 10,
                                ),
                              ),
                            );
                          }
                          if (_showCumulative) {
                            spans.add(
                              TextSpan(
                                text:
                                    '● Cumulative: ₹${NumberFormat('#,##0').format(cum.toInt())}',
                                style: const TextStyle(
                                  color: Color(0xFF059669),
                                  fontWeight: FontWeight.w600,
                                  fontSize: 10,
                                ),
                              ),
                            );
                          }

                          return LineTooltipItem(
                            '$title\n',
                            const TextStyle(
                              color: Color(0xFF0F172A),
                              fontWeight: FontWeight.w800,
                              fontSize: 11,
                            ),
                            children: spans,
                          );
                        } else {
                          return null;
                        }
                      }).toList();
                    },
                  ),
                ),
                lineBarsData: [
                  // 1. Debit / Spent Line (Royal Blue to Sky Blue)
                  if (_showDebit)
                    LineChartBarData(
                      spots: debitSpots,
                      isCurved: true,
                      curveSmoothness: 0.32,
                      preventCurveOverShooting: true,
                      gradient: const LinearGradient(
                        colors: [Color(0xFF2563EB), Color(0xFF38BDF8)],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                      barWidth: 3.2,
                      isStrokeCapRound: true,
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, percent, barData, index) =>
                            FlDotCirclePainter(
                          radius: 4,
                          color: Colors.white,
                          strokeWidth: 2.5,
                          strokeColor: const Color(0xFF2563EB),
                        ),
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            const Color(0xFF38BDF8).withValues(alpha: 0.18),
                            const Color(0xFF38BDF8).withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                    ),

                  // 2. Credit / Repay Line (Mint to Emerald Green)
                  if (_showCredit && hasCredit)
                    LineChartBarData(
                      spots: creditSpots,
                      isCurved: true,
                      curveSmoothness: 0.32,
                      preventCurveOverShooting: true,
                      gradient: const LinearGradient(
                        colors: [Color(0xFF34D399), Color(0xFF10B981)],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                      barWidth: 2.8,
                      isStrokeCapRound: true,
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, percent, barData, index) =>
                            FlDotCirclePainter(
                          radius: 4,
                          color: Colors.white,
                          strokeWidth: 2.5,
                          strokeColor: const Color(0xFF10B981),
                        ),
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            const Color(0xFF10B981).withValues(alpha: 0.12),
                            const Color(0xFF10B981).withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                    ),

                  // 3. Cumulative Line (Dark Forest Teal)
                  if (_showCumulative)
                    LineChartBarData(
                      spots: cumulativeSpots,
                      isCurved: true,
                      curveSmoothness: 0.32,
                      preventCurveOverShooting: true,
                      gradient: const LinearGradient(
                        colors: [Color(0xFF059669), Color(0xFF047857)],
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                      ),
                      barWidth: 3.2,
                      isStrokeCapRound: true,
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, percent, barData, index) =>
                            FlDotCirclePainter(
                          radius: 4,
                          color: Colors.white,
                          strokeWidth: 2.5,
                          strokeColor: const Color(0xFF059669),
                        ),
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            const Color(0xFF059669).withValues(alpha: 0.12),
                            const Color(0xFF059669).withValues(alpha: 0.0),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeInOut,
            ),
          ),
          const SizedBox(height: 8),

          // Bottom Filter Legend Row: Tap to toggle lines
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildLegendToggleChip(
                label: isFullMonth ? 'Weekly Spent' : 'Daily Spent',
                color: const Color(0xFF2563EB),
                isVisible: _showDebit,
                onTap: () {
                  setState(() {
                    if (_showDebit && !_showCredit && !_showCumulative) return;
                    _showDebit = !_showDebit;
                  });
                },
              ),
              const SizedBox(width: 8),
              if (hasCredit) ...[
                _buildLegendToggleChip(
                  label: 'Credit/Repay',
                  color: const Color(0xFF10B981),
                  isVisible: _showCredit,
                  onTap: () {
                    setState(() {
                      if (_showCredit && !_showDebit && !_showCumulative) {
                        return;
                      }
                      _showCredit = !_showCredit;
                    });
                  },
                ),
                const SizedBox(width: 8),
              ],
              _buildLegendToggleChip(
                label: 'Cumulative',
                color: const Color(0xFF059669),
                isVisible: _showCumulative,
                onTap: () {
                  setState(() {
                    if (_showCumulative && !_showDebit && !_showCredit) return;
                    _showCumulative = !_showCumulative;
                  });
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLegendToggleChip({
    required String label,
    required Color color,
    required bool isVisible,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 200),
        opacity: isVisible ? 1.0 : 0.45,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
          decoration: BoxDecoration(
            color:
                isVisible ? color.withValues(alpha: 0.08) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isVisible
                  ? color.withValues(alpha: 0.25)
                  : Colors.grey.shade300,
              width: 0.8,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6.5,
                height: 6.5,
                decoration: BoxDecoration(
                  color: isVisible ? color : Colors.grey.shade400,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 4.5),
              Text(
                label,
                style: TextStyle(
                  color: isVisible
                      ? const Color(0xFF1E293B)
                      : Colors.grey.shade500,
                  fontSize: 9.5,
                  fontWeight: isVisible ? FontWeight.w600 : FontWeight.w500,
                  decoration: isVisible ? null : TextDecoration.lineThrough,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  PopupMenuItem<String> _buildFilterItem({
    required String value,
    required String label,
    required Color color,
    required bool isChecked,
  }) {
    return PopupMenuItem<String>(
      value: value,
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Container(
        decoration: BoxDecoration(
          color: isChecked ? color.withValues(alpha: 0.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: isChecked
              ? Border.all(
                  color: color.withValues(alpha: 0.25),
                  width: 0.8,
                )
              : null,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: isChecked
                      ? const Color(0xFF1E293B)
                      : const Color(0xFF64748B),
                  fontWeight: isChecked ? FontWeight.w600 : FontWeight.w500,
                  fontSize: 11.5,
                ),
              ),
            ),
            Icon(
              isChecked
                  ? Icons.check_box_rounded
                  : Icons.check_box_outline_blank_rounded,
              color: isChecked ? color : const Color(0xFFCBD5E1),
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<String> _buildWeekMenuItem({
    required String value,
    required String label,
    required IconData icon,
  }) {
    final isSelected = _selectedFilter == value;
    return PopupMenuItem<String>(
      value: value,
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Container(
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF2563EB).withValues(alpha: 0.08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: isSelected
              ? Border.all(
                  color: const Color(0xFF2563EB).withValues(alpha: 0.25),
                  width: 0.8,
                )
              : null,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: isSelected
                    ? const Color(0xFF2563EB).withValues(alpha: 0.15)
                    : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(
                icon,
                color: isSelected
                    ? const Color(0xFF2563EB)
                    : const Color(0xFF64748B),
                size: 13,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: isSelected
                      ? const Color(0xFF2563EB)
                      : const Color(0xFF334155),
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 11.5,
                ),
              ),
            ),
            if (isSelected)
              const Icon(
                Icons.check_rounded,
                color: Color(0xFF2563EB),
                size: 15,
              ),
          ],
        ),
      ),
    );
  }
}
