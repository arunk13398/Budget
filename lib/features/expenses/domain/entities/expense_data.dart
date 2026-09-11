import 'package:equatable/equatable.dart';
import 'expense.dart';
import '../../../../core/services/sms_service.dart';

class ExpenseData extends Equatable {
  final List<Expense> expenses;
  final double limit;
  final List<BankSmsGroup> bankGroups;

  const ExpenseData({
    required this.expenses,
    required this.limit,
    this.bankGroups = const [],
  });

  @override
  List<Object?> get props => [expenses, limit, bankGroups];
}
