import '../../domain/entities/expense.dart';

class ExpenseModel extends Expense {
  const ExpenseModel({
    required super.id,
    required super.name,
    required super.amount,
    required super.date,
    required super.bank,
    required super.category,
    required super.type,
    super.balance,
  });

  factory ExpenseModel.fromMap(Map<dynamic, dynamic> map, String id) {
    return ExpenseModel(
      id: id,
      name: map['name'] ?? '',
      amount: (map['amount'] ?? 0).toDouble(),
      date: DateTime.fromMillisecondsSinceEpoch(map['date'] ?? 0),
      bank: map['bank'] ?? '',
      category: map['category'] ?? 'General',
      type: map['type'] ?? 'spent',
      balance: map['balance'] != null ? (map['balance'] as num).toDouble() : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'amount': amount,
      'date': date.millisecondsSinceEpoch,
      'bank': bank,
      'category': category,
      'type': type,
      if (balance != null) 'balance': balance,
    };
  }
}
