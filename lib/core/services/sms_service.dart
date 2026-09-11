import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_sms_inbox/flutter_sms_inbox.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:readsms/readsms.dart';
import '../../features/expenses/domain/repositories/expense_repository.dart';
import '../../features/expenses/domain/entities/expense.dart';
import 'package:intl/intl.dart';

/// A single bank SMS entry.
class BankSmsEntry {
  final String sender;
  final String body;
  final double? amount;
  final DateTime date;
  final String type; // 'credit_card_spent', 'credit_card_credited', 'bank_debited', 'bank_credited', 'upi', 'other'

  BankSmsEntry({
    required this.sender,
    required this.body,
    required this.amount,
    required this.date,
    required this.type,
  });
}

/// A group of bank SMS entries by type.
class BankSmsGroup {
  final String type;        // unique key
  final String label;       // display label
  final String emoji;       // leading emoji
  final List<BankSmsEntry> entries;

  BankSmsGroup({
    required this.type,
    required this.label,
    required this.emoji,
    required this.entries,
  });

  double get total => entries.fold(0.0, (s, e) => s + (e.amount ?? 0));
}

class SmsService {
  final SmsQuery _query = SmsQuery();
  final Readsms _readSms = Readsms();
  final ExpenseRepository _repository;
  static const MethodChannel _notifChannel = MethodChannel('com.budget.planning/notifications');

  SmsService(this._repository);

  /// Initializes listening to status bar bank notifications (100% Play Store compliant)
  void initNotificationListener({void Function(Expense expense)? onExpenseAutoSynced, Map<String, String>? manualCards}) {
    if (kIsWeb) return;
    _notifChannel.setMethodCallHandler((call) async {
      if (call.method == 'onNotificationReceived') {
        try {
          final Map<String, dynamic> args = Map<String, dynamic>.from(call.arguments);
          final title = args['title'] as String? ?? '';
          final text = args['text'] as String? ?? '';
          final timestampMs = args['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch;
          final date = DateTime.fromMillisecondsSinceEpoch(timestampMs);

          final fullBody = '$title $text'.trim();
          debugPrint('--- Triggered Incoming Notification: $fullBody ---');

          final msgId = '$timestampMs';
          final expense = _parseSms(fullBody, date, msgId, title.isNotEmpty ? title : 'Bank', manualCards: manualCards);

          if (expense != null) {
            debugPrint('--- Auto-Synced Expense from Notification: ${expense.name} - ₹${expense.amount} (${expense.bank}) ---');
            await _repository.addExpense(expense);
            if (onExpenseAutoSynced != null) {
              onExpenseAutoSynced(expense);
            }
          }
        } catch (e) {
          debugPrint('Error handling incoming notification: $e');
        }
      }
    });
  }

  Future<bool> isNotificationListenerPermissionGranted() async {
    if (kIsWeb) return false;
    try {
      final res = await _notifChannel.invokeMethod<bool>('checkNotificationListenerPermission');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> requestNotificationListenerPermission() async {
    if (kIsWeb) return;
    try {
      await _notifChannel.invokeMethod('requestNotificationListenerPermission');
    } catch (_) {}
  }

  Future<void> openAutostartSettings() async {
    if (kIsWeb) return;
    try {
      await _notifChannel.invokeMethod('openAutostartSettings');
    } catch (_) {}
  }

  Future<void> rebindNotificationListener() async {
    if (kIsWeb) return;
    try {
      await _notifChannel.invokeMethod('rebindNotificationListener');
    } catch (_) {}
  }

  Future<Map<String, bool>> checkListenerStatus() async {
    if (kIsWeb) return {'isGranted': false, 'isConnected': false};
    try {
      final res = await _notifChannel.invokeMethod('checkListenerStatus');
      if (res is Map) {
        return {
          'isGranted': res['isGranted'] as bool? ?? false,
          'isConnected': res['isConnected'] as bool? ?? false,
        };
      }
      return {'isGranted': false, 'isConnected': false};
    } catch (_) {
      return {'isGranted': false, 'isConnected': false};
    }
  }

  /// Syncs and clears any pending bank notifications that arrived while the application was closed/killed.
  Future<int> syncPendingNotificationCache({Map<String, String>? manualCards}) async {
    if (kIsWeb) return 0;
    try {
      final prefs = await SharedPreferences.getInstance();
      final cacheJson = prefs.getString('pending_notification_cache');
      if (cacheJson == null || cacheJson.isEmpty || cacheJson == '[]') return 0;

      final List<dynamic> rawList = jsonDecode(cacheJson);
      if (rawList.isEmpty) return 0;

      int syncedCount = 0;
      for (final item in rawList) {
        if (item is Map) {
          final title = item['title'] as String? ?? '';
          final text = item['text'] as String? ?? '';
          final timestampMs = item['timestamp'] as int? ?? DateTime.now().millisecondsSinceEpoch;
          final date = DateTime.fromMillisecondsSinceEpoch(timestampMs);

          final fullBody = '$title $text'.trim();
          final expense = _parseSms(fullBody, date, '$timestampMs', title.isNotEmpty ? title : 'Bank', manualCards: manualCards);

          if (expense != null) {
            await _repository.addExpense(expense);
            syncedCount++;
          }
        }
      }

      // Clear the pending cache queue after sync completes
      await prefs.setString('pending_notification_cache', '[]');
      debugPrint('--- Synced and cleared $syncedCount pending background notifications from cache ---');
      return syncedCount;
    } catch (e) {
      debugPrint('Error syncing pending notification cache: $e');
      return 0;
    }
  }

  /// Starts listening for incoming SMS messages.
  void startListening() {
    // Disabled for Play Store compliance (SMS permissions removed)
    return;
  }

  /// Requests SMS permissions, fetches matching banking messages, and saves them to repository.
  Future<void> readAndPrintSms({int? targetMonth, int? targetYear}) async {
    // Disabled for Play Store compliance (SMS permissions removed)
    debugPrint('--- SMS Sync is disabled for Play Store compliance ---');
    return;
  }

  /// Parses a single SMS / Notification message and returns an Expense object if it's a valid transaction.
  Expense? _parseSms(String rawBody, DateTime date, String messageId, String senderName, {Map<String, String>? manualCards}) {
    // Only accept notification titles containing '-' and ending with 'S' (e.g., BZ-KGBANK-S, VM-HDFCBK-S)
    if (!isOfficialBankSenderTitle(senderName)) {
      return null;
    }

    final body = rawBody.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
    final bodyLower = body.toLowerCase();
    final fullLower = '$senderName $body'.toLowerCase();

    // 1. Filter out post-debit/credit balance update notifications ("Bal stands" / "Bal after txn" / "avail bal")
    if (bodyLower.contains('bal stands') || 
        bodyLower.contains('bal standsrs') || 
        bodyLower.contains('balance stands') || 
        bodyLower.contains('bal stands rs') ||
        bodyLower.contains('bal stands.') ||
        bodyLower.contains('bal after txn') ||
        bodyLower.contains('bal after transaction') ||
        bodyLower.contains('balance after txn') ||
        bodyLower.contains('balance after transaction') ||
        bodyLower.contains('avail bal') ||
        bodyLower.contains('available bal') ||
        bodyLower.contains('available balance') ||
        bodyLower.contains('after debit of') ||
        bodyLower.contains('after credit of')) {
      return null;
    }

    // 2. Filter out promotional ads, loan offers, marketing & reward messages
    if (isPromotionalOrAdText(fullLower)) {
      return null;
    }
    
    // 1. Determine Type
    String type = 'spent';
    double? epfBalance;
    
    final creditIdx = bodyLower.indexOf('credited');
    final creditShortIdx = bodyLower.indexOf('credit');
    final receivedIdx = bodyLower.indexOf('received');
    final paidYouIdx = bodyLower.indexOf('paid you');
    final refundIdx = bodyLower.indexOf('refund');
    final addedIdx = bodyLower.indexOf('added');

    final debitIdx = bodyLower.indexOf('debited');
    final debitShortIdx = bodyLower.indexOf('debit');
    final spentIdx = bodyLower.indexOf('spent');
    final sentIdx = bodyLower.indexOf('sent');
    final paidIdx = bodyLower.indexOf('paid');
    final withdrawnIdx = bodyLower.indexOf('withdrawn');

    final creditList = [creditIdx, creditShortIdx, receivedIdx, paidYouIdx, refundIdx, addedIdx].where((i) => i != -1).toList();
    final debitList = [debitIdx, debitShortIdx, spentIdx, sentIdx, paidIdx, withdrawnIdx].where((i) => i != -1).toList();

    final earliestCredit = creditList.isEmpty ? -1 : creditList.reduce((min, i) => i < min ? i : min);
    final earliestDebit = debitList.isEmpty ? -1 : debitList.reduce((min, i) => i < min ? i : min);

    if (senderName.toUpperCase().contains('EPF') || bodyLower.contains('passbook balance') || bodyLower.contains('contribution of')) {
      type = 'credited';
    } else if (paidYouIdx != -1) {
      type = 'credited';
    } else if (earliestCredit != -1 && (earliestDebit == -1 || earliestCredit < earliestDebit)) {
      type = 'credited';
    } else if (earliestDebit != -1) {
      type = (bodyLower.contains('debited') || bodyLower.contains('debit')) ? 'debited' : 'spent';
    } else if (bodyLower.contains('used') || bodyLower.contains('withdrawn') || bodyLower.contains('sent') || bodyLower.contains('paid') || bodyLower.contains('purchase')) {
      type = 'spent';
    } else {
      return null; // Not a transaction message we care about
    }

    // 2. Extract Amount
    double amount = 0.0;
    if (senderName.toUpperCase().contains('EPF') || bodyLower.contains('passbook balance') || bodyLower.contains('contribution of')) {
      final contribMatch = RegExp(r'contribution of\s*(?:Rs\.?|INR|₹)\s*([\d,]+(?:\.\d+)?)', caseSensitive: false).firstMatch(body);
      if (contribMatch != null) {
        amount = double.tryParse(contribMatch.group(1)!.replaceAll(',', '')) ?? 0.0;
      }
      final balMatch = RegExp(r'passbook balance.*?(?:Rs\.?|INR|₹)\s*([\d,]+(?:\.\d+)?)', caseSensitive: false).firstMatch(body);
      if (balMatch != null) {
        epfBalance = double.tryParse(balMatch.group(1)!.replaceAll(',', ''));
      }
    } else {
      final amountMatch = RegExp(r'(?:Rs\.?|INR|₹)\s*([\d,]+(?:\.\d+)?)', caseSensitive: false).firstMatch(body);
      if (amountMatch == null) return null;
      
      final amountStr = amountMatch.group(1)!.replaceAll(',', '');
      amount = double.tryParse(amountStr) ?? 0.0;
    }
    
    if (amount == 0.0) return null;

    // 3. Extract Merchant/Info
    String merchant = 'Transaction';
    if (senderName.toUpperCase().contains('EPF') || bodyLower.contains('passbook balance') || bodyLower.contains('contribution of')) {
      merchant = 'EPF Contribution';
    } else {
      final paidYouMatch = RegExp(r'([a-zA-Z0-9\s._]+)\s+paid\s+you', caseSensitive: false).firstMatch(body);
      final vpaMatch = RegExp(r'from\s+(?:VPA\s+)?([a-zA-Z0-9.\-_@]+)', caseSensitive: false).firstMatch(body);
      final merchantMatch = RegExp(r'(?:at|to|info)\s*(.*?)(?:\s*on|\s*using|\s*at|\s*ref|\s*from|$)', caseSensitive: false).firstMatch(body);

      if (paidYouMatch != null && paidYouMatch.group(1)!.trim().isNotEmpty) {
        merchant = paidYouMatch.group(1)!.trim();
      } else if (vpaMatch != null && vpaMatch.group(1)!.trim().isNotEmpty && vpaMatch.group(1)!.trim().toLowerCase() != 'a/c' && vpaMatch.group(1)!.trim().length > 2) {
        merchant = vpaMatch.group(1)!.trim();
      } else if (merchantMatch != null && merchantMatch.group(1)!.trim().isNotEmpty && merchantMatch.group(1)!.trim().length > 2) {
        merchant = merchantMatch.group(1)!.trim();
      } else {
        // Fallback for transfer messages like "debited from a/c no. XXXXX"
        final debitedFromMatch = RegExp(r'debited from\s+(.*?)(?:\s*\(|\s*on|\s*using|\s*ref|-|$)', caseSensitive: false).firstMatch(body);
        if (debitedFromMatch != null && debitedFromMatch.group(1)!.trim().isNotEmpty && debitedFromMatch.group(1)!.trim().length > 2) {
          merchant = debitedFromMatch.group(1)!.trim();
        }
      }

      // If merchant resolved to a generic or single-letter name (e.g. 'a', 'a/c', 'from'), extract UPI Ref No
      final merchantLower = merchant.toLowerCase().trim();
      if (merchantLower.isEmpty || 
          merchantLower == 'a' || 
          merchantLower == 'a/c' || 
          merchantLower.startsWith('a/c') ||
          merchantLower.startsWith('from a/c') || 
          merchantLower == 'from' || 
          merchantLower == 'transaction' || 
          merchantLower == 'bank alert' ||
          merchantLower.length <= 2) {
        final upiRefMatch = RegExp(r'(?:UPI\s*Ref\s*(?:no\.?)?|Ref\s*(?:no\.?)?|Txn\s*ID|Reference\s*No\.?)\s*:?\s*(\d{6,14})', caseSensitive: false).firstMatch(body);
        if (upiRefMatch != null) {
          merchant = 'UPI Ref: ${upiRefMatch.group(1)}';
        } else {
          merchant = 'Transaction';
        }
      }

      // Append (UPI) if applicable and not already present
      if (bodyLower.contains('upi') && !merchant.toLowerCase().contains('upi')) {
        merchant = '$merchant (UPI)';
      }

      if (merchant.length > 45) merchant = merchant.substring(0, 45); // Truncate long descriptions
    }

    // 4. Extract Bank/Sender
    String sender = senderName.trim();
    if (senderName.toUpperCase().contains('EPF') || bodyLower.contains('passbook balance') || bodyLower.contains('contribution of')) {
      sender = 'EPFOHO-S';
    } else {
      // Check manual cards first
      String? matchedCardName;
      if (manualCards != null) {
        for (final entry in manualCards.entries) {
          if (bodyLower.contains(entry.key.toLowerCase()) || 
              bodyLower.contains(entry.value.toLowerCase()) ||
              sender.toLowerCase().contains(entry.key.toLowerCase()) ||
              sender.toLowerCase().contains(entry.value.toLowerCase())) {
            matchedCardName = entry.key;
            break;
          }
        }
      }

      if (matchedCardName != null) {
        sender = matchedCardName;
      } else {
        sender = normalizeBankName(senderName, body: body);
      }
    }

    // 5. Reference Number for ID
    final refNoMatch = RegExp(r'(?:Ref\s*No\.?|Txn\s*ID|Reference\s*No\.?|Msg\s*Id|UPI\s*(?:Ref\s*no\.?)?|UPI)\s*(\d+)', caseSensitive: false).firstMatch(body);
    final refNo = refNoMatch?.group(1) ?? 'notif_$messageId';

    // 6. Transaction Date
    DateTime trxnDate = date;
    
    if (sender == 'EPFOHO-S') {
      final monthMatch = RegExp(r'(Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)-(\d{2})', caseSensitive: false).firstMatch(body);
      if (monthMatch != null) {
        final monthStr = monthMatch.group(1)!.toLowerCase();
        final year = 2000 + int.parse(monthMatch.group(2)!);
        final months = {'jan': 1, 'feb': 2, 'mar': 3, 'apr': 4, 'may': 5, 'jun': 6, 'jul': 7, 'aug': 8, 'sep': 9, 'oct': 10, 'nov': 11, 'dec': 12};
        if (months.containsKey(monthStr)) {
          trxnDate = DateTime(year, months[monthStr]!, 1);
        }
      }
    } else {
      final dateRegExps = [
        RegExp(r'(\d{4}-\d{2}-\d{2})'),
        RegExp(r'(\d{2}-\d{2}-\d{4})'),
        RegExp(r'(\d{2}/\d{2}/\d{2})'),
        RegExp(r'(\d{2}-\d{2}-\d{2})'),
        RegExp(r'(\d{2} \w{3} \d{2})'),
      ];

      for (var regExp in dateRegExps) {
        final dateMatch = regExp.firstMatch(body);
        if (dateMatch != null) {
          try {
            final dateStr = dateMatch.group(1)!;
            if (dateStr.length == 10 && dateStr.startsWith('20')) {
              trxnDate = DateTime.parse(dateStr);
            } else if (dateStr.contains('/')) {
              trxnDate = DateFormat('dd/MM/yy').parse(dateStr);
            } else if (dateStr.length == 8) {
              trxnDate = DateFormat('dd-MM-yy').parse(dateStr);
            } else if (dateStr.length == 10) {
              trxnDate = DateFormat('dd-MM-yyyy').parse(dateStr);
            } else {
              trxnDate = DateFormat('dd MMM yy').parse(dateStr);
            }
            
            if (trxnDate.year < 2000) {
              trxnDate = DateTime(trxnDate.year + 2000, trxnDate.month, trxnDate.day);
            }
            break;
          } catch (_) {}
        }
      }
    }

    final uniqueId = '${sender}_${type}_${refNo}';

    return Expense(
      id: uniqueId,
      name: merchant,
      amount: amount,
      date: trxnDate,
      bank: sender,
      category: 'Shopping',
      type: type,
      balance: epfBalance,
    );
  }

  /// Scans all inbox SMS, classifies banking messages into groups by type.
  Future<List<BankSmsGroup>> readAllBankSmsGrouped() async {
    // Disabled for Play Store compliance (SMS permissions removed)
    return [];
  }
}

/// Dynamically extracts clean bank card labels from raw SMS sender titles or notification headers
/// without any hardcoded bank lists or default fallbacks to a specific bank.
String normalizeBankName(String rawBank, {String? body}) {
  final cleanRaw = rawBank.trim();
  if (cleanRaw.isEmpty) {
    if (body != null && body.isNotEmpty) {
      final bodyBankMatch = RegExp(r'(?:from|to|at|on|in|using)\s+([A-Za-z0-9\s]+(?:Bank|Card|A/C|Acct))', caseSensitive: false).firstMatch(body);
      if (bodyBankMatch != null) {
        final extracted = bodyBankMatch.group(1)!.trim().toUpperCase();
        if (extracted.isNotEmpty && extracted.length < 25) {
          return (extracted.endsWith('-S') || extracted.endsWith('-T')) ? extracted : '$extracted-S';
        }
      }
    }
    return 'BANK';
  }

  // 1. Check TRAI header format: 2-letter operator prefix followed by hyphen (e.g. AD-KGBANK-S -> KGBANK-S, JX-HDFCBK-T -> HDFCBK-T)
  final parts = cleanRaw.split('-');
  if (parts.length >= 2 && parts[0].length == 2 && RegExp(r'^[A-Za-z]{2}$').hasMatch(parts[0])) {
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

/// Checks if a string represents a valid clean bank card name (e.g., KGBANK-S, HDFCBK-T, SBI-S).
bool isValidBankCardName(String name) {
  final upper = name.trim().toUpperCase();
  if (upper.isEmpty) return false;

  if (upper.contains('PAID YOU') ||
      upper.contains('PAID') ||
      upper.contains('SENT YOU') ||
      upper.contains('SPENT') ||
      upper.contains('DEBITED') ||
      upper.contains('CREDITED') ||
      upper.contains('MESSAGES') ||
      upper.contains('NOTIFICATION') ||
      upper.contains('SYSTEM') ||
      upper == 'BANK' ||
      upper.length > 35) {
    return false;
  }
  return true;
}

/// Checks if a message text is a promotional ad, loan offer, or marketing spam.
bool isPromotionalOrAdText(String text) {
  final lower = text.toLowerCase();
  final promoKeywords = [
    'loan',
    'pre-approved',
    'pre approved',
    'apply now',
    'avail',
    'offer',
    'offers',
    'congratulations',
    'congrats',
    'reward',
    'rewards',
    'cashback of up to',
    'win up to',
    'earn up to',
    't&c apply',
    't&c',
    'check emi options',
    'zero documentation',
    'zero stamp duty',
    'lowest rates',
    'get cash',
    'badhti',
    'mutual fund',
    'investment',
    'discount',
    'promo',
    'promotional',
    'limited period',
    'claim now',
    'click here',
    'bit.ly',
    'tinyurl',
    'link:',
    'eligible for',
  ];

  for (final kw in promoKeywords) {
    if (lower.contains(kw)) return true;
  }
  return false;
}

/// Checks if a notification title matches a valid bank/payment card sender header.
bool isOfficialBankSenderTitle(String title) {
  final clean = title.trim();
  if (clean.isEmpty) return false;

  final upper = clean.toUpperCase();
  if (upper.contains('SYSTEM') ||
      upper.contains('MESSAGES') ||
      upper.contains('NOTIFICATION') ||
      upper.length > 35) {
    return false;
  }
  return true;
}
