import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../../../core/constants/app_constants.dart';
import '../../domain/entities/expense.dart';

class ExpenseLineChart extends StatelessWidget {
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

  Map<int, double> _computeWeeklyTotals(List<Expense> list) {
    final Map<int, double> totals = {1: 0, 2: 0, 3: 0, 4: 0, 5: 0};
    for (final expense in list) {
      final week = ((expense.date.day - 1) ~/ 7) + 1;
      final bucket = week.clamp(1, 5);
      totals[bucket] = (totals[bucket] ?? 0) + expense.amount;
    }
    return totals;
  }

  @override
  Widget build(BuildContext context) {
    final debitWeekly = _computeWeeklyTotals(debitExpenses);
    final creditWeekly = _computeWeeklyTotals(creditExpenses);

    final debitSpots = debitWeekly.entries
        .map((e) => FlSpot(e.key.toDouble(), e.value / 1000))
        .toList();

    final creditSpots = creditWeekly.entries
        .map((e) => FlSpot(e.key.toDouble(), e.value / 1000))
        .toList();

    final Map<int, double> cumulativeWeekly = {};
    double runningSum = 0.0;
    final sortedKeys = debitWeekly.keys.toList()..sort();
    for (final key in sortedKeys) {
      runningSum += debitWeekly[key] ?? 0.0;
      cumulativeWeekly[key] = runningSum;
    }

    final cumulativeSpots = cumulativeWeekly.entries
        .map((e) => FlSpot(e.key.toDouble(), e.value / 1000))
        .toList();

    double maxAmount = limit;
    for (var v in debitWeekly.values) {
      if (v > maxAmount) maxAmount = v;
    }
    for (var v in creditWeekly.values) {
      if (v > maxAmount) maxAmount = v;
    }
    for (var v in cumulativeWeekly.values) {
      if (v > maxAmount) maxAmount = v;
    }
    final maxY = maxAmount <= 0 ? 10.0 : (maxAmount / 1000) * 1.15;

    final cardThemeColors = cardTheme != null
        ? (AppConstants.themeGradients[cardTheme] ?? AppConstants.themeGradients['Ocean']!)
        : [const Color(0xFF2563EB), const Color(0xFF3B82F6)];
    final primaryThemeColor = cardThemeColors.length > 1 ? cardThemeColors[1] : cardThemeColors.first;

    final debitGradient = LinearGradient(
      colors: [primaryThemeColor, primaryThemeColor.withValues(alpha: 0.7)],
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
    );

    final creditGradient = const LinearGradient(
      colors: [Color(0xFF10B981), Color(0xFF059669)],
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
    );

    return Container(
      height: 260,
      padding: const EdgeInsets.only(right: 16, left: 8, top: 16, bottom: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(15),
        color: Colors.white,
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          children: [
            const Text(
              'CARD SPEND',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 15),
            Expanded(
              child: LineChart(
                LineChartData(
                  minX: 1,
                  maxX: 5,
                  minY: 0,
                  maxY: maxY,
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    getDrawingHorizontalLine: (value) =>
                        FlLine(color: Colors.grey.shade200, strokeWidth: 1),
                  ),
                  titlesData: FlTitlesData(
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        interval: 1,
                        getTitlesWidget: (value, meta) {
                          final week = value.toInt();
                          if (week < 1 || week > 5) {
                            return const SizedBox.shrink();
                          }
                          return SideTitleWidget(
                            meta: meta,
                            child: Text(
                              'W$week',
                              style: const TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 38,
                        interval: 1,
                        getTitlesWidget: (value, meta) {
                          final double maxV = meta.max;
                          final allowedValues = [
                            0,
                            (maxV * 0.25).toInt(),
                            (maxV * 0.5).toInt(),
                            (maxV * 0.75).toInt(),
                            maxV.toInt(),
                          ];

                          if (!allowedValues.contains(value.toInt())) {
                            return const SizedBox.shrink();
                          }

                          return Text(
                            '₹${value.toInt()}k',
                            style: const TextStyle(
                              color: Colors.grey,
                              fontSize: 10,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  borderData: FlBorderData(show: false),
                  extraLinesData: boundaryLimit != null
                      ? ExtraLinesData(
                          horizontalLines: [
                            HorizontalLine(
                              y: boundaryLimit! / 1000,
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
                                    'TARGET: ₹${(boundaryLimit! / 1000).toStringAsFixed(0)}k',
                              ),
                            ),
                          ],
                        )
                      : null,
                  lineTouchData: LineTouchData(
                    enabled: true,
                    handleBuiltInTouches: true,
                    touchTooltipData: LineTouchTooltipData(
                      getTooltipColor: (touchedSpot) => const Color(0xFF0F172A),
                      tooltipBorderRadius: BorderRadius.circular(12),
                      tooltipPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      tooltipMargin: 8,
                      fitInsideHorizontally: true,
                      fitInsideVertically: true,
                      tooltipBorder: const BorderSide(
                        color: Color(0xFF334155),
                        width: 1,
                      ),
                      getTooltipItems: (touchedSpots) {
                        final hasCredit = creditSpots.any((s) => s.y > 0);

                        return touchedSpots.map((spot) {
                          final week = spot.x.toInt();
                          final isFirst = spot == touchedSpots.first;

                          String label = "";
                          double amount = 0.0;
                          Color metricColor = primaryThemeColor;

                          if (spot.barIndex == 0) {
                            label = 'Weekly Spent';
                            amount = debitWeekly[week] ?? 0.0;
                            metricColor = Colors.white;
                          } else if (spot.barIndex == 1 && hasCredit) {
                            label = 'Credit/Repay';
                            amount = creditWeekly[week] ?? 0.0;
                            metricColor = Colors.white;
                          } else {
                            label = 'Cumulative';
                            amount = cumulativeWeekly[week] ?? 0.0;
                            metricColor = Colors.white;
                          }

                          final formattedAmount = NumberFormat.currency(
                            symbol: '₹',
                            decimalDigits: 0,
                            locale: 'en_IN',
                          ).format(amount);

                          if (isFirst) {
                            return LineTooltipItem(
                              'WEEK $week SUMMARY\n---------------------\n',
                              const TextStyle(
                                color: Color(0xFF94A3B8),
                                fontWeight: FontWeight.bold,
                                fontSize: 9.5,
                                letterSpacing: 0.8,
                              ),
                              children: [
                                TextSpan(
                                  text: '●  $label: ',
                                  style: TextStyle(
                                    color: metricColor,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 10,
                                  ),
                                ),
                                TextSpan(
                                  text: formattedAmount,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11.5,
                                  ),
                                ),
                              ],
                            );
                          } else {
                            return LineTooltipItem(
                              '●  $label: ',
                              TextStyle(
                                color: metricColor,
                                fontWeight: FontWeight.w600,
                                fontSize: 11,
                              ),
                              children: [
                                TextSpan(
                                  text: formattedAmount,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11.5,
                                  ),
                                ),
                              ],
                            );
                          }
                        }).toList();
                      },
                    ),
                    getTouchedSpotIndicator: (barData, spotIndexes) {
                      return spotIndexes.map((index) {
                        final color =
                            barData.gradient?.colors.first ?? primaryThemeColor;
                        return TouchedSpotIndicatorData(
                          FlLine(
                            color: color.withValues(alpha: 0.35),
                            strokeWidth: 1.5,
                            dashArray: [4, 4],
                          ),
                          FlDotData(
                            getDotPainter: (p0, p1, p2, p3) =>
                                FlDotCirclePainter(
                                  radius: 5,
                                  color: Colors.white,
                                  strokeWidth: 2.5,
                                  strokeColor: color,
                                ),
                          ),
                        );
                      }).toList();
                    },
                  ),
                  lineBarsData: [
                    LineChartBarData(
                      spots: debitSpots,
                      isCurved: true,
                      preventCurveOverShooting: true,
                      gradient: debitGradient,
                      barWidth: 3,
                      isStrokeCapRound: true,
                      dotData: FlDotData(
                        show: true,
                        getDotPainter: (spot, percent, barData, index) =>
                            FlDotCirclePainter(
                              radius: 3.5,
                              color: Colors.white,
                              strokeWidth: 2.5,
                              strokeColor: primaryThemeColor,
                            ),
                      ),
                      belowBarData: BarAreaData(
                        show: true,
                        gradient: LinearGradient(
                          colors: debitGradient.colors
                              .map((c) => c.withValues(alpha: 0.12))
                              .toList(),
                        ),
                      ),
                    ),
                    if (creditSpots.any((s) => s.y > 0))
                      LineChartBarData(
                        spots: creditSpots,
                        isCurved: true,
                        preventCurveOverShooting: true,
                        gradient: creditGradient,
                        barWidth: 3,
                        isStrokeCapRound: true,
                        dotData: FlDotData(
                          show: true,
                          getDotPainter: (spot, percent, barData, index) =>
                              FlDotCirclePainter(
                                radius: 3.5,
                                color: Colors.white,
                                strokeWidth: 2.5,
                                strokeColor: const Color(0xFF10B981),
                              ),
                        ),
                        belowBarData: BarAreaData(
                          show: true,
                          gradient: LinearGradient(
                            colors: creditGradient.colors
                                .map((c) => c.withValues(alpha: 0.1))
                                .toList(),
                          ),
                        ),
                      ),
                    LineChartBarData(
                      spots: cumulativeSpots,
                      isCurved: true,
                      preventCurveOverShooting: true,
                      gradient: const LinearGradient(
                        colors: [Color(0xFF059669), Color(0xFF10B981)],
                      ),
                      barWidth: 3.5,
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
                          colors: [
                            const Color(0xFF10B981).withValues(alpha: 0.15),
                            const Color(0xFF10B981).withValues(alpha: 0.0),
                          ],
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                        ),
                      ),
                    ),
                  ],
                ),
                duration: const Duration(milliseconds: 500),
                curve: Curves.easeInOutCubic,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildLegendItem('Weekly Spent', primaryThemeColor),
                const SizedBox(width: 16),
                if (creditSpots.any((s) => s.y > 0)) ...[
                  _buildLegendItem('Credit/Repay', const Color(0xFF10B981)),
                  const SizedBox(width: 16),
                ],
                _buildLegendItem('Cumulative Spent', const Color(0xFF059669)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLegendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: const TextStyle(
            color: Colors.black54,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
