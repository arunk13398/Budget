import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/usecases/usecase.dart';
import '../../../../core/services/sms_service.dart';
import '../../../../injection_container.dart' as di;
import '../../domain/entities/expense.dart';
import '../../domain/entities/expense_data.dart';
import '../../domain/usecases/add_expense_usecase.dart';
import '../../domain/usecases/delete_expense_usecase.dart';
import '../../domain/usecases/get_expenses_usecase.dart';
import 'expense_state.dart';

class ExpenseNotifier extends StateNotifier<ExpenseState> {
  final AddExpenseUseCase addExpenseUseCase;
  final GetExpensesUseCase getExpensesUseCase;
  final DeleteExpenseUseCase deleteExpenseUseCase;
  final SmsService smsService;
  StreamSubscription? _expensesSubscription;

  ExpenseNotifier({
    required this.addExpenseUseCase,
    required this.getExpensesUseCase,
    required this.deleteExpenseUseCase,
    required this.smsService,
  }) : super(ExpenseInitial()) {
    loadExpenses();
  }

  void loadExpenses() {
    state = ExpenseLoading();
    _expensesSubscription?.cancel();
    _expensesSubscription = getExpensesUseCase(NoParams()).listen(
      (expenseData) async {
        final bankGroups = await smsService.readAllBankSmsGrouped();
        state = ExpenseLoaded(
          ExpenseData(
            expenses: expenseData.expenses,
            limit: expenseData.limit,
            bankGroups: bankGroups,
          ),
        );
      },
      onError: (error) => state = ExpenseError(error.toString()),
    );
  }

  Future<void> syncSms() async {
    try {
      await smsService.readAndPrintSms();
      loadExpenses();
    } catch (e) {
      state = ExpenseError(e.toString());
    }
  }

  Future<void> addExpense(Expense expense) async {
    try {
      await addExpenseUseCase(expense);
    } catch (e) {
      state = ExpenseError(e.toString());
    }
  }

  Future<void> deleteExpense(String id) async {
    try {
      await deleteExpenseUseCase(id);
    } catch (e) {
      state = ExpenseError(e.toString());
    }
  }

  @override
  void dispose() {
    _expensesSubscription?.cancel();
    super.dispose();
  }
}

final expenseNotifierProvider =
    StateNotifierProvider<ExpenseNotifier, ExpenseState>((ref) {
  return ExpenseNotifier(
    addExpenseUseCase: di.sl<AddExpenseUseCase>(),
    getExpensesUseCase: di.sl<GetExpensesUseCase>(),
    deleteExpenseUseCase: di.sl<DeleteExpenseUseCase>(),
    smsService: di.sl<SmsService>(),
  );
});
