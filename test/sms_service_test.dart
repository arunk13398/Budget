import 'package:flutter_test/flutter_test.dart';
import 'package:widget_learning/core/services/sms_service.dart';
import 'package:widget_learning/features/expenses/domain/entities/expense.dart';
import 'package:widget_learning/features/expenses/data/repositories/expense_repository_impl.dart';
import 'package:widget_learning/features/expenses/data/datasources/expense_local_data_source.dart';
import 'package:widget_learning/features/expenses/data/datasources/settings_local_data_source.dart';
import 'package:widget_learning/features/expenses/data/models/expense_model.dart';

class MockExpenseLocalDataSource implements ExpenseLocalDataSource {
  final Map<String, ExpenseModel> storage = {};

  @override
  List<ExpenseModel> getExpenses() => storage.values.toList();

  @override
  Future<void> saveExpense(ExpenseModel expense) async {
    storage[expense.id] = expense;
  }

  @override
  Future<void> saveExpenses(List<ExpenseModel> expenses) async {
    for (final e in expenses) {
      storage[e.id] = e;
    }
  }

  @override
  Future<void> deleteExpense(String id) async {
    storage.remove(id);
  }

  @override
  bool isEmpty() => storage.isEmpty;
}

class MockSettingsLocalDataSource implements SettingsLocalDataSource {
  @override
  double getLimit({double defaultValue = 80000.0}) => 50000.0;
  @override
  Future<void> saveLimit(double limit) async {}
  @override
  String? getLegacyExpensesString(String key) => null;
  @override
  double? getLegacyLimitDouble(String key) => null;
  @override
  Future<void> removeLegacyKey(String key) async {}
}

void main() {
  group('SMS Service & Bank Header Detection Tests', () {
    test('isOfficialBankSenderTitle detects valid bank headers and rejects spam/phone numbers/shortcodes', () {
      expect(isOfficialBankSenderTitle('VM-HDFCBK'), isTrue);
      expect(isOfficialBankSenderTitle('VK-SBIINB-S'), isTrue);
      expect(isOfficialBankSenderTitle('AD-ICICIB'), isTrue);
      expect(isOfficialBankSenderTitle('EPFOHO-S'), isTrue);
      expect(isOfficialBankSenderTitle('AXISBK-S'), isTrue);
      expect(isOfficialBankSenderTitle('KGBANK-S'), isTrue);
      expect(isOfficialBankSenderTitle('CREDIN-S'), isTrue);

      // Rejects shortcodes and numbers (like 650001-P, 650025-P-S)
      expect(isOfficialBankSenderTitle('650001-P'), isFalse);
      expect(isOfficialBankSenderTitle('650001-P-S'), isFalse);
      expect(isOfficialBankSenderTitle('650025-P-S'), isFalse);

      // Rejects personal mobile phone numbers
      expect(isOfficialBankSenderTitle('+919876543210'), isFalse);
      expect(isOfficialBankSenderTitle('9876543210'), isFalse);

      // Rejects non-bank telecom and promotional senders
      expect(isOfficialBankSenderTitle('AIRTEL'), isFalse);
      expect(isOfficialBankSenderTitle('AIRTEL-S'), isFalse);
      expect(isOfficialBankSenderTitle('FROMBM'), isFalse);
      expect(isOfficialBankSenderTitle('FROMBM-S'), isFalse);
      expect(isOfficialBankSenderTitle('SWIGGY-S'), isFalse);

      // Rejects system or empty titles
      expect(isOfficialBankSenderTitle('SYSTEM'), isFalse);
      expect(isOfficialBankSenderTitle('MESSAGES'), isFalse);
      expect(isOfficialBankSenderTitle(''), isFalse);
    });

    test('isValidBankCardName strictly enforces hyphen, -S or -T suffix, and excludes invalid cards', () {
      // Valid cards
      expect(isValidBankCardName('KGBANK-S'), isTrue);
      expect(isValidBankCardName('HDFCBK-S'), isTrue);
      expect(isValidBankCardName('AXISBK-S'), isTrue);
      expect(isValidBankCardName('SBIINB-T'), isTrue);
      expect(isValidBankCardName('EPFOHO-S'), isTrue);
      expect(isValidBankCardName('CREDIN-S'), isTrue);

      // Invalid cards (from screenshot & non-bank entities)
      expect(isValidBankCardName('650001-P-S'), isFalse);
      expect(isValidBankCardName('650025-P-S'), isFalse);
      expect(isValidBankCardName('AIRTEL-S'), isFalse);
      expect(isValidBankCardName('FROMBM-S'), isFalse);
      expect(isValidBankCardName('WLPARK-S'), isFalse); // Amusement park
      expect(isValidBankCardName('VAAHAN-S'), isFalse); // Gov transport
      expect(isValidBankCardName('VAAHAN-G-S'), isFalse);
      expect(isValidBankCardName('MYGMSG-S'), isFalse); // Electronics shop
      expect(isValidBankCardName('UIICHO-S'), isFalse); // Insurance
      expect(isValidBankCardName('PHONPE-S'), isFalse); // Payment app, not a bank
      expect(isValidBankCardName('PHONPE-P-S'), isFalse);

      // Missing hyphen or wrong suffix
      expect(isValidBankCardName('HDFCBK'), isFalse);
      expect(isValidBankCardName('HDFC-X'), isFalse);
      expect(isValidBankCardName('BANK'), isFalse);
      expect(isValidBankCardName(''), isFalse);
    });

    test('containsTransactionKeyword checks for debited, credited, spend, debit, credit and excludes OTP/promos', () {
      // Valid transaction action texts
      expect(containsTransactionKeyword('Your a/c no. XX1234 is debited for Rs 500.00 on 22-Sep-26 at Swiggy'), isTrue);
      expect(containsTransactionKeyword('Rs 1500.00 credited to your A/C on 22-Sep-26 by UPI'), isTrue);
      expect(containsTransactionKeyword('You have spent Rs. 450 on your Credit Card ending 1234 at Starbucks'), isTrue);
      expect(containsTransactionKeyword('Rs 250 debit to VPA friend@upi'), isTrue);
      expect(containsTransactionKeyword('Rs 2000 credit transaction successful in your account'), isTrue);
      expect(containsTransactionKeyword('Cash withdrawn Rs. 2000 from ATM'), isTrue);
      expect(containsTransactionKeyword('EPFO passbook balance Rs 50000 updated'), isTrue);

      // Rejected non-transaction / OTP / promo messages
      expect(containsTransactionKeyword('Your OTP is 650001 for login. Do not share with anyone.'), isFalse);
      expect(containsTransactionKeyword('650025 is your secret verification code.'), isFalse);
      expect(containsTransactionKeyword('Airtel recharge of Rs 299 is successful. Enjoy 1.5GB/day data.'), isFalse);
      expect(containsTransactionKeyword('Special offer! Get 20% discount on your next purchase.'), isFalse);
      expect(containsTransactionKeyword('Your credit card bill payment of Rs 1000 is due on 25th.'), isFalse);
      expect(containsTransactionKeyword('Your credit limit has been increased to Rs 1,50,000.'), isFalse);
      expect(containsTransactionKeyword('E-statement for your HDFC Bank account is generated.'), isFalse);
      expect(containsTransactionKeyword('Your minimum amount due is Rs 450 for credit card ending 1234.'), isFalse);
    });

    test('readAllBankSmsGrouped filters out banks that have no transactions or invalid types', () async {
      final localDataSource = MockExpenseLocalDataSource();
      final settingsDataSource = MockSettingsLocalDataSource();
      final repository = ExpenseRepositoryImpl(
        expenseLocalDataSource: localDataSource,
        settingsLocalDataSource: settingsDataSource,
      );
      final smsService = SmsService(repository);

      // Add one valid transaction and one non-bank / non-transaction expense
      final validExpense = Expense(
        id: 'HDFCBK-S_spent_1',
        name: 'Swiggy',
        amount: 250.0,
        date: DateTime.now(),
        bank: 'HDFCBK-S',
        category: 'Food',
        type: 'spent',
      );
      final invalidTypeExpense = Expense(
        id: 'AIRTEL-S_info_1',
        name: 'Bill Info',
        amount: 0.0,
        date: DateTime.now(),
        bank: 'AIRTEL-S',
        category: 'Bills',
        type: 'info',
      );

      await repository.addExpenses([validExpense, invalidTypeExpense]);

      final groups = await smsService.readAllBankSmsGrouped();
      expect(groups.length, 1);
      expect(groups.first.label, 'HDFCBK-S');
      expect(groups.first.entries.length, 1);
    });

    test('normalizeBankName normalizes TRAI headers to card format', () {
      expect(normalizeBankName('VM-HDFCBK'), 'HDFCBK-S');
      expect(normalizeBankName('AD-KGBANK-S'), 'KGBANK-S');
      expect(normalizeBankName('JX-SBIINB-T'), 'SBIINB-T');
    });

    test('isPromotionalOrAdText filters out loan and credit spam', () {
      expect(isPromotionalOrAdText('Pre-approved personal loan of Rs 5,00,000 apply now'), isTrue);
      expect(isPromotionalOrAdText('Congratulations! Win cashback of up to Rs 500'), isTrue);
      expect(isPromotionalOrAdText('Rs 450 debited at Starbucks using card ending 1234'), isFalse);
    });
  });

  group('ExpenseRepository Deduplication Tests', () {
    late MockExpenseLocalDataSource localDataSource;
    late MockSettingsLocalDataSource settingsDataSource;
    late ExpenseRepositoryImpl repository;

    setUp(() {
      localDataSource = MockExpenseLocalDataSource();
      settingsDataSource = MockSettingsLocalDataSource();
      repository = ExpenseRepositoryImpl(
        expenseLocalDataSource: localDataSource,
        settingsLocalDataSource: settingsDataSource,
      );
    });

    test('Deduplicates between notification entry and SMS inbox entry for same transaction', () async {
      final notifTime = DateTime(2026, 9, 22, 14, 30, 0);
      final notifExpense = Expense(
        id: 'HDFCBK-S_spent_notif_1727000000000',
        name: 'Transaction',
        amount: 350.0,
        date: notifTime,
        bank: 'HDFCBK-S',
        category: 'Shopping',
        type: 'spent',
      );

      // Notification arrives first
      await repository.addExpense(notifExpense);
      var expenses = await repository.getExpenses().first;
      expect(expenses.expenses.length, 1);
      expect(expenses.expenses.first.name, 'Transaction');

      // Later, user syncs SMS from phone message folder which has exact merchant and ref number
      final smsTime = DateTime(2026, 9, 22, 14, 30, 2); // 2 seconds later
      final smsExpense = Expense(
        id: 'HDFCBK-S_spent_UPI987654321',
        name: 'Starbucks Coffee (UPI)',
        amount: 350.0,
        date: smsTime,
        bank: 'HDFCBK-S',
        category: 'Shopping',
        type: 'spent',
      );

      await repository.addExpense(smsExpense);
      expenses = await repository.getExpenses().first;

      // Should NOT duplicate; should update with better merchant name & real transaction ID
      expect(expenses.expenses.length, 1);
      expect(expenses.expenses.first.name, 'Starbucks Coffee (UPI)');
      expect(expenses.expenses.first.amount, 350.0);
      expect(expenses.expenses.first.id, 'HDFCBK-S_spent_UPI987654321');
    });

    test('Allows distinct transactions with different amounts or dates', () async {
      final exp1 = Expense(
        id: 'HDFCBK-S_spent_1',
        name: 'Merchant A',
        amount: 200.0,
        date: DateTime(2026, 9, 22, 10, 0, 0),
        bank: 'HDFCBK-S',
        category: 'Shopping',
        type: 'spent',
      );

      final exp2 = Expense(
        id: 'HDFCBK-S_spent_2',
        name: 'Merchant B',
        amount: 500.0,
        date: DateTime(2026, 9, 22, 11, 0, 0),
        bank: 'HDFCBK-S',
        category: 'Shopping',
        type: 'spent',
      );

      await repository.addExpenses([exp1, exp2]);
      final expenses = await repository.getExpenses().first;
      expect(expenses.expenses.length, 2);
    });

    test('Rejects declined and card-ending noise items from being added to repository', () async {
      final declinedExp1 = Expense(
        id: 'declined_1',
        name: 'incorrect pin. for rs. 4000.00',
        amount: 4000.0,
        date: DateTime(2026, 9, 22, 10, 0, 0),
        bank: 'SBIINB-T',
        category: 'Shopping',
        type: 'spent',
      );

      final declinedExp2 = Expense(
        id: 'declined_2',
        name: 'incorrect pin. for rs. 420.00',
        amount: 420.0,
        date: DateTime(2026, 9, 22, 10, 30, 0),
        bank: 'SBIINB-T',
        category: 'Shopping',
        type: 'spent',
      );

      final cardEndingExp = Expense(
        id: 'card_ending_1',
        name: 'indian rai with your credit card ending 6578.',
        amount: 450.0,
        date: DateTime(2026, 9, 22, 11, 0, 0),
        bank: 'HDFCBK-S',
        category: 'Shopping',
        type: 'spent',
      );

      final validExp = Expense(
        id: 'valid_1',
        name: 'Indian Railways UTS',
        amount: 30.0,
        date: DateTime(2026, 9, 22, 12, 0, 0),
        bank: 'HDFCBK-S',
        category: 'Shopping',
        type: 'spent',
      );

      await repository.addExpenses([declinedExp1, declinedExp2, cardEndingExp, validExp]);
      final expenses = await repository.getExpenses().first;

      // Only validExp should be present; the 3 invalid ones should be filtered out
      expect(expenses.expenses.length, 1);
      expect(expenses.expenses.first.name, 'Indian Railways UTS');
      expect(expenses.expenses.any((e) => e.name.contains('incorrect pin')), isFalse);
      expect(expenses.expenses.any((e) => e.name.contains('credit card ending')), isFalse);
    });

    test('Helper functions isDeclinedOrFailedText and isCardEndingOrDeclinedMerchant identify bad items', () {
      expect(isDeclinedOrFailedText('incorrect pin. for rs. 4000.00'), isTrue);
      expect(isDeclinedOrFailedText('incorrect pin. for rs. 420.00'), isTrue);
      expect(isDeclinedOrFailedText('txn declined at POS'), isTrue);
      expect(isDeclinedOrFailedText('transaction failed'), isTrue);
      expect(isDeclinedOrFailedText('payment unsuccessful'), isTrue);
      expect(isDeclinedOrFailedText('paid at Swiggy'), isFalse);

      expect(isCardEndingOrDeclinedMerchant('indian rai with your credit card ending 6578.'), isTrue);
      expect(isCardEndingOrDeclinedMerchant('card ending with 6578'), isTrue);
      expect(isCardEndingOrDeclinedMerchant('credit card ending 1234'), isTrue);
      expect(isCardEndingOrDeclinedMerchant('incorrect pin. for rs. 4000.00'), isTrue);
      expect(isCardEndingOrDeclinedMerchant('SWIGGY'), isFalse);
      expect(isCardEndingOrDeclinedMerchant('INDIAN RAILWAYS UTS'), isFalse);

      expect(cleanMerchantName('indian rai with your credit card ending 6578.'), 'indian rai');
      expect(cleanMerchantName('Swiggy with your card ending 1234'), 'Swiggy');
      expect(cleanMerchantName('Flipkart on your credit card ending 9999.'), 'Flipkart');
    });

    test('isStatementOrBillText correctly flags statement and total due notifications', () {
      expect(isStatementOrBillText('ement: total due amt: rs.1,419.00 min due amt'), isTrue);
      expect(isStatementOrBillText('ement: total due: rs.164.00 min.due: rs.164.0'), isTrue);
      expect(isStatementOrBillText('Statement for your credit card: Total due amt: Rs 12,212.00 min due amt: Rs 500'), isTrue);
      expect(isStatementOrBillText('Total amt due: Rs 527.00 pay by 20-Sep-26'), isTrue);
      expect(isStatementOrBillText('Your bill of Rs 899 is due on 25-Sep'), isTrue);
      expect(isStatementOrBillText('Paid Rs 500 to Swiggy'), isFalse);
      expect(isStatementOrBillText('Adhnan.e-2'), isFalse);
    });

    test('canonicalFilterMerchantName combines sequential handles like adhnan.e-2, adhnan.e-3 into adhnan.e', () {
      expect(canonicalFilterMerchantName('adhnan.e-2'), 'adhnan.e');
      expect(canonicalFilterMerchantName('adhnan.e-3'), 'adhnan.e');
      expect(canonicalFilterMerchantName('adhnan.e'), 'adhnan.e');
      expect(canonicalFilterMerchantName('adhnan.e-2 (UPI)'), 'adhnan.e (UPI)');
      expect(canonicalFilterMerchantName('guna080100-1@ok. (upi)'), 'guna080100 (UPI)');
      expect(canonicalFilterMerchantName('guna080100-3@okicici (upi)'), 'guna080100 (UPI)');
      expect(canonicalFilterMerchantName('irwinrex1996-1@. (upi)'), 'irwinrex1996 (UPI)');
      expect(canonicalFilterMerchantName('irwinrex1996@okhdfcbank (upi)'), 'irwinrex1996 (UPI)');
    });

    test('matchesExpenseNameFilter matches combined handles with single filter item', () {
      // Filter is "adhnan.e"
      expect(matchesExpenseNameFilter('adhnan.e-2', ['adhnan.e']), isTrue);
      expect(matchesExpenseNameFilter('adhnan.e-3', ['adhnan.e']), isTrue);
      expect(matchesExpenseNameFilter('adhnan.e', ['adhnan.e']), isTrue);
      expect(matchesExpenseNameFilter('adhnan.e-2 (UPI)', ['adhnan.e']), isTrue);
      expect(matchesExpenseNameFilter('adhnan.e (UPI)', ['adhnan.e']), isTrue);
      expect(matchesExpenseNameFilter('other.person', ['adhnan.e']), isFalse);

      // Filter is "adhnan.e (UPI)"
      expect(matchesExpenseNameFilter('adhnan.e-2', ['adhnan.e (UPI)']), isTrue);
      expect(matchesExpenseNameFilter('adhnan.e-3 (UPI)', ['adhnan.e (UPI)']), isTrue);

      // Empty filter returns false (no items selected)
      expect(matchesExpenseNameFilter('adhnan.e-2', []), isFalse);
    });

    test('Rejects total due and statement items from being added to repository', () async {
      final billExp1 = Expense(
        id: 'bill_1',
        name: 'ement: total due amt: rs.1,419.00 min due amt',
        amount: 1419.0,
        date: DateTime(2026, 9, 22, 10, 0, 0),
        bank: 'SBIINB-T',
        category: 'Shopping',
        type: 'spent',
      );

      final billExp2 = Expense(
        id: 'bill_2',
        name: 'ement: total due: rs.164.00 min.due: rs.164.0',
        amount: 164.0,
        date: DateTime(2026, 9, 22, 10, 30, 0),
        bank: 'SBIINB-T',
        category: 'Shopping',
        type: 'spent',
      );

      final validExp = Expense(
        id: 'valid_2',
        name: 'adhnan.e-2 (UPI)',
        amount: 50.0,
        date: DateTime(2026, 9, 22, 12, 0, 0),
        bank: 'HDFCBK-S',
        category: 'Shopping',
        type: 'spent',
      );

      await repository.addExpenses([billExp1, billExp2, validExp]);
      final expenses = await repository.getExpenses().first;

      expect(expenses.expenses.any((e) => e.name.contains('total due')), isFalse);
      expect(expenses.expenses.any((e) => e.name.contains('ement:')), isFalse);
    });
  });
}
