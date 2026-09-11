import '../../domain/repositories/expense_repository.dart';
import '../../../../core/usecases/usecase.dart';

class DeleteExpenseUseCase implements UseCase<void, String> {
  final ExpenseRepository repository;

  DeleteExpenseUseCase(this.repository);

  @override
  Future<void> call(String params) async {
    return await repository.deleteExpense(params);
  }
}
