import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../domain/entities/expense.dart';

class TotalBudgetOverviewCard extends StatelessWidget {
  final List<String> visibleCards;
  final List<Expense> expenses;
  final int selectedMonth;
  final int selectedYear;
  final String? selectedCard;
  final List<Color>? selectedCardColors;
  final Map<String, List<Color>>? cardThemeGradients;
  final Function(String)? onCardTap;

  const TotalBudgetOverviewCard({
    super.key,
    required this.visibleCards,
    required this.expenses,
    required this.selectedMonth,
    required this.selectedYear,
    this.selectedCard,
    this.selectedCardColors,
    this.cardThemeGradients,
    this.onCardTap,
  });

  String _getDateRangeText() {
    final now = DateTime.now();
    final monthDate = DateTime(selectedYear, selectedMonth + 1);
    final monthName = DateFormat('MMM').format(monthDate);

    if (now.month == (selectedMonth + 1) && now.year == selectedYear) {
      return 'Data from 1-${now.day} $monthName, $selectedYear';
    } else {
      final daysInMonth = DateTime(selectedYear, selectedMonth + 2, 0).day;
      return 'Data from 1-$daysInMonth $monthName, $selectedYear';
    }
  }

  String _formatAmountWithDecimals(double amount) {
    final formatter = NumberFormat.currency(
      locale: 'en_IN',
      symbol: '₹',
      decimalDigits: 2,
    );
    return formatter.format(amount);
  }

  String _formatK(double val) {
    if (val >= 1000) {
      final k = val / 1000;
      return k == k.roundToDouble() ? '${k.toInt()}K' : '${k.toStringAsFixed(1)}K';
    }
    return val.toInt().toString();
  }

  String _formatCardLabel(String card) {
    String clean = card.trim();
    // Strip trailing technical suffixes like -S, -P, -C
    if (clean.endsWith('-S') || clean.endsWith('-s') ||
        clean.endsWith('-P') || clean.endsWith('-p') ||
        clean.endsWith('-C') || clean.endsWith('-c')) {
      clean = clean.substring(0, clean.length - 2).trim();
    }
    return clean;
  }

  double _getCardSpend(String card, int month, int year) {
    final cleanCard = card.trim().toUpperCase();
    return expenses.where((e) {
      if (e.date.month != month || e.date.year != year) return false;
      if (e.type != 'spent' && e.type != 'debited') return false;
      final bank = e.bank.trim().toUpperCase();
      return bank.contains(cleanCard) || cleanCard.contains(bank);
    }).fold(0.0, (sum, e) => sum + e.amount);
  }

  /// Resolves the segment colors for the gauge graph based on the selected card color
  List<Color> _resolveSegmentColors(List<String> cards) {
    // 1. Resolve base theme colors from selected card
    final baseColors = selectedCardColors ??
        (selectedCard != null && cardThemeGradients != null
            ? cardThemeGradients![selectedCard]
            : null) ??
        const [Color(0xFF1E40AF), Color(0xFF2563EB), Color(0xFF3B82F6)];

    final primary = baseColors.length > 1 ? baseColors[1] : baseColors.first;
    final secondary = baseColors.length > 2
        ? baseColors[2]
        : (baseColors.length > 1 ? baseColors[1] : baseColors.first);

    final hsl = HSLColor.fromColor(primary);
    final tertiary = hsl
        .withLightness((hsl.lightness + 0.18).clamp(0.0, 0.92))
        .withSaturation((hsl.saturation * 0.8).clamp(0.0, 1.0))
        .toColor();
    final quaternary = hsl
        .withLightness((hsl.lightness - 0.16).clamp(0.12, 0.9))
        .toColor();

    final palette = [primary, secondary, tertiary, quaternary];

    // If individual card themes are provided, allow each to map cleanly
    if (cardThemeGradients != null && cardThemeGradients!.isNotEmpty) {
      final List<Color> result = [];
      for (int i = 0; i < cards.length; i++) {
        final card = cards[i];
        final isSelected = selectedCard != null &&
            (card.trim().toUpperCase() == selectedCard!.trim().toUpperCase() ||
                card.contains(selectedCard!) ||
                selectedCard!.contains(card));

        if (isSelected) {
          result.add(primary);
        } else if (cardThemeGradients!.containsKey(card)) {
          final cList = cardThemeGradients![card]!;
          result.add(cList.length > 1 ? cList[1] : cList.first);
        } else {
          result.add(palette[(i + 1) % palette.length]);
        }
      }
      if (result.length == cards.length) {
        return result;
      }
    }

    return List.generate(cards.length, (i) => palette[i % palette.length]);
  }

  @override
  Widget build(BuildContext context) {
    // 1. Resolve cards to display
    List<String> cards = visibleCards.where((c) => c.trim().isNotEmpty).toList();
    if (cards.isEmpty) {
      cards = expenses
          .map((e) => e.bank.trim())
          .where((b) => b.isNotEmpty)
          .toSet()
          .take(4)
          .toList();
    }
    if (cards.isEmpty) {
      cards = ['Card 1', 'Card 2', 'Card 3', 'Card 4'];
    }

    // 2. Calculate current month spending per card
    final currentMonthNum = selectedMonth + 1;
    final cardSpends = cards.map((c) => _getCardSpend(c, currentMonthNum, selectedYear)).toList();

    // Total spend across all visible cards
    final totalSpend = cardSpends.fold(0.0, (sum, val) => sum + val);

    // 3. Calculate previous month spending for comparison
    final prevDate = DateTime(selectedYear, currentMonthNum - 1, 1);
    final prevMonthNum = prevDate.month;
    final prevYearNum = prevDate.year;
    final prevTotalSpend = cards
        .map((c) => _getCardSpend(c, prevMonthNum, prevYearNum))
        .fold(0.0, (sum, val) => sum + val);

    int diffPct = 0;
    bool isIncreased = true;
    if (prevTotalSpend > 0) {
      final diff = ((totalSpend - prevTotalSpend) / prevTotalSpend) * 100;
      diffPct = diff.round().abs();
      isIncreased = totalSpend >= prevTotalSpend;
    } else if (totalSpend > 0) {
      diffPct = 100;
      isIncreased = true;
    }

    // 4. Calculate gauge max scale (target budget proportion)
    double maxScale = 5000.0;
    if (totalSpend > 0) {
      if (totalSpend <= 1500) {
        maxScale = 2400.0;
      } else if (totalSpend <= 3500) {
        maxScale = 5000.0;
      } else if (totalSpend <= 7000) {
        maxScale = 10000.0;
      } else if (totalSpend <= 15000) {
        maxScale = 20000.0;
      } else if (totalSpend <= 30000) {
        maxScale = 40000.0;
      } else if (totalSpend <= 75000) {
        maxScale = 100000.0;
      } else {
        maxScale = ((totalSpend / 10000).ceil() * 10000 * 1.3).toDouble();
      }
    }

    // 5. Build dynamic segment colors based on selected card
    final segmentColors = _resolveSegmentColors(cards);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: const Color(0xFFF1F5F9),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.03),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Left Column: Title, Date, Trend & Interactive Card Legend
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Budget Overview',
                  style: TextStyle(
                    fontSize: 18.5,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0B132B),
                    letterSpacing: -0.4,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  _getDateRangeText(),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF94A3B8),
                  ),
                ),
                const SizedBox(height: 10),
                // Trend badge
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isIncreased ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                      size: 13,
                      color: isIncreased ? const Color(0xFFEA580C) : const Color(0xFF10B981),
                    ),
                    const SizedBox(width: 2),
                    Text(
                      '${isIncreased ? '+' : '-'}$diffPct%',
                      style: TextStyle(
                        color: isIncreased ? const Color(0xFFEA580C) : const Color(0xFF10B981),
                        fontWeight: FontWeight.bold,
                        fontSize: 11.5,
                      ),
                    ),
                    const Text(
                      ' than last month',
                      style: TextStyle(
                        color: Color(0xFF94A3B8),
                        fontWeight: FontWeight.w500,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                // Interactive Card Legend with active selection indication
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: List.generate(cards.length, (index) {
                    final cardName = cards[index];
                    final label = _formatCardLabel(cardName);
                    final spend = cardSpends[index];
                    final color = segmentColors[index % segmentColors.length];
                    final isSelected = selectedCard != null &&
                        (cardName.trim().toUpperCase() == selectedCard!.trim().toUpperCase() ||
                            cardName.contains(selectedCard!) ||
                            selectedCard!.contains(cardName));

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: GestureDetector(
                        onTap: () {
                          if (onCardTap != null) onCardTap!(cardName);
                        },
                        behavior: HitTestBehavior.opaque,
                        child: Container(
                          padding: isSelected
                              ? const EdgeInsets.symmetric(horizontal: 7, vertical: 3)
                              : const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
                          decoration: isSelected
                              ? BoxDecoration(
                                  color: color.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: color.withValues(alpha: 0.3),
                                    width: 1,
                                  ),
                                )
                              : null,
                          child: Row(
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
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                                  color: isSelected ? const Color(0xFF0F172A) : const Color(0xFF475569),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                _formatK(spend),
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w700,
                                  color: isSelected ? color : const Color(0xFF0F172A),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),
                ),
              ],
            ),
          ),

          const SizedBox(width: 14),

          // Right Column: Semicircular Curved Gauge Graph themed to selected card
          Expanded(
            flex: 6,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                final gaugeHeight = (width / 2) + 16.0;

                return SizedBox(
                  width: width,
                  height: gaugeHeight,
                  child: Stack(
                    alignment: Alignment.bottomCenter,
                    children: [
                      // Semicircle arc painter using selected card colors
                      CustomPaint(
                        size: Size(width, gaugeHeight),
                        painter: CurvedGaugePainter(
                          values: cardSpends,
                          colors: segmentColors,
                          maxValue: maxScale,
                          strokeWidth: 20.0,
                        ),
                      ),
                      // Center Content: SPENT + Amount
                      Positioned(
                        bottom: 6,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'SPENT',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.5,
                                color: Color(0xFF64748B),
                              ),
                            ),
                            const SizedBox(height: 2),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                _formatAmountWithDecimals(totalSpend),
                                style: const TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF0F172A),
                                  letterSpacing: -0.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Custom painter for the semicircular curved gauge graph with colored card segments
/// and clean white divider gaps, dynamically styled with the selected card's color.
class CurvedGaugePainter extends CustomPainter {
  final List<double> values;
  final List<Color> colors;
  final double maxValue;
  final Color trackColor;
  final Color dividerColor;
  final double strokeWidth;

  CurvedGaugePainter({
    required this.values,
    required this.colors,
    required this.maxValue,
    this.trackColor = const Color(0xFFEDF2F7),
    this.dividerColor = Colors.white,
    this.strokeWidth = 20.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final center = Offset(size.width / 2, size.height - 4);
    final radius = math.min(
      (size.width / 2) - strokeWidth / 2,
      size.height - strokeWidth / 2 - 4,
    );

    if (radius <= 0) return;

    final rect = Rect.fromCircle(center: center, radius: radius);

    // 1. Draw full 180° background track from math.pi (left) to 0 (right)
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;

    canvas.drawArc(rect, math.pi, math.pi, false, trackPaint);

    final totalValue = values.fold(0.0, (sum, v) => sum + v);
    if (totalValue <= 0 || maxValue <= 0) return;

    // Fraction filled of the 180° arch
    final filledFraction = (totalValue / maxValue).clamp(0.0, 1.0);
    final totalSweep = filledFraction * math.pi;

    // 2. Draw colored segments for each card
    double currentStart = math.pi;
    final List<double> boundaryAngles = [];

    for (int i = 0; i < values.length; i++) {
      final val = values[i];
      if (val <= 0) continue;

      final fractionOfTotal = val / totalValue;
      final segmentSweep = fractionOfTotal * totalSweep;
      if (segmentSweep <= 0) continue;

      final color = colors[i % colors.length];
      final segmentPaint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt;

      canvas.drawArc(rect, currentStart, segmentSweep, false, segmentPaint);

      currentStart += segmentSweep;
      boundaryAngles.add(currentStart);
    }

    // 3. Draw clean white radial divider lines at segment boundaries
    if (boundaryAngles.isNotEmpty) {
      final dividerPaint = Paint()
        ..color = dividerColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.butt;

      final innerR = radius - (strokeWidth / 2) - 1.0;
      final outerR = radius + (strokeWidth / 2) + 1.0;

      for (int i = 0; i < boundaryAngles.length; i++) {
        final angle = boundaryAngles[i];
        // Skip if close to the end of the full arch (0° / 2*pi)
        if ((angle - 2 * math.pi).abs() < 0.04) continue;

        final p1 = Offset(
          center.dx + innerR * math.cos(angle),
          center.dy + innerR * math.sin(angle),
        );
        final p2 = Offset(
          center.dx + outerR * math.cos(angle),
          center.dy + outerR * math.sin(angle),
        );
        canvas.drawLine(p1, p2, dividerPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CurvedGaugePainter oldDelegate) {
    return oldDelegate.values != values ||
        oldDelegate.maxValue != maxValue ||
        oldDelegate.colors != colors ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}
