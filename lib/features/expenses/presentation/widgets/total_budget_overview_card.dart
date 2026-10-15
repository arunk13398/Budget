import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../domain/entities/expense.dart';

class TotalBudgetOverviewCard extends StatefulWidget {
  final List<String> visibleCards;
  final List<Expense> expenses;
  final int selectedMonth;
  final int selectedYear;
  final String? selectedCard;
  final List<Color>? selectedCardColors;
  final Map<String, List<Color>>? cardThemeGradients;
  final Function(String)? onCardTap;
  final double height;
  final Color defaultGaugeColor;
  final Color greenGaugeColor;
  final Color orangeGaugeColor;
  final Color redGaugeColor;
  final bool useMultiColorGauge;

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
    this.height = 150.0,
    this.defaultGaugeColor = const Color(0xFFC3F42E),
    this.greenGaugeColor = const Color(0xFF22C55E),
    this.orangeGaugeColor = const Color(0xFFF97316),
    this.redGaugeColor = const Color(0xFFEF4444),
    this.useMultiColorGauge = false,
  });

  @override
  State<TotalBudgetOverviewCard> createState() => _TotalBudgetOverviewCardState();
}

class _TotalBudgetOverviewCardState extends State<TotalBudgetOverviewCard> {
  static const double _itemHeight = 27.0;
  late final ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _scrollToSelectedCard(animate: false);
      }
    });
  }

  @override
  void didUpdateWidget(covariant TotalBudgetOverviewCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedCard != widget.selectedCard ||
        oldWidget.visibleCards != widget.visibleCards) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _scrollToSelectedCard(animate: true);
        }
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  List<String> _getDisplayCards() {
    List<String> cards = widget.visibleCards.where((c) => c.trim().isNotEmpty).toList();
    if (cards.isEmpty) {
      cards = widget.expenses
          .map((e) => e.bank.trim())
          .where((b) => b.isNotEmpty)
          .toSet()
          .take(4)
          .toList();
    }
    if (cards.isEmpty) {
      cards = ['Card 1', 'Card 2', 'Card 3', 'Card 4'];
    }
    return cards;
  }

  bool _isCardSelected(String cardName, String? selectedCard) {
    if (selectedCard == null || selectedCard.isEmpty) return false;
    final c1 = cardName.trim().toUpperCase();
    final c2 = selectedCard.trim().toUpperCase();
    if (c1 == c2) return true;
    if (c1.contains(c2) || c2.contains(c1)) return true;
    final l1 = _formatCardLabel(c1).toUpperCase();
    final l2 = _formatCardLabel(c2).toUpperCase();
    return l1 == l2 || l1.contains(l2) || l2.contains(l1);
  }

  int _getSelectedIndex(List<String> cards) {
    if (widget.selectedCard == null || cards.isEmpty) return -1;
    return cards.indexWhere((c) => _isCardSelected(c, widget.selectedCard));
  }

  void _scrollToSelectedCard({bool animate = true}) {
    final cards = _getDisplayCards();
    final index = _getSelectedIndex(cards);
    if (index >= 0) {
      _scrollToIndex(index, animate: animate);
    }
  }

  void _scrollToIndex(int index, {bool animate = true}) {
    if (!_scrollController.hasClients || index < 0) return;
    final position = _scrollController.position;
    if (!position.hasContentDimensions) return;

    final viewportHeight = position.viewportDimension;
    // Target offset positions item's vertical center in the middle of viewport
    final itemCenter = index * _itemHeight + (_itemHeight / 2);
    final targetOffset = (itemCenter - (viewportHeight / 2))
        .clamp(position.minScrollExtent, position.maxScrollExtent);

    if ((position.pixels - targetOffset).abs() < 1.0) return;

    if (animate) {
      _scrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeInOutCubic,
      );
    } else {
      _scrollController.jumpTo(targetOffset);
    }
  }

  String _getDateRangeText() {
    final now = DateTime.now();
    final monthDate = DateTime(widget.selectedYear, widget.selectedMonth + 1);
    final monthName = DateFormat('MMM').format(monthDate);

    if (now.month == (widget.selectedMonth + 1) && now.year == widget.selectedYear) {
      return 'Data from 1-${now.day} $monthName, ${widget.selectedYear}';
    } else {
      final daysInMonth = DateTime(widget.selectedYear, widget.selectedMonth + 2, 0).day;
      return 'Data from 1-$daysInMonth $monthName, ${widget.selectedYear}';
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
    return widget.expenses.where((e) {
      if (e.date.month != month || e.date.year != year) return false;
      if (e.type != 'spent' && e.type != 'debited') return false;
      final bank = e.bank.trim().toUpperCase();
      return bank.contains(cleanCard) || cleanCard.contains(bank);
    }).fold(0.0, (sum, e) => sum + e.amount);
  }

  /// Resolves the segment colors for the gauge graph based on the selected card color
  List<Color> _resolveSegmentColors(List<String> cards) {
    // 1. Resolve base theme colors from selected card
    final baseColors = widget.selectedCardColors ??
        (widget.selectedCard != null && widget.cardThemeGradients != null
            ? widget.cardThemeGradients![widget.selectedCard]
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
    if (widget.cardThemeGradients != null && widget.cardThemeGradients!.isNotEmpty) {
      final List<Color> result = [];
      for (int i = 0; i < cards.length; i++) {
        final card = cards[i];
        final isSelected = _isCardSelected(card, widget.selectedCard);

        if (isSelected) {
          result.add(primary);
        } else if (widget.cardThemeGradients!.containsKey(card)) {
          final cList = widget.cardThemeGradients![card]!;
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
    final cards = _getDisplayCards();

    // 2. Calculate current month spending per card
    final currentMonthNum = widget.selectedMonth + 1;
    final cardSpends = cards.map((c) => _getCardSpend(c, currentMonthNum, widget.selectedYear)).toList();

    // Total spend across all visible cards
    final totalSpend = cardSpends.fold(0.0, (sum, val) => sum + val);

    // 3. Calculate previous month spending for comparison
    final prevDate = DateTime(widget.selectedYear, currentMonthNum - 1, 1);
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
      height: widget.height,
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
      padding: const EdgeInsets.only(left: 18, right: 10, top: 13, bottom: 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Left Column: Title, Date, Trend & Interactive Card Legend
          Expanded(
            flex: 9,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: const Text(
                    'Budget Overview',
                    style: TextStyle(
                      fontSize: 17.5,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF0B132B),
                      letterSpacing: -0.4,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _getDateRangeText(),
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF94A3B8),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 5),
                // Trend badge
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
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
                          fontSize: 10.5,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                // Interactive Scrollable Card Legend with active selection indication
                Expanded(
                  child: RawScrollbar(
                    controller: _scrollController,
                    thumbVisibility: false,
                    thickness: 2.5,
                    radius: const Radius.circular(4),
                    thumbColor: const Color(0xFFCBD5E1),
                    child: ListView.builder(
                      controller: _scrollController,
                      itemCount: cards.length,
                      itemExtent: _itemHeight,
                      physics: const BouncingScrollPhysics(),
                      padding: EdgeInsets.zero,
                      itemBuilder: (context, index) {
                        final cardName = cards[index];
                        final label = _formatCardLabel(cardName);
                        final spend = cardSpends[index];
                        final color = segmentColors[index % segmentColors.length];
                        final isSelected = _isCardSelected(cardName, widget.selectedCard);

                        return Align(
                          alignment: Alignment.centerLeft,
                          child: GestureDetector(
                            onTap: () {
                              _scrollToIndex(index, animate: true);
                              if (widget.onCardTap != null) widget.onCardTap!(cardName);
                            },
                            behavior: HitTestBehavior.opaque,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: isSelected
                                  ? const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5)
                                  : const EdgeInsets.symmetric(horizontal: 3, vertical: 1.5),
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
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 7.0,
                                      height: 7.0,
                                      decoration: BoxDecoration(
                                        color: color,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      label,
                                      style: TextStyle(
                                        fontSize: 11.0,
                                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                                        color: isSelected ? const Color(0xFF0F172A) : const Color(0xFF475569),
                                      ),
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      _formatK(spend),
                                      style: TextStyle(
                                        fontSize: 11.0,
                                        fontWeight: FontWeight.w700,
                                        color: isSelected ? color : const Color(0xFF0F172A),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 6),

          // Right Column: Semicircular Curved Gauge Graph themed to selected card
          Expanded(
            flex: 13,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final totalWidth = constraints.maxWidth;
                final totalHeight = constraints.maxHeight > 0
                    ? constraints.maxHeight
                    : ((totalWidth / 2) + 20.0);

                const totalSegments = 24;
                final maxRadiusByWidth = (totalWidth / 2) - 2.0;
                final approxTickWidth = (maxRadiusByWidth * math.pi / totalSegments) * 0.70;
                final maxRadiusByHeight = totalHeight - (approxTickWidth / 2) - 4.0;
                final outerRadius = math.max(15.0, math.min(maxRadiusByWidth, maxRadiusByHeight));

                final tickLength = outerRadius * 0.32;
                final innerRadius = outerRadius - tickLength;
                final tickWidth = (outerRadius * math.pi / totalSegments) * 0.70;

                final gaugeVisualHeight = outerRadius + (tickWidth / 2);
                final topMargin = math.max(2.0, (totalHeight - gaugeVisualHeight) / 2);
                final centerY = topMargin + outerRadius;
                final center = Offset(totalWidth / 2, centerY);

                return SizedBox(
                  width: totalWidth,
                  height: totalHeight,
                  child: Stack(
                    children: [
                      // Semicircle arc painter using selected card colors
                      CustomPaint(
                        size: Size(totalWidth, totalHeight),
                        painter: CurvedGaugePainter(
                          values: cardSpends,
                          colors: segmentColors,
                          activeColor: widget.defaultGaugeColor,
                          greenColor: widget.greenGaugeColor,
                          orangeColor: widget.orangeGaugeColor,
                          redColor: widget.redGaugeColor,
                          useMultiColor: widget.useMultiColorGauge,
                          maxValue: maxScale,
                          totalSegments: totalSegments,
                          centerOffset: center,
                          customOuterRadius: outerRadius,
                          customTickLength: tickLength,
                          customTickWidth: tickWidth,
                        ),
                      ),
                      // Center Content: SPENT + Amount
                      Positioned(
                        left: 0,
                        right: 0,
                        top: centerY - (innerRadius * 0.44) - 20,
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'SPENT',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.6,
                                  color: Color(0xFF64748B),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 4.0),
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    _formatAmountWithDecimals(totalSpend),
                                    style: const TextStyle(
                                      fontSize: 20.5,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFF0F172A),
                                      letterSpacing: -0.5,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
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

/// Custom painter for the segmented semicircular curved gauge graph with pill-shaped ticks,
/// dynamically styled with the card's theme color and proportional spend fill.
class CurvedGaugePainter extends CustomPainter {
  final List<double> values;
  final List<Color> colors;
  final double maxValue;
  final Color trackColor;
  final Color activeColor;
  final Color greenColor;
  final Color orangeColor;
  final Color redColor;
  final bool useMultiColor;
  final int totalSegments;
  final Offset? centerOffset;
  final double? customOuterRadius;
  final double? customTickLength;
  final double? customTickWidth;

  CurvedGaugePainter({
    required this.values,
    this.colors = const [],
    required this.maxValue,
    this.activeColor = const Color(0xFFC3F42E),
    this.greenColor = const Color(0xFF22C55E),
    this.orangeColor = const Color(0xFFF97316),
    this.redColor = const Color(0xFFEF4444),
    this.trackColor = const Color(0xFFEDF2F7),
    this.useMultiColor = false,
    this.totalSegments = 24,
    this.centerOffset,
    this.customOuterRadius,
    this.customTickLength,
    this.customTickWidth,
    double strokeWidth = 20.0,
    Color dividerColor = Colors.white,
  });

  Color _getGradientColor({
    required int index,
    required int activeSegments,
    required double spendPct,
  }) {
    if (spendPct <= 55.0 || activeSegments <= 1) {
      if (activeSegments <= 1 && spendPct > 55.0) {
        if (spendPct <= 75.0) return greenColor;
        if (spendPct <= 85.0) return orangeColor;
        return redColor;
      }
      return activeColor;
    }

    final t = index / (activeSegments - 1);

    if (spendPct <= 75.0) {
      // Below 75: gradient from baseColor (Color(0xFFC3F42E)) to green
      if (t <= 0.35) {
        return activeColor;
      }
      final localT = (t - 0.35) / 0.65;
      return Color.lerp(activeColor, greenColor, localT)!;
    } else if (spendPct <= 85.0) {
      // Below 85: gradient from baseColor -> green -> orange
      if (t <= 0.25) {
        return activeColor;
      } else if (t <= 0.65) {
        final localT = (t - 0.25) / 0.40;
        return Color.lerp(activeColor, greenColor, localT)!;
      } else {
        final localT = (t - 0.65) / 0.35;
        return Color.lerp(greenColor, orangeColor, localT)!;
      }
    } else {
      // Above 85: gradient from baseColor -> green -> orange -> red
      if (t <= 0.20) {
        return activeColor;
      } else if (t <= 0.50) {
        final localT = (t - 0.20) / 0.30;
        return Color.lerp(activeColor, greenColor, localT)!;
      } else if (t <= 0.75) {
        final localT = (t - 0.50) / 0.25;
        return Color.lerp(greenColor, orangeColor, localT)!;
      } else {
        final localT = (t - 0.75) / 0.25;
        return Color.lerp(orangeColor, redColor, localT)!;
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final outerRadius = customOuterRadius ??
        math.min((size.width / 2) - 2.0, size.height - 8.0);
    if (outerRadius <= 15) return;

    final tickLength = customTickLength ?? (outerRadius * 0.32);
    final innerRadius = outerRadius - tickLength;
    final tickWidth = customTickWidth ??
        ((outerRadius * math.pi / totalSegments) * 0.70);
    final cornerRadius = tickWidth * 0.42;

    final center = centerOffset ??
        Offset(
          size.width / 2,
          math.max(
            outerRadius + 2.0,
            (size.height + outerRadius) / 2,
          ),
        );

    final totalSpend = values.fold(0.0, (sum, v) => sum + v);
    final fraction = maxValue > 0 ? (totalSpend / maxValue).clamp(0.0, 1.0) : 0.0;
    int activeSegments = (fraction * totalSegments).round();
    if (totalSpend > 0 && activeSegments == 0) {
      activeSegments = 1;
    }

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.fill;

    // Draw all segments from left (pi) around the semicircle to right (2*pi)
    for (int i = 0; i < totalSegments; i++) {
      // Angle sweeps from pi (180°, bottom-left) to 2*pi (360°, bottom-right)
      final theta = math.pi + (i + 0.5) * (math.pi / totalSegments);

      Paint paint;
      if (i < activeSegments && totalSpend > 0) {
        if (useMultiColor && colors.isNotEmpty) {
          // Map this segment index to the appropriate card spend
          final segmentProgress = (i + 0.5) / activeSegments;
          double cumulative = 0.0;
          Color segColor = colors.first;
          for (int c = 0; c < values.length; c++) {
            if (values[c] <= 0) continue;
            cumulative += values[c] / totalSpend;
            if (segmentProgress <= cumulative || c == values.length - 1) {
              segColor = colors[c % colors.length];
              break;
            }
          }
          paint = Paint()
            ..color = segColor
            ..style = PaintingStyle.fill;
        } else {
          final segColor = _getGradientColor(
            index: i,
            activeSegments: activeSegments,
            spendPct: fraction * 100,
          );
          paint = Paint()
            ..color = segColor
            ..style = PaintingStyle.fill;
        }
      } else {
        paint = trackPaint;
      }

      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(theta);
      final rect = Rect.fromLTRB(innerRadius, -tickWidth / 2, outerRadius, tickWidth / 2);
      final rrect = RRect.fromRectAndRadius(rect, Radius.circular(cornerRadius));
      canvas.drawRRect(rrect, paint);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant CurvedGaugePainter oldDelegate) {
    return oldDelegate.values != values ||
        oldDelegate.maxValue != maxValue ||
        oldDelegate.colors != colors ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.greenColor != greenColor ||
        oldDelegate.orangeColor != orangeColor ||
        oldDelegate.redColor != redColor ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.useMultiColor != useMultiColor ||
        oldDelegate.totalSegments != totalSegments ||
        oldDelegate.centerOffset != centerOffset ||
        oldDelegate.customOuterRadius != customOuterRadius ||
        oldDelegate.customTickLength != customTickLength ||
        oldDelegate.customTickWidth != customTickWidth;
  }
}
