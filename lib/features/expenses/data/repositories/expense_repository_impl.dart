import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../../domain/entities/expense.dart';
import '../../domain/entities/expense_data.dart';
import '../../domain/repositories/expense_repository.dart';
import '../datasources/expense_local_data_source.dart';
import '../datasources/settings_local_data_source.dart';
import '../models/expense_model.dart';
import '../../../../core/services/encryption_service.dart';
import '../../../../core/services/sms_service.dart';

bool _isGenericMerchantName(String name) {
  final lower = name.toLowerCase().trim();
  return lower == 'transaction' || 
         lower == 'bank alert' || 
         lower == 'a' || 
         lower == 'account' || 
         lower == 'bank' ||
         lower.startsWith('a/c') ||
         lower.length <= 2;
}

bool _isBetterMerchantName(String newName, String existingName) {
  final newIsGeneric = _isGenericMerchantName(newName);
  final existingIsGeneric = _isGenericMerchantName(existingName);
  
  if (existingIsGeneric && !newIsGeneric) return true;
  return false;
}

List<ExpenseModel> _parseExpensesIsolate(String encryptedJson) {
  final String expensesJson = EncryptionService.decryptData(encryptedJson);
  List<dynamic> decoded;
  try {
    decoded = json.decode(expensesJson);
  } catch (e) {
    try {
      decoded = json.decode(encryptedJson);
    } catch (_) {
      return [];
    }
  }

  final List<ExpenseModel> rawList = decoded.map((item) {
    final Map<String, dynamic> map = Map<String, dynamic>.from(item);
    return ExpenseModel.fromMap(map, map['id'] ?? '');
  }).toList();
  
  final List<ExpenseModel> deduplicated = [];
  
  for (var e in rawList) {
    if (isPromotionalOrAdText('${e.name} ${e.bank}')) {
      continue;
    }

    var cleanName = e.name.trim();
    if (cleanName.toLowerCase() == 'a' || cleanName.toLowerCase() == 'a/c' || cleanName.toLowerCase() == 'from a/c') {
      cleanName = 'Transaction';
    }

    final modelItem = ExpenseModel(
      id: e.id,
      name: cleanName,
      amount: e.amount,
      date: e.date,
      bank: e.bank,
      category: e.category,
      type: e.type,
    );

    final dupIndex = deduplicated.indexWhere((existing) =>
      existing.bank.toUpperCase() == modelItem.bank.toUpperCase() &&
      existing.amount == modelItem.amount &&
      (existing.date.difference(modelItem.date).inSeconds).abs() <= 120
    );

    if (dupIndex != -1) {
      if (_isBetterMerchantName(modelItem.name, deduplicated[dupIndex].name)) {
        deduplicated[dupIndex] = modelItem;
      }
    } else {
      deduplicated.add(modelItem);
    }
  }
  
  return deduplicated;
}

class ExpenseRepositoryImpl implements ExpenseRepository {
  final ExpenseLocalDataSource expenseLocalDataSource;
  final SettingsLocalDataSource settingsLocalDataSource;
  final StreamController<ExpenseData> _controller = StreamController<ExpenseData>.broadcast();
  
  List<Expense>? _cachedExpenses;
  double? _cachedLimit;

  static const String _kExpensesKey = 'local_expenses';
  static const String _kLimitKey = 'local_limit';

  ExpenseRepositoryImpl({
    required this.expenseLocalDataSource,
    required this.settingsLocalDataSource,
  }) {
    _initStorage();
  }

  Future<void> _initStorage() async {
    await _migrateLegacyDataIfNeeded();
    _emitLatest();
  }

  Future<void> _migrateLegacyDataIfNeeded() async {
    final String? legacyEncrypted = settingsLocalDataSource.getLegacyExpensesString(_kExpensesKey);
    if (expenseLocalDataSource.isEmpty() && legacyEncrypted != null && legacyEncrypted.isNotEmpty) {
      final List<ExpenseModel> deduplicated = await compute(_parseExpensesIsolate, legacyEncrypted);
      await expenseLocalDataSource.saveExpenses(deduplicated);
      await settingsLocalDataSource.removeLegacyKey(_kExpensesKey);
    }

    final double? legacyLimit = settingsLocalDataSource.getLegacyLimitDouble(_kLimitKey);
    if (legacyLimit != null) {
      await settingsLocalDataSource.saveLimit(legacyLimit);
      await settingsLocalDataSource.removeLegacyKey(_kLimitKey);
    }
  }

  List<Expense> _getRawExpenses() {
    if (_cachedExpenses != null) return List.from(_cachedExpenses!);
    _cachedExpenses = expenseLocalDataSource.getExpenses();
    return List.from(_cachedExpenses!);
  }

  double _getRawLimit() {
    if (_cachedLimit != null) return _cachedLimit!;
    _cachedLimit = settingsLocalDataSource.getLimit();
    return _cachedLimit!;
  }

  Future<void> _emitLatest() async {
    final expenses = _getRawExpenses();
    final limit = _getRawLimit();
    _controller.add(ExpenseData(expenses: expenses, limit: limit));
  }

  @override
  Future<void> addExpense(Expense expense) async {
    await addExpenses([expense]);
  }

  @override
  Future<void> addExpenses(List<Expense> newExpenses) async {
    final expenses = _getRawExpenses().map((e) => e as ExpenseModel).toList();
    bool changed = false;

    for (var expense in newExpenses) {
      final model = ExpenseModel(
        id: expense.id.isEmpty || expense.id.startsWith('temp_')
            ? DateTime.now().millisecondsSinceEpoch.toString()
            : expense.id,
        name: expense.name,
        amount: expense.amount,
        date: expense.date,
        bank: expense.bank,
        category: expense.category,
        type: expense.type,
      );

      final index = expenses.indexWhere((e) => e.id == model.id);
      if (index != -1) {
        expenses[index] = model;
        await expenseLocalDataSource.saveExpense(model);
        changed = true;
      } else {
        final dupIndex = expenses.indexWhere((e) =>
          e.bank.toUpperCase() == model.bank.toUpperCase() &&
          e.amount == model.amount &&
          (e.date.difference(model.date).inSeconds).abs() <= 120
        );

        if (dupIndex != -1) {
          if (_isBetterMerchantName(model.name, expenses[dupIndex].name)) {
            expenses[dupIndex] = model;
            await expenseLocalDataSource.saveExpense(model);
            changed = true;
          }
        } else {
          expenses.add(model);
          await expenseLocalDataSource.saveExpense(model);
          changed = true;
        }
      }
    }

    if (changed) {
      _cachedExpenses = List.from(expenses);
      _emitLatest();
    }
  }

  @override
  Stream<ExpenseData> getExpenses() async* {
    yield ExpenseData(expenses: _getRawExpenses(), limit: _getRawLimit());
    yield* _controller.stream;
  }
  
  Future<void> updateLimit(double limit) async {
    _cachedLimit = limit;
    await settingsLocalDataSource.saveLimit(limit);
    _emitLatest();
  }

  @override
  Future<void> deleteExpense(String id) async {
    await expenseLocalDataSource.deleteExpense(id);
    _cachedExpenses = expenseLocalDataSource.getExpenses();
    _emitLatest();
  }
}
