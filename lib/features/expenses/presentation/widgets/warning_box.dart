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

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFFCD34D),
          width: 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFD97706).withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF3C7),
              shape: BoxShape.circle,
              border: Border.all(
                color: const Color(0xFFFDE68A),
                width: 0.5,
              ),
            ),
            child: const Icon(
              Icons.warning_amber_rounded,
              color: Color(0xFFD97706),
              size: 18,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'BOUNDARY REACHED: ₹${cardBoundary.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFB45309),
                    fontSize: 12,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 3),
                Builder(
                  builder: (context) {
                    final excess = currentTotal - cardBoundary;
                    return Text(
                      'Current spending of ₹${currentTotal.toStringAsFixed(0)} has exceeded your set boundary limit for $cardName by ₹${excess.toStringAsFixed(0)}.',
                      style: const TextStyle(
                        color: Color(0xFF78350F),
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        height: 1.4,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
