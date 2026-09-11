import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../../core/constants/app_constants.dart';

class ExpensePieChart extends StatelessWidget {
  final Map<String, double> cardLimits;
  final Map<String, double> groupLimits;
  final Map<String, int> groupColors;
  final Map<String, String>? cardThemes;
  final Map<String, Color>? cardColors;

  const ExpensePieChart({
    super.key,
    required this.cardLimits,
    required this.groupLimits,
    required this.groupColors,
    this.cardThemes,
    this.cardColors,
  });

  static const List<Color> _defaultPalette = [
    Color(0xFF2563EB), // Vibrant Blue
    Color(0xFF10B981), // Emerald Green
    Color(0xFF9333EA), // Royal Purple
    Color(0xFFF59E0B), // Amber
    Color(0xFFEC4899), // Hot Pink
    Color(0xFF06B6D4), // Cyan
  ];

  String _formatAmount(double amount) {
    if (amount >= 1000) {
      final kVal = amount / 1000;
      return '₹${kVal.toStringAsFixed(1)}k';
    }
    return '₹${amount.toStringAsFixed(0)}';
  }

  Color _getCardColor(String cardName) {
    if (cardColors != null && cardColors!.containsKey(cardName)) {
      return cardColors![cardName]!;
    }
    if (cardThemes != null) {
      String? themeName = cardThemes![cardName];
      if (themeName == null) {
        final cleanInput = cardName.replaceAll(RegExp(r'[^A-Z0-9]'), '').toUpperCase();
        if (cleanInput.isNotEmpty) {
          for (final entry in cardThemes!.entries) {
            final cleanKey = entry.key.replaceAll(RegExp(r'[^A-Z0-9]'), '').toUpperCase();
            if (cleanKey.isNotEmpty && cleanKey == cleanInput) {
              themeName = entry.value;
              break;
            }
          }
        }
      }
      themeName ??= 'Ocean';
      final gradient = AppConstants.themeGradients[themeName] ?? AppConstants.themeGradients['Ocean']!;
      return gradient.length > 1 ? gradient[1] : gradient.last;
    }
    return const Color(0xFF64748B);
  }

  @override
  Widget build(BuildContext context) {
    final double totalBudget = cardLimits.values.fold(0.0, (s, v) => s + v);
    final double totalGroupLimits = groupLimits.values.fold(0.0, (s, v) => s + v);
    final double unallocated = (totalBudget - totalGroupLimits).clamp(0.0, totalBudget);

    return Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.grey.shade200, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Text(
            'BUDGET PLANS',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  flex: 5,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      PieChart(
                        PieChartData(
                          sectionsSpace: 2,
                          centerSpaceRadius: 45,
                          startDegreeOffset: -90,
                          sections: _getSections(totalBudget, unallocated),
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Total Budget',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF94A3B8),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '₹${totalBudget.toStringAsFixed(0)}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0F172A),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 22,),
                Expanded(
                  flex: 3,
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'DETAILS ADDED',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: 5),
                        // CARDS Section
                        if (cardLimits.isNotEmpty) ...[
                          const Text(
                            'CARDS',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF0F172A),
                              letterSpacing: 0.8,
                            ),
                          ),
                          const SizedBox(height: 6),
                          ...cardLimits.entries.map((entry) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2.5),
                              child: Row(
                                children: [
                                  Container(
                                    width: 7,
                                    height: 7,
                                    decoration: BoxDecoration(
                                      color: _getCardColor(entry.key),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      entry.key,
                                      style: const TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF334155),
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Text(
                                    _formatAmount(entry.value),
                                    style: const TextStyle(
                                      fontSize: 9,
                                      color: Color(0xFF64748B),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Divider(height: 1, thickness: 1, color: Color(0xFFE2E8F0)),
                          ),
                        ],

                        // GROUPS Section
                        if (groupLimits.isNotEmpty) ...[
                          const Text(
                            'GROUPS',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                            ),
                          ),
                          const SizedBox(height: 6),
                          ...groupLimits.entries.toList().asMap().entries.map((entry) {
                            final index = entry.key;
                            final groupEntry = entry.value;
                            final label = groupEntry.key;
                            final limit = groupEntry.value;

                            final colorInt = groupColors[label];
                            final color = colorInt != null
                                ? Color(colorInt)
                                : _defaultPalette[index % _defaultPalette.length];

                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 2.5),
                              child: Row(
                                children: [
                                  Container(
                                    width: 7,
                                    height: 7,
                                    decoration: BoxDecoration(
                                      color: color,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      label,
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 1,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Text(
                                    _formatAmount(limit),
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }),
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Divider(height: 1, thickness: 1, color: Color(0xFFE2E8F0)),
                          ),
                        ],
                        // REMAINING Section
                        Row(
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: const BoxDecoration(
                                color: Color(0xFF10B981),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'REMAINING',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1,
                                ),
                              ),
                            ),
                            Text(
                              _formatAmount(unallocated),
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<PieChartSectionData> _getSections(double totalBudget, double unallocated) {
    final List<PieChartSectionData> sections = [];

    int colorIdx = 0;
    groupLimits.forEach((label, limit) {
      if (limit > 0) {
        final colorInt = groupColors[label];
        final color = colorInt != null
            ? Color(colorInt)
            : _defaultPalette[colorIdx % _defaultPalette.length];
        colorIdx++;

        sections.add(
          PieChartSectionData(
            color: color,
            value: limit,
            title: '',
            radius: 45,
          ),
        );
      }
    });

    if (unallocated > 0 || sections.isEmpty) {
      sections.add(
        PieChartSectionData(
          color: const Color(0xFFF1F5F9), // Subtle light grey slice
          value: unallocated > 0 ? unallocated : (totalBudget > 0 ? totalBudget : 1.0),
          title: '',
          radius: 40,
        ),
      );
    }

    return sections;
  }
}
