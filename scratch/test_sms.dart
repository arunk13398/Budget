// @dart=3.0

bool isOfficialBankSenderTitle(String title) {
  final clean = title.trim();
  if (clean.isEmpty || !clean.contains('-')) return false;
  
  final upper = clean.toUpperCase();
  if (!upper.endsWith('S') && !upper.endsWith('T')) return false;

  final parts = upper.split('-');
  if (parts.length >= 2 && parts.first.length <= 4) {
    return true;
  }
  return false;
}

String extractCardBankName(String rawBank) {
  final cleanRaw = rawBank.trim();
  final parts = cleanRaw.split('-');
  if (parts.length >= 2 && parts[0].length == 2) {
    final bankPart = parts.sublist(1).join('-').toUpperCase();
    if (bankPart.isNotEmpty) {
      if (bankPart.endsWith('-S') || bankPart.endsWith('-T')) {
        return bankPart;
      }
      return '$bankPart-S';
    }
  }
  final upper = cleanRaw.toUpperCase();
  if (upper.endsWith('-S') || upper.endsWith('-T')) {
    return upper;
  }
  return '$upper-S';
}

void main() {
  final titles = [
    'BZ-KGBANK-S',
    'VM-HDFCBK-S',
    'AD-KGBANK-T',
    'JX-HDFCBK-T',
    'BP-ICICIB-T',
    'AM-SBICRD-S',
    'VK-CANBK-T',
    'HDFC Bank Loans',
    'Security',
    'Messages',
  ];

  for (final title in titles) {
    final accepted = isOfficialBankSenderTitle(title);
    if (accepted) {
      print('ACCEPTED: "$title" -> Card Bank Name: "${extractCardBankName(title)}"');
    } else {
      print('REJECTED: "$title" (Avoided)');
    }
  }
}
