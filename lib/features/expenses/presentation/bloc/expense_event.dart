import 'package:equatable/equatable.dart';
import '../../domain/entities/expense.dart';
import '../../domain/entities/expense_data.dart';

abstract class ExpenseEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

class LoadExpensesEvent extends ExpenseEvent {}

class AddExpenseEvent extends ExpenseEvent {
  final Expense expense;
  AddExpenseEvent(this.expense);

  @override
  List<Object?> get props => [expense];
}

class ExpensesUpdatedEvent extends ExpenseEvent {
  final ExpenseData expenseData;
  ExpensesUpdatedEvent(this.expenseData);

  @override
  List<Object?> get props => [expenseData];
}

class ExpenseErrorEvent extends ExpenseEvent {
  final String message;
  ExpenseErrorEvent(this.message);

  @override
  List<Object?> get props => [message];
}

class SetValueEvent extends ExpenseEvent {
  final bool expanded;
  SetValueEvent(this.expanded);

  @override
  List<Object?> get props => [expanded];
}
class DeleteExpenseEvent extends ExpenseEvent {
  final String id;
  DeleteExpenseEvent(this.id);

  @override
  List<Object?> get props => [id];
}

class SyncSmsEvent extends ExpenseEvent {}
