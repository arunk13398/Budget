import 'package:flutter/material.dart';
import '../../../../core/constants/app_constants.dart';

class MonthSelector extends StatelessWidget {
  final int selectedMonth;
  final Function(int) onMonthSelected;
  final List<Color>? gradientColors;

  const MonthSelector({
    super.key,
    required this.selectedMonth,
    required this.onMonthSelected,
    this.gradientColors,
  });

  @override
  Widget build(BuildContext context) {
    final activeColors = gradientColors != null && gradientColors!.isNotEmpty
        ? (gradientColors!.length >= 2
            ? [gradientColors!.first, gradientColors!.last]
            : [gradientColors!.first, gradientColors!.first])
        : const [Color(0xFF1D4ED8), Color(0xFF2563EB)];
    final primaryColor = activeColors.first;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(40),
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(
          color: const Color(0xFFF1F5F9),
          width: 1.2,
        ),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: 6,
        vertical: 6,
      ),
      child: SizedBox(
        height: 38,
        child: ListView.builder(
          itemCount: AppConstants.months.length,
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          itemBuilder: (context, index) {
            final isSelected = index == selectedMonth;
            return GestureDetector(
              onTap: () => onMonthSelected(index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(right: 8),
                padding: isSelected
                    ? const EdgeInsets.fromLTRB(4, 4, 16, 4)
                    : const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 8,
                      ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(30),
                  gradient: isSelected
                      ? LinearGradient(
                          colors: activeColors,
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                        )
                      : null,
                  color: isSelected ? null : const Color(0xFFF1F4F8),
                  border: isSelected
                      ? null
                      : Border.all(
                          color: const Color(0xFFE2E8F0)
                              .withValues(alpha: 0.7),
                          width: 0.8,
                        ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: primaryColor.withValues(alpha: 0.35),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ]
                      : null,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (isSelected) ...[
                      Container(
                        width: 28,
                        height: 28,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '${DateTime.now().day}',
                          style: TextStyle(
                            color: primaryColor,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                            height: 1.0,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      AppConstants.months[index].toUpperCase(),
                      style: TextStyle(
                        color: isSelected
                            ? Colors.white
                            : const Color(0xFF475569),
                        fontWeight: FontWeight.bold,
                        fontSize: 12.5,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
