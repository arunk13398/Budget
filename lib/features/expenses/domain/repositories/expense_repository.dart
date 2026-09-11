import '../entities/expense.dart';
import '../entities/expense_data.dart';

abstract class ExpenseRepository {
  Future<void> addExpense(Expense expense);
  Future<void> addExpenses(List<Expense> expenses);
  Stream<ExpenseData> getExpenses();
  Future<void> deleteExpense(String id);
}
