import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:home_widget/home_widget.dart';
import 'package:widget_learning/screens/home_screen.dart';
import 'core/services/sms_service.dart';
import 'injection_container.dart' as di;
import 'features/expenses/presentation/bloc/expense_bloc.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await di.init();

  if (!kIsWeb) {
    await HomeWidget.setAppGroupId('group.nagavalliApp');
    HomeWidget.registerBackgroundCallback(backgroundCallback);
  }

  // Initialize Play Store compliant Notification Listener
  di.sl<SmsService>().initNotificationListener();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => di.sl<ExpenseBloc>(),
      child: MaterialApp(
        title: 'Spender Pro',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
          useMaterial3: true,
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
