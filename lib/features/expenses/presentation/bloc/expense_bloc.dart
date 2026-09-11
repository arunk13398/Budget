import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/usecases/usecase.dart';
import '../../domain/usecases/add_expense_usecase.dart';
import '../../domain/usecases/get_expenses_usecase.dart';
import '../../domain/usecases/delete_expense_usecase.dart';
import 'expense_event.dart';
import 'expense_state.dart';
import '../../../../core/services/sms_service.dart';
import '../../domain/entities/expense_data.dart';

class ExpenseBloc extends Bloc<ExpenseEvent, ExpenseState> {
  final AddExpenseUseCase addExpenseUseCase;
  final GetExpensesUseCase getExpensesUseCase;
  final DeleteExpenseUseCase deleteExpenseUseCase;
  final SmsService smsService;
  StreamSubscription? _expensesSubscription;

  ExpenseBloc({
    required this.addExpenseUseCase,
    required this.getExpensesUseCase,
    required this.deleteExpenseUseCase,
    required this.smsService,
  }) : super(ExpenseInitial()) {
    on<LoadExpensesEvent>((event, emit) async {
      emit(ExpenseLoading());
      await _expensesSubscription?.cancel();
      _expensesSubscription = getExpensesUseCase(NoParams()).listen(
        (expenseData) async {
          final bankGroups = await smsService.readAllBankSmsGrouped();
          add(ExpensesUpdatedEvent(
            ExpenseData(
              expenses: expenseData.expenses,
              limit: expenseData.limit,
              bankGroups: bankGroups,
            ),
          ));
        },
        onError: (error) => add(ExpenseErrorEvent(error.toString())),
      );
    });
    on<AddExpenseEvent>(_onAddExpense);
    on<DeleteExpenseEvent>(_onDeleteExpense);
    on<ExpensesUpdatedEvent>(_onExpensesUpdated);
    on<ExpenseErrorEvent>(_onExpenseError);
    on<SetValueEvent>(_onSetValueEvent);
    on<SyncSmsEvent>(_onSyncSms);
  }

  Future<void> _onSyncSms(SyncSmsEvent event, Emitter<ExpenseState> emit) async {
    try {
      await smsService.readAndPrintSms();
      add(LoadExpensesEvent());
    } catch (e) {
      emit(ExpenseError(e.toString()));
    }
  }

  Future<void> _onAddExpense(AddExpenseEvent event, Emitter<ExpenseState> emit) async {
    try {
      await addExpenseUseCase(event.expense);
    } catch (e) {
      emit(ExpenseError(e.toString()));
    }
  }

  Future<void> _onDeleteExpense(DeleteExpenseEvent event, Emitter<ExpenseState> emit) async {
    try {
      await deleteExpenseUseCase(event.id);
    } catch (e) {
      emit(ExpenseError(e.toString()));
    }
  }

  void _onExpensesUpdated(ExpensesUpdatedEvent event, Emitter<ExpenseState> emit) {
    emit(ExpenseLoaded(event.expenseData));
  }

  void _onExpenseError(ExpenseErrorEvent event, Emitter<ExpenseState> emit) {
    emit(ExpenseError(event.message));
  }

  void _onSetValueEvent(
      SetValueEvent event,
      Emitter<ExpenseState> emit,
      ) {
    // Logic for expanded state removed as per user request
  }

  @override
  Future<void> close() {
    _expensesSubscription?.cancel();
    return super.close();
  }
}
