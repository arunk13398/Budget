import 'package:flutter/material.dart';

class WarningBox extends StatelessWidget {
  final double cardBoundary;
  final double currentTotal;
  final String cardName;

  const WarningBox({
    super.key,
    required this.cardBoundary,
    required this.currentTotal,
    required this.cardName,
  });

  String _formatAmount(double amount) {
    final int val = amount.round();
    final String str = val.abs().toString();
    if (str.length <= 3) return '${amount < 0 ? '-' : ''}₹$str';

    final String lastThree = str.substring(str.length - 3);
    final String otherNumbers = str.substring(0, str.length - 3);

    final StringBuffer result = StringBuffer();
    int count = 0;
    for (int i = otherNumbers.length - 1; i >= 0; i--) {
      if (count == 2) {
        result.write(',');
        count = 0;
      }
      result.write(otherNumbers[i]);
      count++;
    }

    final String formattedOther = result.toString().split('').reversed.join('');
    return '${amount < 0 ? '-' : ''}₹$formattedOther,$lastThree';
  }

  @override
  Widget build(BuildContext context) {
    final excess = currentTotal - cardBoundary;
    final isExceeded = excess > 0;
    final percentage = cardBoundary > 0 ? (currentTotal / cardBoundary) * 100 : 100.0;
    final formattedCurrent = _formatAmount(currentTotal);
    final formattedBoundary = _formatAmount(cardBoundary);
    final formattedExcess = _formatAmount(excess.abs());

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [
            Color(0xFFFFFBEB), // Soft warm amber
            Color(0xFFFFF1F2), // Rose/crimson whisper
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFFCA5A5).withValues(alpha: 0.55),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFEF4444).withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header Row: Glowing Icon + Title + Over Limit Badge
          Row(
            children: [
              // Icon Badge with Fire/Alert Gradient & Glow
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFF59E0B), Color(0xFFEF4444)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.28),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.warning_rounded,
                  color: Colors.white,
                  size: 15,
                ),
              ),
              const SizedBox(width: 10),

              // Title and Card Pill
              Expanded(
                child: Row(
                  children: [
                    Text(
                      isExceeded ? 'Boundary Exceeded' : 'Boundary Reached',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF991B1B),
                        fontSize: 12.5,
                        letterSpacing: -0.2,
                      ),
                    ),
                    if (cardName.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1.5,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: const Color(0xFFFCA5A5).withValues(alpha: 0.45),
                            width: 0.8,
                          ),
                        ),
                        child: Text(
                          cardName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF7F1D1D),
                            fontSize: 10,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // Excess highlight chip
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFFF87171).withValues(alpha: 0.35),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.arrow_upward_rounded,
                      size: 11,
                      color: Color(0xFFDC2626),
                    ),
                    const SizedBox(width: 2),
                    Text(
                      isExceeded ? '+$formattedExcess' : '100%',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Color(0xFFDC2626),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 7),

          // Details Row: Spent vs Limit + Percentage
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              RichText(
                text: TextSpan(
                  style: const TextStyle(
                    color: Color(0xFF78350F),
                    fontSize: 11.5,
                  ),
                  children: [
                    const TextSpan(text: 'Spent '),
                    TextSpan(
                      text: formattedCurrent,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF991B1B),
                      ),
                    ),
                    const TextSpan(
                      text: ' of ',
                      style: TextStyle(
                        color: Color(0xFF9CA3AF),
                        fontSize: 11,
                      ),
                    ),
                    TextSpan(
                      text: formattedBoundary,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF4B5563),
                      ),
                    ),
                    const TextSpan(
                      text: ' limit',
                      style: TextStyle(
                        color: Color(0xFF9CA3AF),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                '${percentage.toStringAsFixed(0)}%',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 11.5,
                  color: Color(0xFFDC2626),
                ),
              ),
            ],
          ),

          const SizedBox(height: 5),

          // Micro Progress Bar showing the budget overflow
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: Container(
              height: 4.5,
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFFFEE2E2),
                borderRadius: BorderRadius.circular(3),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final totalWidth = constraints.maxWidth;
                  final budgetFraction =
                      (cardBoundary / (currentTotal > 0 ? currentTotal : 1.0))
                          .clamp(0.0, 1.0);
                  final budgetWidth = totalWidth * budgetFraction;
                  final excessWidth = totalWidth - budgetWidth;

                  return Row(
                    children: [
                      // Base budget portion (Warm amber gradient)
                      Container(
                        width: budgetWidth,
                        height: 4.5,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFFFBBF24), Color(0xFFF97316)],
                          ),
                        ),
                      ),
                      // Exceeded portion (Vibrant Red)
                      if (excessWidth > 0)
                        Container(
                          width: excessWidth,
                          height: 4.5,
                          color: const Color(0xFFDC2626),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
