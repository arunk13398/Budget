import 'package:get_it/get_it.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'features/expenses/data/adapters/expense_model_adapter.dart';
import 'features/expenses/data/models/expense_model.dart';
import 'features/expenses/data/repositories/expense_repository_impl.dart';
import 'features/expenses/domain/repositories/expense_repository.dart';
import 'features/expenses/domain/usecases/add_expense_usecase.dart';
import 'features/expenses/domain/usecases/get_expenses_usecase.dart';
import 'features/expenses/domain/usecases/delete_expense_usecase.dart';
import 'features/expenses/presentation/bloc/expense_bloc.dart';
import 'core/services/sms_service.dart';

final sl = GetIt.instance;

Future<void> init() async {
  // Hive Initialization
  await Hive.initFlutter();

  if (!Hive.isAdapterRegistered(0)) {
    Hive.registerAdapter(ExpenseModelAdapter());
  }

  Box<ExpenseModel> expensesBox;
  if (Hive.isBoxOpen('expenses_box')) {
    expensesBox = Hive.box<ExpenseModel>('expenses_box');
  } else {
    expensesBox = await Hive.openBox<ExpenseModel>('expenses_box');
  }

  Box<dynamic> settingsBox;
  if (Hive.isBoxOpen('settings_box')) {
    settingsBox = Hive.box<dynamic>('settings_box');
  } else {
    settingsBox = await Hive.openBox<dynamic>('settings_box');
  }

  final sharedPreferences = await SharedPreferences.getInstance();

  if (!sl.isRegistered<Box<ExpenseModel>>()) {
    sl.registerLazySingleton<Box<ExpenseModel>>(() => expensesBox);
  }
  if (!sl.isRegistered<Box<dynamic>>()) {
    sl.registerLazySingleton<Box<dynamic>>(() => settingsBox);
  }
  if (!sl.isRegistered<SharedPreferences>()) {
    sl.registerLazySingleton(() => sharedPreferences);
  }

  // Services
  if (!sl.isRegistered<SmsService>()) {
    sl.registerLazySingleton(() => SmsService(sl()));
  }
  
  // Blocs
  if (!sl.isRegistered<ExpenseBloc>()) {
    sl.registerFactory(
      () => ExpenseBloc(
        addExpenseUseCase: sl(),
        getExpensesUseCase: sl(),
        deleteExpenseUseCase: sl(),
        smsService: sl(),
      ),
    );
  }

  // Use cases
  if (!sl.isRegistered<AddExpenseUseCase>()) {
    sl.registerLazySingleton(() => AddExpenseUseCase(sl()));
  }
  if (!sl.isRegistered<GetExpensesUseCase>()) {
    sl.registerLazySingleton(() => GetExpensesUseCase(sl()));
  }
  if (!sl.isRegistered<DeleteExpenseUseCase>()) {
    sl.registerLazySingleton(() => DeleteExpenseUseCase(sl()));
  }

  // Repository
  if (!sl.isRegistered<ExpenseRepository>()) {
    sl.registerLazySingleton<ExpenseRepository>(
      () => ExpenseRepositoryImpl(
        expensesBox: sl(),
        settingsBox: sl(),
        sharedPreferences: sl(),
      ),
    );
  }
}
