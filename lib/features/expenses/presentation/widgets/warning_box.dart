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
    final formattedCurrent = _formatAmount(currentTotal);
    final formattedBoundary = _formatAmount(cardBoundary);
    final formattedExcess = _formatAmount(excess);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFFFCD34D).withValues(alpha: 0.8),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: const BoxDecoration(
              color: Color(0xFFFEF3C7),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.warning_amber_rounded,
              color: Color(0xFFD97706),
              size: 16,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Text(
                      'Boundary Reached',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFB45309),
                        fontSize: 12,
                      ),
                    ),
                    if (cardName.isNotEmpty) ...[
                      Text(
                        ' • ',
                        style: TextStyle(
                          color: Colors.amber.shade800,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        cardName,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF92400E),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                RichText(
                  text: TextSpan(
                    style: const TextStyle(
                      color: Color(0xFF78350F),
                      fontSize: 11.5,
                      height: 1.3,
                    ),
                    children: [
                      const TextSpan(text: 'Spent '),
                      TextSpan(
                        text: formattedCurrent,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFB45309),
                        ),
                      ),
                      const TextSpan(text: ' (Limit '),
                      TextSpan(
                        text: formattedBoundary,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const TextSpan(text: ', Exceeded by '),
                      TextSpan(
                        text: formattedExcess,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFDC2626),
                        ),
                      ),
                      const TextSpan(text: ')'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
