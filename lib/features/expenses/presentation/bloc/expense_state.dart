import 'package:equatable/equatable.dart';
import '../../domain/entities/expense_data.dart';

abstract class ExpenseState extends Equatable {
  @override
  List<Object?> get props => [];
}

class ExpenseInitial extends ExpenseState {}

class ExpenseLoading extends ExpenseState {}

class ExpenseLoaded extends ExpenseState {
  final ExpenseData data;

  ExpenseLoaded(this.data);

  @override
  List<Object?> get props => [data];
}

class ExpenseError extends ExpenseState {
  final String message;
  ExpenseError(this.message);

  @override
  List<Object?> get props => [message];
}
