import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract class SettingsLocalDataSource {
  double getLimit({double defaultValue = 80000.0});
  Future<void> saveLimit(double limit);
  String? getLegacyExpensesString(String key);
  double? getLegacyLimitDouble(String key);
  Future<void> removeLegacyKey(String key);
}

class SettingsLocalDataSourceImpl implements SettingsLocalDataSource {
  final Box<dynamic> settingsBox;
  final SharedPreferences? sharedPreferences;

  static const String _kLimitKey = 'local_limit';

  SettingsLocalDataSourceImpl({
    required this.settingsBox,
    this.sharedPreferences,
  });

  @override
  double getLimit({double defaultValue = 80000.0}) {
    return (settingsBox.get(_kLimitKey, defaultValue: defaultValue) as num).toDouble();
  }

  @override
  Future<void> saveLimit(double limit) async {
    await settingsBox.put(_kLimitKey, limit);
  }

  @override
  String? getLegacyExpensesString(String key) {
    return sharedPreferences?.getString(key);
  }

  @override
  double? getLegacyLimitDouble(String key) {
    return sharedPreferences?.getDouble(key);
  }

  @override
  Future<void> removeLegacyKey(String key) async {
    await sharedPreferences?.remove(key);
  }
}
