import 'package:equatable/equatable.dart';

class Expense extends Equatable {
  final String id;
  final String name;
  final double amount;
  final DateTime date;
  final String bank;
  final String category;
  final String type; // 'spent', 'credited', 'debited'
  final double? balance;

  const Expense({
    required this.id,
    required this.name,
    required this.amount,
    required this.date,
    required this.bank,
    required this.category,
    required this.type,
    this.balance,
  });

  @override
  List<Object?> get props => [id, name, amount, date, bank, category, type, balance];
}
