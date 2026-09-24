import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../domain/entities/expense.dart';

class CombinedGroupBarChart extends StatelessWidget {
  final List<Expense> debitExpenses;
  final Map<String, double> groupLimits;
  final Map<String, int> groupColors;
  final Map<String, String> categoryGroups;
  final Map<String, String> transactionGroups;
  final double totalBudget;

  const CombinedGroupBarChart({
    super.key,
    required this.debitExpenses,
    required this.groupLimits,
    required this.groupColors,
    required this.categoryGroups,
    required this.transactionGroups,
    required this.totalBudget,
  });

  @override
  Widget build(BuildContext context) {
    final Map<String, double> groupSpending = {};
    for (var expense in debitExpenses) {
      final label = transactionGroups[expense.id] ?? categoryGroups[expense.name.trim().toUpperCase()] ?? 'Unread';
      groupSpending[label] = (groupSpending[label] ?? 0) + expense.amount;
    }

    final assignedGroups = categoryGroups.values.toSet();
    final activeGroups = groupLimits.keys.where((g) => (groupLimits[g] ?? 0) > 0).toList();

    final List<String> displayGroups = activeGroups;

    final double totalSpent = activeGroups.fold(0.0, (sum, group) => sum + (groupSpending[group] ?? 0.0));

    double maxChartValue = totalSpent;
    for (var group in activeGroups) {
      final spent = groupSpending[group] ?? 0.0;
      final limit = groupLimits[group] ?? 0.0;
      if (spent > maxChartValue) maxChartValue = spent;
      if (limit > maxChartValue) maxChartValue = limit;
    }

    if (maxChartValue == 0) {
      maxChartValue = totalBudget > 0 ? totalBudget : 1000;
    }

    final double finalMaxY = maxChartValue > 0 ? (maxChartValue / 1000) * 1.05 : 101.0;

    final barGroups = displayGroups.asMap().entries.map((entry) {
      final index = entry.key;
      final group = entry.value;

      double spent;
      double limit;
      Color color;
      LinearGradient? gradient;

      spent = groupSpending[group] ?? 0;
      limit = groupLimits[group] ?? 0;
      color = Color(groupColors[group] ?? Colors.blue.value);

      return BarChartGroupData(
        x: index,
        barRods: [
          BarChartRodData(
            toY: spent / 1000,
            color: gradient == null ? color : null,
            gradient: gradient,
            width: 16,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
            backDrawRodData: BackgroundBarChartRodData(
              show: true,
              toY: limit / 1000,
              color: color.withValues(alpha: 0.2),
            ),
          ),
        ],
      );
    }).toList();

    final List<HorizontalLine> horizontalLines = [
      ...groupLimits.entries
          .where((e) => e.value > 0 && activeGroups.contains(e.key))
          .map((e) {
        return HorizontalLine(
          y: e.value / 1000,
          color: Color(groupColors[e.key] ?? Colors.grey.value).withValues(alpha: 0.5),
          strokeWidth: 1,
          dashArray: [4, 4],
          label: HorizontalLineLabel(
            show: true,
            alignment: Alignment.topRight,
            padding: const EdgeInsets.only(right: 5, bottom: 2),
            style: const TextStyle(
              color: Colors.black,
              fontSize: 7,
              fontWeight: FontWeight.bold,
            ),
            labelResolver: (line) => e.key,
          ),
        );
      }),
    ];

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.grey.shade200, width: 0.5),
      ),
      child: Column(
        children: [
          const Text(
            'BUDGET SPENDS',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: BarChart(
              BarChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (value) =>
                      FlLine(color: Colors.grey.shade100, strokeWidth: 1),
                ),
                alignment: BarChartAlignment.spaceAround,
                maxY: finalMaxY,
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (group) => Colors.black,
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      return BarTooltipItem(
                        '${displayGroups[group.x]}\n₹${(rod.toY * 1000).toStringAsFixed(0)}',
                        const TextStyle(color: Colors.white, fontSize: 10),
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  show: true,
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 40,
                      interval: (finalMaxY / 4) > 0 ? (finalMaxY / 4) : 5,
                      getTitlesWidget: (value, meta) {
                        return Text(
                          '₹${value.toInt()}k',
                          style: const TextStyle(color: Colors.grey, fontSize: 8),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final index = value.toInt();
                        if (index < 0 || index >= displayGroups.length) {
                          return const SizedBox.shrink();
                        }
                        final groupName = displayGroups[index];
                        final shortName = groupName.length > 3 ? groupName.substring(0, 3) : groupName;
                        return Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            shortName.toUpperCase(),
                            style: const TextStyle(color: Colors.grey, fontSize: 8),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                extraLinesData: ExtraLinesData(horizontalLines: horizontalLines),
                barGroups: barGroups,
              ),
            ),
          ),
        ],
      ),
    );
  }
}