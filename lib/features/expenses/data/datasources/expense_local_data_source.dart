import 'package:hive/hive.dart';
import '../models/expense_model.dart';

abstract class ExpenseLocalDataSource {
  List<ExpenseModel> getExpenses();
  Future<void> saveExpense(ExpenseModel expense);
  Future<void> saveExpenses(List<ExpenseModel> expenses);
  Future<void> deleteExpense(String id);
  bool isEmpty();
}

class ExpenseLocalDataSourceImpl implements ExpenseLocalDataSource {
  final Box<ExpenseModel> expensesBox;

  ExpenseLocalDataSourceImpl({required this.expensesBox});

  @override
  List<ExpenseModel> getExpenses() {
    return expensesBox.values.toList();
  }

  @override
  Future<void> saveExpense(ExpenseModel expense) async {
    await expensesBox.put(expense.id, expense);
  }

  @override
  Future<void> saveExpenses(List<ExpenseModel> expenses) async {
    for (var expense in expenses) {
      await expensesBox.put(expense.id, expense);
    }
  }

  @override
  Future<void> deleteExpense(String id) async {
    if (expensesBox.containsKey(id)) {
      await expensesBox.delete(id);
    }
  }

  @override
  bool isEmpty() {
    return expensesBox.isEmpty;
  }
}
