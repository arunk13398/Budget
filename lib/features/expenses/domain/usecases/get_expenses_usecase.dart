import '../../../../core/usecases/usecase.dart';
import '../entities/expense_data.dart';
import '../repositories/expense_repository.dart';

class GetExpensesUseCase implements StreamUseCase<ExpenseData, NoParams> {
  final ExpenseRepository repository;

  GetExpensesUseCase(this.repository);

  @override
  Stream<ExpenseData> call(NoParams params) {
    return repository.getExpenses();
  }
}
