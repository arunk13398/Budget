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
  /// True if direct SMS reading is supported in the current flavor.
  /// Google Play Store variant disables SMS permissions to comply with Play Store policies.
  /// GitHub variant has full SMS permissions enabled.
  static bool get isSmsSupported => appFlavor != 'playstore';

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

  /// Checks if SMS read permission is granted.
  Future<bool> isSmsPermissionGranted() async {
    if (kIsWeb || !isSmsSupported) return false;
    try {
      return await Permission.sms.isGranted;
    } catch (_) {
      return false;
    }
  }

  /// Requests runtime SMS permission.
  Future<bool> requestSmsPermission() async {
    if (kIsWeb || !isSmsSupported) return false;
    try {
      final status = await Permission.sms.request();
      return status.isGranted;
    } catch (_) {
      return false;
    }
  }

  /// Starts listening for incoming SMS messages.
  void startListening({void Function(Expense expense)? onExpenseAutoSynced, Map<String, String>? manualCards}) {
    if (kIsWeb || !isSmsSupported) return;
    try {
      _readSms.read();
      _readSms.smsStream.listen((sms) async {
        try {
          final body = sms.body;
          final sender = sms.sender;
          final time = sms.timeReceived;
          if (body.isEmpty || sender.isEmpty) return;

          final msgId = '${time.millisecondsSinceEpoch}';
          final expense = _parseSms(body, time, msgId, sender, manualCards: manualCards);
          if (expense != null) {
            await _repository.addExpense(expense);
            if (onExpenseAutoSynced != null) {
              onExpenseAutoSynced(expense);
            }
          }
        } catch (e) {
          debugPrint('Error handling incoming live SMS: $e');
        }
      });
    } catch (e) {
      debugPrint('Error starting SMS stream listener: $e');
    }
  }

  /// Requests SMS permissions, fetches matching banking messages from the phone message folder,
  /// and saves them to repository with deduplication. Returns count of newly synced expenses.
  Future<int> readAndPrintSms({int? targetMonth, int? targetYear, Map<String, String>? manualCards}) async {
    if (kIsWeb || !isSmsSupported) return 0;
    try {
      var isGranted = await Permission.sms.isGranted;
      if (!isGranted) {
        final status = await Permission.sms.request();
        if (!status.isGranted) {
          debugPrint('--- SMS Permission Denied by user ---');
          return 0;
        }
      }

      // Query inbox SMS messages from the phone's message folder
      final List<SmsMessage> messages = await _query.querySms(
        kinds: [SmsQueryKind.inbox],
        sort: true,
      );

      if (messages.isEmpty) {
        debugPrint('--- No SMS messages found in phone message folder ---');
        return 0;
      }

      debugPrint('--- Found ${messages.length} SMS messages in inbox to scan ---');

      // Load manual cards if not provided
      Map<String, String>? effectiveCards = manualCards;
      if (effectiveCards == null) {
        final prefs = await SharedPreferences.getInstance();
        final rawCards = prefs.getString('manual_cards');
        if (rawCards != null && rawCards.isNotEmpty) {
          try {
            effectiveCards = Map<String, String>.from(jsonDecode(rawCards));
          } catch (_) {}
        }
      }

      final List<Expense> extractedExpenses = [];
      for (final msg in messages) {
        final body = msg.body?.trim() ?? '';
        final address = msg.address?.trim() ?? '';
        final date = msg.date ?? DateTime.now();
        final id = '${msg.id ?? date.millisecondsSinceEpoch}';

        if (body.isEmpty || address.isEmpty) continue;

        final expense = _parseSms(
          body,
          date,
          id,
          address,
          manualCards: effectiveCards,
        );

        if (expense != null) {
          extractedExpenses.add(expense);
        }
      }

      if (extractedExpenses.isEmpty) {
        debugPrint('--- No valid bank transactions found in SMS inbox ---');
        return 0;
      }

      debugPrint('--- Extracted ${extractedExpenses.length} bank transaction expenses from SMS inbox ---');

      // Get initial count of expenses in repository before adding
      final initialData = await _repository.getExpenses().first;
      final initialIds = initialData.expenses.map((e) => e.id).toSet();

      // Add to repository (repository handles de-duplication with existing expenses and notifications)
      await _repository.addExpenses(extractedExpenses);

      // Verify newly added count
      final updatedData = await _repository.getExpenses().first;
      final newCount = updatedData.expenses.where((e) => !initialIds.contains(e.id)).length;

      debugPrint('--- Successfully synced $newCount new transactions from phone messages folder ---');
      return newCount > 0 ? newCount : extractedExpenses.length;
    } catch (e, stack) {
      debugPrint('Error reading SMS from phone message folder: $e\n$stack');
      return 0;
    }
  }

  /// Parses a single SMS / Notification message and returns an Expense object if it's a valid transaction.
  Expense? _parseSms(String rawBody, DateTime date, String messageId, String senderName, {Map<String, String>? manualCards}) {
    // Verify sender title against official bank headers or user configured manual cards
    if (!isOfficialBankSenderTitle(senderName, manualCards: manualCards)) {
      return null;
    }

    final body = rawBody.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
    final bodyLower = body.toLowerCase();
    final fullLower = '$senderName $body'.toLowerCase();

    // 0. Filter out declined, failed, unsuccessful, or rejected transactions
    if (isDeclinedOrFailedText(fullLower) || isDeclinedOrFailedText(bodyLower)) {
      return null;
    }

    // Filter out credit card statements, bill due, total due / min due notices
    if (isStatementOrBillText(fullLower) || isStatementOrBillText(bodyLower)) {
      return null;
    }

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
    
    // Check for mandatory transaction action keywords in body:
    // debited, credited, spend, spent, debit, credit, withdrawn, etc.
    if (!containsTransactionKeyword(body)) {
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
    final spendIdx = bodyLower.indexOf('spend');
    final sentIdx = bodyLower.indexOf('sent');
    final paidIdx = bodyLower.indexOf('paid');
    final withdrawnIdx = bodyLower.indexOf('withdrawn');

    final creditList = [creditIdx, creditShortIdx, receivedIdx, paidYouIdx, refundIdx, addedIdx].where((i) => i != -1).toList();
    final debitList = [debitIdx, debitShortIdx, spentIdx, spendIdx, sentIdx, paidIdx, withdrawnIdx].where((i) => i != -1).toList();

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
    } else if (bodyLower.contains('withdrawn') || bodyLower.contains('paid to') || bodyLower.contains('purchase')) {
      type = 'spent';
    } else {
      return null; // Not a valid transaction message
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
      final merchantMatch = RegExp(
        r'\b(?:at|to|info)\b\s*(.*?)(?:\s+on\b|\s+using\b|\s+with\b|\s+via\b|\s+thru\b|\s+through\b|\s+for\s*(?:rs|inr|₹)|\s+(?:credit\s+|debit\s+)?card\s*ending|\s+ending\s+(?:with\s+|in\s+)?\d+|\s+a/c|\s+account|\s+ref\b|\s+from\b|\.|$|[,\r\n])',
        caseSensitive: false,
      ).firstMatch(body);

      if (paidYouMatch != null && paidYouMatch.group(1)!.trim().isNotEmpty) {
        merchant = paidYouMatch.group(1)!.trim();
      } else if (vpaMatch != null && vpaMatch.group(1)!.trim().isNotEmpty && vpaMatch.group(1)!.trim().toLowerCase() != 'a/c' && vpaMatch.group(1)!.trim().length > 2) {
        merchant = vpaMatch.group(1)!.trim();
      } else if (merchantMatch != null && merchantMatch.group(1)!.trim().isNotEmpty && merchantMatch.group(1)!.trim().length > 2) {
        merchant = merchantMatch.group(1)!.trim();
      } else {
        // Fallback for transfer messages like "debited from a/c no. XXXXX"
        final debitedFromMatch = RegExp(r'debited from\s+(.*?)(?:\s*\(|\s+on\b|\s+using\b|\s+with\b|\s+ref\b|-|$)', caseSensitive: false).firstMatch(body);
        if (debitedFromMatch != null && debitedFromMatch.group(1)!.trim().isNotEmpty && debitedFromMatch.group(1)!.trim().length > 2) {
          merchant = debitedFromMatch.group(1)!.trim();
        }
      }

      // Clean trailing card ending fragments and noise
      merchant = cleanMerchantName(merchant);

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
          merchantLower == 'card' ||
          merchantLower == 'credit card' ||
          merchantLower == 'debit card' ||
          merchantLower.length <= 2 ||
          isCardEndingOrDeclinedMerchant(merchant)) {
        final upiRefMatch = RegExp(r'(?:UPI\s*Ref\s*(?:no\.?)?|Ref\s*(?:no\.?)?|Txn\s*ID|Reference\s*No\.?)\s*:?\s*(\d{6,14})', caseSensitive: false).firstMatch(body);
        if (upiRefMatch != null) {
          merchant = 'UPI Ref: ${upiRefMatch.group(1)}';
        } else {
          // Reject if it is a card ending noise or declined fragment with no UPI ref
          return null;
        }
      }

      // Append (UPI) if applicable and not already present
      if (bodyLower.contains('upi') && !merchant.toLowerCase().contains('upi')) {
        merchant = '$merchant (UPI)';
      }

      if (merchant.length > 45) merchant = merchant.substring(0, 45); // Truncate long descriptions
    }

    // Reject if merchant after all processing is still a declined, card ending, or statement/due item
    if (isCardEndingOrDeclinedMerchant(merchant) || isDeclinedOrFailedText(merchant) || isStatementOrBillText(merchant)) {
      return null;
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

    // Verify sender is a valid bank card name
    if (!isValidBankCardName(sender, manualCards: manualCards)) {
      return null;
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

    final uniqueId = '${sender}_${type}_$refNo';

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

  /// Returns bank card groups constructed from the saved expenses in repository.
  Future<List<BankSmsGroup>> readAllBankSmsGrouped({Map<String, String>? manualCards}) async {
    try {
      final expenseData = await _repository.getExpenses().first;
      final allExpenses = expenseData.expenses;

      final Map<String, List<BankSmsEntry>> groupedByBank = {};

      for (final e in allExpenses) {
        final bankName = normalizeBankName(e.bank, body: e.name);
        if (!isValidBankCardName(bankName, manualCards: manualCards)) continue;

        // Ensure the transaction is an actual credited, debited, or spent transaction
        if (e.type != 'spent' && e.type != 'debited' && e.type != 'credited') continue;

        // Skip declined, failed, card-ending, or statement noise entries
        if (isCardEndingOrDeclinedMerchant(e.name) ||
            isDeclinedOrFailedText(e.name) ||
            isStatementOrBillText(e.name)) continue;

        if (!groupedByBank.containsKey(bankName)) {
          groupedByBank[bankName] = [];
        }
        groupedByBank[bankName]!.add(
          BankSmsEntry(
            sender: bankName,
            body: '${e.name} - ₹${e.amount}',
            amount: e.amount,
            date: e.date,
            type: e.type == 'credited' ? 'bank_credited' : 'credit_card_spent',
          ),
        );
      }

      return groupedByBank.entries
          .where((entry) => entry.value.isNotEmpty || (manualCards != null && manualCards.containsKey(entry.key)))
          .map((entry) {
        return BankSmsGroup(
          type: entry.key,
          label: entry.key,
          emoji: '💳',
          entries: entry.value,
        );
      }).toList();
    } catch (e) {
      debugPrint('Error in readAllBankSmsGrouped: $e');
      return [];
    }
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

  final upper = cleanRaw.toUpperCase();

  // 1. If it starts with digits or phone number, return as is (invalid)
  if (RegExp(r'^\+?[0-9]').hasMatch(upper)) {
    return upper;
  }

  // 2. Check TRAI header format: 2-letter operator prefix followed by hyphen (e.g. AD-KGBANK-S -> KGBANK-S, JX-HDFCBK-T -> HDFCBK-T, BZ-KGBANK -> KGBANK-S)
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

  // 3. Already has hyphen and ends with -S or -T
  if (upper.contains('-') && (upper.endsWith('-S') || upper.endsWith('-T'))) {
    return upper;
  }

  // 4. If it contains a hyphen, check if we should append -S
  if (upper.contains('-')) {
    return '$upper-S';
  }

  return upper;
}

/// Non-bank / promotional / telecom / government / retail keywords to blacklist from bank cards.
const List<String> kNonBankBlacklist = [
  'AIRTEL',
  'JIO',
  'VODAFONE',
  'IDEA',
  'BSNL',
  'ACT',
  'FROMBM',
  'SWIGGY',
  'ZOMATO',
  'AMAZON',
  'FLIPKART',
  'MYNTRA',
  'UBER',
  'OLA',
  'DOMINOS',
  'MEESHO',
  'NYKAA',
  'SYSTEM',
  'MESSAGES',
  'NOTIFICATION',
  'VAAHAN',
  'SARATHI',
  'PARIVAHAN',
  'ECHALLAN',
  'WLPARK',
  'WONDERLA',
  'MYGMSG',
  'MYG',
  'UIICHO',
  'UIIC',
  'PHONPE',
  'PHONEPE',
  'GPAY',
  'MOBIKW',
  'FREECH',
  'PAYTM',
  'IRCTC',
  'MAKEMY',
  'GOIBIB',
  'YATRA',
  'REDBUS',
  'BOOKMY',
  'PVR',
  'INOX',
  'CROMA',
  'VIJAYS',
  'RELIAN',
  'DMART',
  'DELHIV',
  'BLUEDA',
  'DTDC',
  'EKART',
  'SHADOW',
  'XPRESS',
  'GOOGLE',
  'TRUECL',
  'WHATSAPP',
  'TELEGRAM',
];

/// Checks if an entity name contains recognizable bank, card, or payment institution patterns.
bool isKnownBankOrCardEntity(String entity) {
  final upper = entity.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  if (upper.isEmpty) return false;

  // Direct bank & card keywords
  if (upper.contains('BANK') ||
      upper.contains('BK') ||
      upper.contains('BNK') ||
      upper.contains('CARD') ||
      upper.contains('CRD') ||
      upper.contains('PAYZAP') ||
      upper.contains('CREDIN') ||
      upper.contains('EPFOHO') ||
      upper.contains('EPFO') ||
      upper.contains('UPI')) {
    return true;
  }

  // Known major Indian financial institutions and abbreviations
  final bankPrefixes = [
    'SBI',
    'HDFC',
    'ICICI',
    'AXIS',
    'KGB',
    'KGBANK',
    'KVB',
    'BOB',
    'PNB',
    'KOTAK',
    'CANARA',
    'CANBK',
    'FEDBNK',
    'FEDERAL',
    'INDUS',
    'UNIONB',
    'UNION',
    'IDFC',
    'YESB',
    'RBL',
    'AUBANK',
    'AUSFB',
    'IPPB',
    'IOB',
    'UCO',
    'BOI',
    'CENTBK',
    'CITI',
    'SCB',
    'HSBC',
    'BANDHAN',
    'EQUITAS',
    'UJJIVAN',
    'CUB',
    'TMB',
    'SIB',
    'CSB',
    'DBS',
    'GRAMIN',
    'COOP',
  ];

  for (final b in bankPrefixes) {
    if (upper.contains(b)) {
      return true;
    }
  }

  return false;
}

/// Checks if a string represents a valid clean bank card name.
/// Rules:
/// 1. Must NOT start with digits or '+' (e.g., rejects shortcodes like 650001-P-S).
/// 2. Must contain a hyphen '-' and end with '-S' or '-T'.
/// 3. Must NOT contain purely numeric segments between hyphens.
/// 4. Must NOT match known non-bank/telecom/promotional senders.
/// 5. Must match a recognized bank, card, or financial entity.
bool isValidBankCardName(String name, {Map<String, String>? manualCards}) {
  final upper = name.trim().toUpperCase();
  if (upper.isEmpty) return false;

  // If user explicitly configured this as a manual card, allow it
  if (manualCards != null) {
    for (final entry in manualCards.entries) {
      if (upper == entry.key.toUpperCase() || 
          upper == normalizeBankName(entry.key).toUpperCase()) {
        return true;
      }
    }
  }

  // Must not start with digit or plus (phone numbers or shortcodes like 650001-P-S)
  if (RegExp(r'^\+?[0-9]').hasMatch(upper)) {
    return false;
  }

  // Must contain a hyphen '-' and end with '-S' or '-T'
  if (!upper.contains('-') || (!upper.endsWith('-S') && !upper.endsWith('-T'))) {
    return false;
  }

  // Must not contain numeric segments (e.g. 650001-P-S)
  final segments = upper.split('-');
  for (final seg in segments) {
    if (RegExp(r'^\d+$').hasMatch(seg)) {
      return false;
    }
  }

  // Reject generic or action names
  if (upper == 'BANK' ||
      upper == 'BANK-S' ||
      upper == 'BANK-T' ||
      upper.startsWith('PAID') ||
      upper.startsWith('SPENT') ||
      upper.startsWith('DEBIT') ||
      upper.startsWith('CREDIT')) {
    return false;
  }

  // Blacklist non-bank / telecom / promo headers
  for (final blocked in kNonBankBlacklist) {
    if (upper.contains(blocked)) {
      return false;
    }
  }

  if (upper.length < 3 || upper.length > 25) {
    return false;
  }

  // Extract core bank identifier (strip -S, -T suffix and operator prefixes)
  var coreEntity = upper;
  if (coreEntity.endsWith('-S')) coreEntity = coreEntity.substring(0, coreEntity.length - 2);
  if (coreEntity.endsWith('-T')) coreEntity = coreEntity.substring(0, coreEntity.length - 2);
  final parts = coreEntity.split('-');
  if (parts.length >= 2 && parts.first.length == 2) {
    coreEntity = parts.sublist(1).join();
  } else {
    coreEntity = parts.join();
  }

  // Must be a recognized bank, card, or financial entity
  return isKnownBankOrCardEntity(coreEntity);
}

/// Checks if a message text contains required financial transaction action keywords:
/// debited, credited, spend, spent, debit, credit, withdrawn, refund, etc.
bool containsTransactionKeyword(String body) {
  // Reject declined, failed, or unsuccessful transactions immediately
  if (isDeclinedOrFailedText(body)) {
    return false;
  }

  // Reject bill reminders, statement notices, total due / min due alerts
  if (isStatementOrBillText(body)) {
    return false;
  }

  final lower = body.toLowerCase();

  // Reject OTP / verification codes unless there is an explicit debit/credit confirmation
  if (lower.contains('otp') ||
      lower.contains('one time password') ||
      lower.contains('verification code') ||
      lower.contains('secret code') ||
      lower.contains('login code') ||
      lower.contains('auth code')) {
    if (!lower.contains('has been debited') &&
        !lower.contains('is debited') &&
        !lower.contains('has been credited') &&
        !lower.contains('is credited')) {
      return false;
    }
  }

  // Reject bill reminders, statement notices, and credit limit updates unless there is an explicit transaction
  if (lower.contains('bill due') ||
      lower.contains('payment due') ||
      lower.contains('statement generated') ||
      lower.contains('e-statement') ||
      lower.contains('credit limit') ||
      lower.contains('minimum amount due') ||
      lower.contains('total amount due')) {
    if (!lower.contains('debited') &&
        !lower.contains('credited') &&
        !lower.contains('spent') &&
        !lower.contains('spend') &&
        !lower.contains('has been paid') &&
        !lower.contains('paid rs') &&
        !lower.contains('paid inr') &&
        !lower.contains('paid ₹')) {
      return false;
    }
  }

  // EPFO / Passbook messages
  if (lower.contains('passbook balance') || lower.contains('contribution of')) {
    return true;
  }

  // Core transaction action keywords requested by user
  final transactionKeywords = [
    'debited',
    'credited',
    'spent',
    'spend',
    'debit',
    'credit',
    'withdrawn',
    'refund',
    'refunded',
    'deposited',
    'deducted',
    'paid to',
    'paid you',
    'transferred to',
    'received rs',
    'received inr',
    'received ₹',
  ];

  for (final kw in transactionKeywords) {
    if (lower.contains(kw)) {
      // If keyword is 'credit' or 'debit', ensure it's not a card dispatch / limit promo / bill due reminder
      if (kw == 'credit' || kw == 'debit') {
        if (lower.contains('credit limit') ||
            lower.contains('bill due') ||
            lower.contains('payment due') ||
            lower.contains('apply for') ||
            lower.contains('dispatched') ||
            lower.contains('reward points') ||
            lower.contains('statement') ||
            (lower.contains('credit card') &&
                !lower.contains('debited') &&
                !lower.contains('credited') &&
                !lower.contains('spent') &&
                !lower.contains('spend'))) {
          continue;
        }
      }
      return true;
    }
  }

  return false;
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

/// Checks if a sender or notification title matches a valid bank/payment card sender header.
/// Enforces:
/// 1. Must NOT start with digits or '+' (rejects 650001-P, +91..., etc.).
/// 2. Must contain a hyphen '-' (TRAI format e.g. BZ-KGBANK-S, VK-SBIINB-T, EPFOHO-S).
/// 3. Must NOT contain purely numeric segments.
/// 4. Must NOT be in the non-bank blacklist (e.g. AIRTEL, FROMBM, SWIGGY).
bool isOfficialBankSenderTitle(String title, {Map<String, String>? manualCards}) {
  final clean = title.trim();
  if (clean.isEmpty) return false;

  // If manual cards explicitly match, allow it
  if (manualCards != null) {
    for (final entry in manualCards.entries) {
      if (clean.toLowerCase().contains(entry.key.toLowerCase()) || 
          clean.toLowerCase().contains(entry.value.toLowerCase())) {
        return true;
      }
    }
  }

  // Reject personal phone numbers or shortcodes starting with digits (e.g. 650001-P, +91...)
  if (RegExp(r'^\+?[0-9]').hasMatch(clean)) {
    return false;
  }

  // Must contain hyphen '-' (official TRAI headers or normalized card IDs have hyphen)
  if (!clean.contains('-')) {
    return false;
  }

  final upper = clean.toUpperCase();

  // Reject if any segment is purely numeric (e.g. 650001-P)
  final segments = upper.split('-');
  for (final seg in segments) {
    if (RegExp(r'^\d+$').hasMatch(seg)) {
      return false;
    }
  }

  // Reject non-bank blacklist
  for (final blocked in kNonBankBlacklist) {
    if (upper == blocked ||
        upper == '$blocked-S' ||
        upper == '$blocked-T' ||
        upper.startsWith('$blocked-') ||
        upper.contains(blocked)) {
      return false;
    }
  }

  // Extract core entity: TRAI format has 2-letter operator prefix e.g. "VM-HDFCBK-S" -> "HDFCBK"
  var coreEntity = upper;
  if (coreEntity.endsWith('-S')) coreEntity = coreEntity.substring(0, coreEntity.length - 2);
  if (coreEntity.endsWith('-T')) coreEntity = coreEntity.substring(0, coreEntity.length - 2);
  if (segments.length >= 2 && segments[0].length == 2 && RegExp(r'^[A-Z]{2}$').hasMatch(segments[0])) {
    coreEntity = segments.sublist(1).join();
  } else {
    coreEntity = segments.join();
  }

  if (!isKnownBankOrCardEntity(coreEntity)) {
    return false;
  }

  // Check TRAI format or -S / -T suffix
  // TRAI format: 2-letter operator + '-' + entity (e.g. BZ-KGBANK, VM-HDFCBK-S, VK-SBIINB-T)
  // or normalized card ID ending with -S or -T
  if (upper.endsWith('-S') || upper.endsWith('-T')) {
    return true;
  }

  if (segments.length >= 2 && segments[0].length == 2 && RegExp(r'^[A-Z]{2}$').hasMatch(segments[0])) {
    return true;
  }

  return false;
}

/// Checks if a message text or merchant description indicates a declined, failed, or unsuccessful transaction.
bool isDeclinedOrFailedText(String text) {
  final lower = text.toLowerCase();

  final failureKeywords = [
    'declined',
    'decline',
    'failed',
    'failure',
    'unsuccessful',
    'not processed',
    'could not process',
    'could not be processed',
    'unable to process',
    'incorrect pin',
    'invalid pin',
    'wrong pin',
    'insufficient fund',
    'insufficient balance',
    'limit exceeded',
    'exceeded limit',
    'exceeds limit',
    'not debited',
    'was not debited',
    'has not been debited',
    'is not debited',
    'cannot be debited',
    'cancelled',
    'canceled',
    'rejected',
    'txn rejected',
    'transaction rejected',
    'blocked',
    'card blocked',
    'payment failed',
    'mandate failed',
    'auto-debit failed',
    'autodebit failed',
  ];

  for (final kw in failureKeywords) {
    if (lower.contains(kw)) {
      return true;
    }
  }

  if (RegExp(r'\b(?:fail|failed|failure|failures|unsuccessful)\b', caseSensitive: false).hasMatch(lower)) {
    return true;
  }

  return false;
}

/// Checks if a merchant string contains unwanted card ending noise or decline fragments.
bool isCardEndingOrDeclinedMerchant(String name) {
  final clean = name.trim();
  if (clean.isEmpty) return true;
  final lower = clean.toLowerCase();

  if (isDeclinedOrFailedText(lower)) return true;
  if (isStatementOrBillText(lower)) return true;

  final badPatterns = [
    'card ending',
    'card ending with',
    'credit card ending',
    'debit card ending',
    'ending with',
    'with your credit card',
    'with your debit card',
    'with your card',
    'with card ending',
    'with credit card',
    'with debit card',
    'a/c ending',
    'account ending',
  ];

  for (final pat in badPatterns) {
    if (lower.contains(pat)) {
      return true;
    }
  }

  if (RegExp(r'\bending\s+(?:with\s+|in\s+)?\d{2,6}\b', caseSensitive: false).hasMatch(lower)) {
    return true;
  }
  if (RegExp(r'\b(?:credit\s+|debit\s+)?card\s*ending\b', caseSensitive: false).hasMatch(lower)) {
    return true;
  }

  return false;
}

/// Sanitizes a merchant name by removing trailing card clauses, payment noise, or punctuation.
String cleanMerchantName(String rawMerchant) {
  var clean = rawMerchant.trim();
  if (clean.isEmpty) return clean;

  clean = clean.replaceAll(
    RegExp(
      r'(?:\s+(?:with|using|on|via)\s+(?:your\s+)?(?:credit\s+|debit\s+)?card(?:\s+ending(?:\s+(?:with|in)?\s*\d+)?)?.*)$',
      caseSensitive: false,
    ),
    '',
  );

  clean = clean.replaceAll(
    RegExp(
      r'(?:\s+(?:credit\s+|debit\s+)?card\s+ending(?:\s+(?:with|in)?\s*\d+)?.*)$',
      caseSensitive: false,
    ),
    '',
  );

  clean = clean.replaceAll(
    RegExp(
      r'(?:\s+ending\s+(?:with\s+|in\s+)?\d+.*)$',
      caseSensitive: false,
    ),
    '',
  );

  clean = clean.replaceAll(
    RegExp(
      r'(?:\s+for\s+(?:rs\.?|inr|₹).*)$',
      caseSensitive: false,
    ),
    '',
  );

  clean = clean.replaceAll(
    RegExp(
      r'(?:\s+due\s+to\s+.*)$',
      caseSensitive: false,
    ),
    '',
  );

  clean = clean.replaceAll(RegExp(r'[\s.,\-_:;]+$'), '').trim();
  return clean;
}

/// Checks if a message text or merchant description is a bill reminder, statement notice, or total/min due item.
bool isStatementOrBillText(String text) {
  final lower = text.toLowerCase();

  final billKeywords = [
    'total due',
    'min due',
    'min.due',
    'min. due',
    'minimum due',
    'due amt',
    'due amount',
    'total amt due',
    'total amount due',
    'minimum amt due',
    'minimum amount due',
    'statement generated',
    'card statement',
    'e-statement',
    'estatement',
    'bill due',
    'payment due',
    'pay by',
    'due date',
    'due on',
    'amount due',
    'amt due',
    'due: rs',
    'due: inr',
    'due: ₹',
    'due:rs',
    'due amt: rs',
    'due amt: inr',
    'due amt: ₹',
    'min due amt',
    'min.due amt',
    'ement:',
  ];

  for (final kw in billKeywords) {
    if (lower.contains(kw)) {
      return true;
    }
  }

  if (RegExp(r'\bdue\s*:\s*(?:rs\.?|inr|₹)?\s*[\d,]+', caseSensitive: false).hasMatch(lower)) {
    return true;
  }
  if (RegExp(r'\b(?:total|min(?:imum)?)\s*(?:amt|amount)?\s*due\b', caseSensitive: false).hasMatch(lower)) {
    return true;
  }
  if (RegExp(r'\bstatement\b', caseSensitive: false).hasMatch(lower) && 
      (lower.contains('due') || lower.contains('amt') || lower.contains('min') || lower.contains('card'))) {
    return true;
  }

  return false;
}

/// Canonicalizes a merchant name for filtering and grouping, combining sequential handles
/// (e.g. "adhnan.e-2", "adhnan.e-3" -> "adhnan.e") and stripping VPA domains.
String canonicalFilterMerchantName(String name) {
  var clean = name.trim();
  if (clean.isEmpty) return clean;

  final hasUpi = clean.toLowerCase().contains('(upi)');
  var base = clean.replaceAll(RegExp(r'\s*\(?UPI\)?', caseSensitive: false), '').trim();

  // Strip VPA handles (e.g. @okaxis, @okhdfcbank, @okicici, @ok., @.)
  base = base.replaceAll(RegExp(r'@[a-zA-Z0-9._\-]*$'), '').trim();

  // Strip trailing sequential index like "-1", "-2", "-3", "-01", "_1", "_02"
  // e.g. "adhnan.e-2" -> "adhnan.e", "guna080100-1" -> "guna080100"
  base = base.replaceAll(RegExp(r'[-_]\d+$'), '').trim();

  // Strip trailing punctuation
  base = base.replaceAll(RegExp(r'[\s.,\-_:;]+$'), '').trim();

  if (base.isEmpty) return clean;

  if (hasUpi) {
    return '$base (UPI)';
  }
  return base;
}

/// Checks if an expense name matches the user's selected filter names,
/// supporting combined handles (e.g. "adhnan.e-2" matches filter "adhnan.e").
bool matchesExpenseNameFilter(String expenseName, List<String> selectedNames) {
  if (selectedNames.isEmpty) return false;
  final expUpper = expenseName.trim().toUpperCase();
  final expCanonical = canonicalFilterMerchantName(expUpper);
  final expCore = expCanonical.replaceAll(RegExp(r'\s*\(?UPI\)?', caseSensitive: false), '').trim();

  for (final sel in selectedNames) {
    final selUpper = sel.trim().toUpperCase();
    if (selUpper == expUpper || selUpper == expCanonical) return true;
    final selCore = canonicalFilterMerchantName(selUpper).replaceAll(RegExp(r'\s*\(?UPI\)?', caseSensitive: false), '').trim();
    if (selCore.isNotEmpty && selCore == expCore) return true;
  }
  return false;
}




