import '../../../../core/usecases/usecase.dart';
import '../../domain/entities/expense.dart';
import '../../domain/repositories/expense_repository.dart';

class AddExpenseUseCase implements UseCase<void, Expense> {
  final ExpenseRepository repository;

  AddExpenseUseCase(this.repository);

  @override
  Future<void> call(Expense expense) async {
    return await repository.addExpense(expense);
  }
}
