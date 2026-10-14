import 'dart:async';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:home_widget/home_widget.dart';
import 'package:flip_card/flip_card.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/services/encryption_service.dart';
import '../providers/expense_provider.dart';
import '../providers/expense_state.dart';
import 'dart:ui' as ui;
import 'dart:math' as math;
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:flutter/rendering.dart';
import '../../domain/entities/expense.dart';
import 'package:url_launcher/url_launcher.dart';

import '../helpers/home_helper.dart';
import '../widgets/combined_group_bar_chart.dart';
import '../widgets/expense_line_chart.dart';
import '../widgets/expense_pie_chart.dart';
import '../widgets/transaction_item.dart';
import '../widgets/warning_box.dart';
import '../widgets/year_contribution_heatmap.dart';
import '../widgets/simple_color_slider_picker.dart';
import '../widgets/total_budget_overview_card.dart';
import '../../../../core/services/sms_service.dart';
import '../../../../core/services/app_update_service.dart';
import '../../../../core/constants/app_constants.dart';
import '../dialogs/custom_blue_date_picker_dialog.dart';
import '../../domain/repositories/expense_repository.dart';
import '../../../../injection_container.dart' as di;

@pragma('vm:entry-point')
Future<void> backgroundCallback(Uri? uri) async {
  if (uri?.host == 'sync') {
    await di.init();
    final smsService = di.sl<SmsService>();
    await smsService.readAndPrintSms(
      targetMonth: DateTime.now().month,
      targetYear: DateTime.now().year,
    );

    await HomeWidget.updateWidget(
      name: 'NagavalliWidgetProvider',
      iOSName: 'NagavalliWidgetProvider',
    );
    await HomeWidget.updateWidget(
      name: 'NagavalliPieWidgetProvider',
      iOSName: 'NagavalliPieWidgetProvider',
    );
    await HomeWidget.updateWidget(
      name: 'NagavalliLineWidgetProvider',
      iOSName: 'NagavalliLineWidgetProvider',
    );
  }
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> with WidgetsBindingObserver {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final ScrollController _monthScrollController = ScrollController();
  bool _isSyncing = false;
  double _currentValue = 0.0;
  final double minValue = 0.0;
  final double maxValue = 80000.0;
  String cardName = 'SBI CREDIT CARD';
  List<String> visibleCards = [];
  int _drawerTabIndex = 0;
  int _transactionTabIndex = 0;
  int selectedMonth = DateTime.now().month - 1;
  int? selectedWeek;
  List<String> selectedExpenseNames = [];
  Map<String, DateTime> cardDueDates = {};
  Map<String, double> cardLimits = {};
  Map<String, double> cardBoundaries = {};
  Map<String, bool> cardBudgetEnabled = {}; // cardName -> bool
  Map<String, bool> isCreditCardOverrides = {};
  Map<String, bool> hideCreditDataOverrides = {};
  Map<String, bool> includeInTotalBudget = {}; // cardName -> bool
  Map<String, String> categoryGroups = {}; // merchant -> groupName
  Map<String, String> transactionGroups = {}; // transactionId -> groupName
  Map<String, int> groupColors = {}; // groupName -> colorInt
  Map<String, double> groupLimits = {}; // groupName -> maxLimit
  bool isDueDateFiltered = false;
  String? editingCardName;
  List<BankSmsGroup> _bankGroups = [];
  Map<String, String> cardThemes = {};
  Map<String, String> manualCards = {}; // cardName -> msgId
  Set<String> deletedCards = {};
  Set<String> disabledCards = {};
  bool showBudgetOverview = true;
  AppUpdateInfo? _availableUpdate;
  AppUpdateInfo? _latestUpdateInfo;
  bool _isCheckingUpdate = false;
  bool _isUpdateDismissed = false;

  // Temporary Drawer State
  List<String>? _tempVisibleCards;
  Set<String>? _tempDisabledCards;
  List<String>? _tempSelectedExpenseNames;
  String? _tempEditingCardName;
  Map<String, double>? _tempCardLimits;
  Map<String, double>? _tempCardBoundaries;
  Map<String, bool>? _tempCardBudgetEnabled;
  Map<String, DateTime>? _tempCardDueDates;
  Map<String, bool>? _tempIsCreditCardOverrides;
  Map<String, bool>? _tempHideCreditData;
  Map<String, bool>? _tempIncludeInTotalBudget;
  Map<String, String>? _tempCardThemes;
  bool? _tempShowBudgetOverview;
  List<String>? _cachedUniqueNames;
  Map<String, List<String>>? _cachedLabelGroups;
  List<String>? _cachedOtherMerchants;
  final Map<String, TextEditingController> _tempLimitControllers = {};
  final Map<String, TextEditingController> _tempBoundaryControllers = {};

  final GlobalKey _pieChartKey = GlobalKey();
  final GlobalKey _lineChartKey = GlobalKey();
  int _analyticsPageIndex = 0;
  final PageController _analyticsPageController = PageController();
  static const _notificationChannel =
      MethodChannel('com.budget.planning/notifications');
  final Map<String, double> _lastNotifiedSpending = {};
  final Map<String, double> _lastNotifiedBoundarySpending = {};
  final Map<String, double> _lastNotifiedMaxSpending = {};

  bool _isCardDeleted(String? name) {
    if (name == null || name.trim().isEmpty) return false;
    final target = name.trim().toUpperCase();
    final normTarget = normalizeBankName(name).trim().toUpperCase();

    for (final dc in deletedCards) {
      final cleanDc = dc.trim().toUpperCase();
      final normDc = normalizeBankName(dc).trim().toUpperCase();
      if (cleanDc == target ||
          normDc == target ||
          cleanDc == normTarget ||
          normDc == normTarget) {
        return true;
      }
      if (target.length >= 3 && cleanDc.length >= 3) {
        if (target.contains(cleanDc) || cleanDc.contains(target)) {
          return true;
        }
      }
    }
    return false;
  }

  bool _isCardDisabled(String? name) {
    if (name == null || name.trim().isEmpty) return false;
    final target = name.trim().toUpperCase();
    final normTarget = normalizeBankName(name).trim().toUpperCase();

    for (final dc in disabledCards) {
      final cleanDc = dc.trim().toUpperCase();
      final normDc = normalizeBankName(dc).trim().toUpperCase();
      if (cleanDc == target ||
          normDc == target ||
          cleanDc == normTarget ||
          normDc == normTarget) {
        return true;
      }
      if (target.length >= 3 && cleanDc.length >= 3) {
        if (target.contains(cleanDc) || cleanDc.contains(target)) {
          return true;
        }
      }
    }
    return false;
  }

  String getCardTheme(String bankName) {
    final queryName = bankName.isNotEmpty ? bankName : cardName;
    if (_tempCardThemes != null && queryName.isNotEmpty && _tempCardThemes!.containsKey(queryName) && _tempCardThemes![queryName] != null) {
      return _tempCardThemes![queryName]!;
    }
    if (queryName.isNotEmpty && cardThemes.containsKey(queryName) && cardThemes[queryName] != null) {
      return cardThemes[queryName]!;
    }
    final cleanInput = queryName.replaceAll(RegExp(r'[^A-Z0-9]'), '').toUpperCase();
    if (cleanInput.isNotEmpty) {
      if (_tempCardThemes != null) {
        for (final entry in _tempCardThemes!.entries) {
          final cleanKey = entry.key.replaceAll(RegExp(r'[^A-Z0-9]'), '').toUpperCase();
          if (cleanKey.isNotEmpty && cleanKey == cleanInput) {
            return entry.value;
          }
        }
      }
      for (final entry in cardThemes.entries) {
        final cleanKey = entry.key.replaceAll(RegExp(r'[^A-Z0-9]'), '').toUpperCase();
        if (cleanKey.isNotEmpty && cleanKey == cleanInput) {
          return entry.value;
        }
      }
    }
    return 'Ocean';
  }

  List<Color> getCardThemeGradient(String bankName) {
    final theme = getCardTheme(bankName);
    final themeGradients = AppConstants.themeGradients;
    return themeGradients[theme] ?? themeGradients['Ocean']!;
  }

  Color getThemeColor(String bankName) {
    return getCardThemeGradient(bankName).first;
  }

  Future<bool?> _showAttractiveDeleteDialog({
    required BuildContext context,
    required String title,
    required String itemName,
    required String message,
    IconData icon = Icons.delete_forever_rounded,
    String deleteButtonText = 'Delete',
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        elevation: 12,
        backgroundColor: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFFCA5A5), width: 1.2),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Icon(
                  icon,
                  color: const Color(0xFFEF4444),
                  size: 28,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0F172A),
                  letterSpacing: -0.3,
                ),
              ),
              if (itemName.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Text(
                    itemName,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF334155),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12.5,
                  height: 1.4,
                  color: Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        side: BorderSide(color: Colors.grey.shade300),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF475569),
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        backgroundColor: const Color(0xFFEF4444),
                        elevation: 4,
                        shadowColor: const Color(
                          0xFFEF4444,
                        ).withValues(alpha: 0.4),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: () => Navigator.pop(ctx, true),
                      child: Text(
                        deleteButtonText,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    final savedCardName = prefs.getString('cardName') ?? '';
    final savedVisibleCards = prefs.getStringList('visibleCards') ?? [];
    final savedDeletedCards = prefs.getStringList('deletedCards') ?? [];
    final savedDisabledCards = prefs.getStringList('disabledCards') ?? [];
    final cgJsonEncrypted = prefs.getString('categoryGroups');
    final gcJsonEncrypted = prefs.getString('groupColors');
    final tgJsonEncrypted = prefs.getString('transactionGroups');
    final glJsonEncrypted = prefs.getString('groupLimits');

    // Run heavy AES decryption and JSON parsing concurrently in background Isolates!
    final results = await Future.wait([
      cgJsonEncrypted != null ? EncryptionService.decryptAndParseMapInIsolate(cgJsonEncrypted) : Future.value(<String, String>{}),
      gcJsonEncrypted != null ? EncryptionService.decryptAndParseMapInIsolate(gcJsonEncrypted) : Future.value(<String, String>{}),
      tgJsonEncrypted != null ? EncryptionService.decryptAndParseMapInIsolate(tgJsonEncrypted) : Future.value(<String, String>{}),
      glJsonEncrypted != null ? EncryptionService.decryptAndParseMapInIsolate(glJsonEncrypted) : Future.value(<String, String>{}),
    ]);

    final Map<String, double> newCardLimits = {};
    final Map<String, double> newCardBoundaries = {};
    final Map<String, bool> newCardBudgetEnabled = {};
    final Map<String, bool> newIsCreditCardOverrides = {};
    final Map<String, bool> newHideCreditDataOverrides = {};
    final Map<String, DateTime> newCardDueDates = {};
    final Map<String, bool> newIncludeInTotalBudget = {};
    final Map<String, String> newCardThemes = {};

    final keys = prefs.getKeys();
    for (var key in keys) {
      if (key.startsWith('limit_')) {
        final card = key.replaceFirst('limit_', '');
        newCardLimits[card] = prefs.getDouble(key)!;
      } else if (key.startsWith('boundary_')) {
        final card = key.replaceFirst('boundary_', '');
        final val = prefs.getDouble(key) ?? 0.0;
        if (val > 0) newCardBoundaries[card] = val;
      } else if (key.startsWith('budgetEnabled_')) {
        final card = key.replaceFirst('budgetEnabled_', '');
        newCardBudgetEnabled[card] = prefs.getBool(key) ?? true;
      } else if (key.startsWith('isCreditCard_')) {
        final card = key.replaceFirst('isCreditCard_', '');
        newIsCreditCardOverrides[card] = prefs.getBool(key) ?? false;
      } else if (key.startsWith('hideCreditData_')) {
        final card = key.replaceFirst('hideCreditData_', '');
        newHideCreditDataOverrides[card] = prefs.getBool(key) ?? false;
      } else if (key.startsWith('dueDate_')) {
        final card = key.replaceFirst('dueDate_', '');
        final ds = prefs.getString(key);
        if (ds != null) newCardDueDates[card] = DateTime.parse(ds);
      } else if (key.startsWith('includeInTotalBudget_')) {
        final card = key.replaceFirst('includeInTotalBudget_', '');
        newIncludeInTotalBudget[card] = prefs.getBool(key) ?? true;
      } else if (key.startsWith('theme_')) {
        final card = key.replaceFirst('theme_', '');
        newCardThemes[card] = prefs.getString(key) ?? 'Ocean';
      }
    }

    Map<String, String> newManualCards = {};
    final mcJson = prefs.getString('manualCards');
    if (mcJson != null) {
      try {
        newManualCards = Map<String, String>.from(jsonDecode(mcJson));
      } catch (_) {}
    }

    if (!mounted) return;

    setState(() {
      deletedCards = savedDeletedCards.toSet();
      disabledCards = savedDisabledCards.toSet();
      cardName = savedCardName;
      visibleCards = savedVisibleCards
          .where((card) =>
              !_isCardDeleted(card) &&
              isValidBankCardName(card, manualCards: newManualCards))
          .toList();
      cardLimits = newCardLimits;
      cardBoundaries = newCardBoundaries;
      cardBudgetEnabled = newCardBudgetEnabled;
      isCreditCardOverrides = newIsCreditCardOverrides;
      hideCreditDataOverrides = newHideCreditDataOverrides;
      cardDueDates = newCardDueDates;
      includeInTotalBudget = newIncludeInTotalBudget;
      cardThemes = newCardThemes;
      manualCards = newManualCards;
      showBudgetOverview = prefs.getBool('show_budget_overview') ?? true;

      categoryGroups = results[0];

      final rawGc = results[1];
      groupColors = rawGc.map((k, v) => MapEntry(k, int.tryParse(v) ?? Colors.grey.value));

      transactionGroups = results[2];

      final rawGl = results[3];
      groupLimits = rawGl.map((k, v) => MapEntry(k, double.tryParse(v) ?? 0.0));

      if (!groupLimits.containsKey('Unread')) {
        groupLimits['Unread'] = 0.0;
        groupColors['Unread'] = Colors.grey.value;
      }

      if (!groupLimits.containsKey('Travel')) {
        groupLimits['Travel'] = 0.0;
        groupColors['Travel'] = Colors.blue.value;
      }

      if (!groupLimits.containsKey('Shopping')) {
        groupLimits['Shopping'] = 0.0;
        groupColors['Shopping'] = Colors.purple.value;
      }
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cardName', cardName);
    await prefs.setStringList('visibleCards', visibleCards);
    await prefs.setStringList('deletedCards', deletedCards.toList());
    await prefs.setStringList('disabledCards', disabledCards.toList());
    await prefs.setBool('show_budget_overview', showBudgetOverview);

    for (final entry in cardLimits.entries) {
      await prefs.setDouble('limit_${entry.key}', entry.value);
    }
    for (final entry in cardBoundaries.entries) {
      if (entry.value > 0) {
        await prefs.setDouble('boundary_${entry.key}', entry.value);
      } else {
        await prefs.remove('boundary_${entry.key}');
      }
    }
    for (final entry in cardBudgetEnabled.entries) {
      await prefs.setBool('budgetEnabled_${entry.key}', entry.value);
    }
    final allKeys = prefs.getKeys();
    for (final key in allKeys) {
      if (key.startsWith('limit_')) {
        final card = key.replaceFirst('limit_', '');
        if (_isCardDeleted(card) || !cardLimits.containsKey(card)) {
          await prefs.remove(key);
        }
      } else if (key.startsWith('boundary_')) {
        final card = key.replaceFirst('boundary_', '');
        if (_isCardDeleted(card) || !cardBoundaries.containsKey(card)) {
          await prefs.remove(key);
        }
      } else if (key.startsWith('budgetEnabled_')) {
        final card = key.replaceFirst('budgetEnabled_', '');
        if (_isCardDeleted(card) || !cardBudgetEnabled.containsKey(card)) {
          await prefs.remove(key);
        }
      } else if (key.startsWith('dueDate_')) {
        final card = key.replaceFirst('dueDate_', '');
        if (_isCardDeleted(card) || !cardDueDates.containsKey(card)) {
          await prefs.remove(key);
        }
      } else if (key.startsWith('isCreditCard_')) {
        final card = key.replaceFirst('isCreditCard_', '');
        if (_isCardDeleted(card) || !isCreditCardOverrides.containsKey(card)) {
          await prefs.remove(key);
        }
      } else if (key.startsWith('hideCreditData_')) {
        final card = key.replaceFirst('hideCreditData_', '');
        if (_isCardDeleted(card) || !hideCreditDataOverrides.containsKey(card)) {
          await prefs.remove(key);
        }
      } else if (key.startsWith('theme_')) {
        final card = key.replaceFirst('theme_', '');
        if (_isCardDeleted(card) || !cardThemes.containsKey(card)) {
          await prefs.remove(key);
        }
      } else if (key.startsWith('includeInTotalBudget_')) {
        final card = key.replaceFirst('includeInTotalBudget_', '');
        if (_isCardDeleted(card) || !includeInTotalBudget.containsKey(card)) {
          await prefs.remove(key);
        }
      }
    }
    for (final entry in cardDueDates.entries) {
      await prefs.setString('dueDate_${entry.key}', entry.value.toIso8601String());
    }
    for (final entry in isCreditCardOverrides.entries) {
      await prefs.setBool('isCreditCard_${entry.key}', entry.value);
    }
    for (final entry in hideCreditDataOverrides.entries) {
      await prefs.setBool('hideCreditData_${entry.key}', entry.value);
    }
    for (final entry in cardThemes.entries) {
      await prefs.setString('theme_${entry.key}', entry.value);
    }
    for (final entry in includeInTotalBudget.entries) {
      await prefs.setBool('includeInTotalBudget_${entry.key}', entry.value);
    }

    await prefs.setString('manualCards', jsonEncode(manualCards));

    // Run JSON encoding and AES encryption in background Isolates!
    final encryptedMaps = await Future.wait([
      EncryptionService.parseAndEncryptMapInIsolate(categoryGroups),
      EncryptionService.parseAndEncryptMapInIsolate(transactionGroups),
      EncryptionService.parseAndEncryptMapInIsolate(groupColors),
      EncryptionService.parseAndEncryptMapInIsolate(groupLimits),
    ]);

    await prefs.setString('categoryGroups', encryptedMaps[0]);
    await prefs.setString('transactionGroups', encryptedMaps[1]);
    await prefs.setString('groupColors', encryptedMaps[2]);
    await prefs.setString('groupLimits', encryptedMaps[3]);
  }

  void _showCustomSyncToast({Expense? expense, int? count}) {
    if (!mounted) return;

    final isSingle = expense != null;
    final isCredit = isSingle ? expense.type == 'credited' : true;
    final accentColor = isCredit ? const Color(0xFF00E676) : const Color(0xFFFF5252);

    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        elevation: 12,
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        padding: EdgeInsets.zero,
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        duration: const Duration(seconds: 4),
        content: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF161B22),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: accentColor.withValues(alpha: 0.35), width: 1.2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
              BoxShadow(
                color: accentColor.withValues(alpha: 0.12),
                blurRadius: 12,
                spreadRadius: -2,
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isSingle
                      ? (isCredit
                            ? Icons.arrow_downward_rounded
                            : Icons.arrow_upward_rounded)
                      : Icons.sync_rounded,
                  color: accentColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isSingle ? 'Auto-Synced Payment' : (count != null && count > 0 ? 'Synced Transactions' : 'Sync Complete'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isSingle
                          ? '${expense.name} • ${expense.bank}'
                          : (count != null && count > 0)
                              ? 'Captured $count payment(s) from SMS & Notifications'
                              : 'All bank transactions are up to date',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.75),
                        fontSize: 11.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (isSingle) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${isCredit ? "+" : "-"} ₹${expense.amount.toStringAsFixed(0)}',
                    style: TextStyle(
                      color: accentColor,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initApp();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncPendingNotificationsOnResume();
    }
  }

  Future<void> _syncPendingNotificationsOnResume() async {
    di.sl<SmsService>().rebindNotificationListener();
    final syncedCount = await di.sl<SmsService>().syncPendingNotificationCache(
      manualCards: manualCards,
    );
    if (syncedCount > 0 && mounted) {
      await _loadBankGroups();
      ref.read(expenseNotifierProvider.notifier).loadExpenses();
      _scheduleWidgetUpdate();
      _showCustomSyncToast(count: syncedCount);
    }
  }

  Future<void> _initApp() async {
    await _loadSettings();
    await _loadBankGroups();

    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      await Permission.notification.request();
    }

    // Initialize Notification Listener for auto-syncing bank transaction notifications
    di.sl<SmsService>().initNotificationListener(
      manualCards: manualCards,
      onExpenseAutoSynced: (expense) async {
        await _loadBankGroups();
        if (mounted) {
          ref.read(expenseNotifierProvider.notifier).loadExpenses();
          _scheduleWidgetUpdate();
          _showCustomSyncToast(expense: expense);
        }
      },
    );

    if (visibleCards.isNotEmpty) {
      // Force match the first card in the stack for initial load
      setState(() => cardName = visibleCards[0]);
    }

    if (mounted) {
      ref.read(expenseNotifierProvider.notifier).loadExpenses();
    }

    // Sync any pending bank notifications captured in the native cache queue while app was closed/killed
    final syncedCount = await di.sl<SmsService>().syncPendingNotificationCache(
      manualCards: manualCards,
    );
    if (syncedCount > 0 && mounted) {
      await _loadBankGroups();
      ref.read(expenseNotifierProvider.notifier).loadExpenses();
      _scheduleWidgetUpdate();
      _showCustomSyncToast(count: syncedCount);
    }

    if (AppUpdateService.isUpdateSupported) {
      _checkForAppUpdate();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (mounted) {
        _scheduleWidgetUpdate();
        final status = await di.sl<SmsService>().checkListenerStatus();
        final isGranted = status['isGranted'] ?? false;
        final isConnected = status['isConnected'] ?? false;

        if ((!isGranted || !isConnected) && mounted) {
          _showNotificationPermissionDialog(
            isDisconnectedOnly: isGranted && !isConnected,
          );
        }
        Future.delayed(const Duration(milliseconds: 150), () {
          if (mounted) {
            _scrollToMonth(selectedMonth);
          }
        });
      }
    });
  }

  void _showNotificationPermissionDialog({bool isDisconnectedOnly = false}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(
              Icons.notifications_active_rounded,
              color: Color(0xFF10B981),
            ),
            const SizedBox(width: 10),
            Text(
              isDisconnectedOnly ? 'Re-enable Auto Sync' : 'Enable Auto Sync',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Text(
          isDisconnectedOnly
              ? 'Android OS suspended the background Notification Listener service for Spender Pro. Please tap "TOGGLE ACCESS", turn Notification Access OFF and back ON to re-enable 24/7 background payment sync.'
              : 'To automatically sync bank payments & update your Home Screen Widget in real-time (even when the app is closed), please enable Notification Access & Autostart in Android settings.',
          style: const TextStyle(fontSize: 14, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await di.sl<SmsService>().openAutostartSettings();
            },
            child: const Text(
              'AUTOSTART',
              style: TextStyle(
                color: Colors.blue,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () async {
              Navigator.pop(context);
              await di.sl<SmsService>().requestNotificationListenerPermission();
            },
            child: Text(
              isDisconnectedOnly ? 'TOGGLE ACCESS' : 'ENABLE NOW',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _scrollToMonth(int index) {
    if (!_monthScrollController.hasClients) return;

    const double itemWidth = 85.0;
    const double itemMargin = 8.0;
    const double itemSpace = itemWidth + itemMargin;
    final double viewportWidth = MediaQuery.of(context).size.width - 50.0;

    double targetOffset =
        (index * itemSpace) + (itemWidth / 2) - (viewportWidth / 2);

    final maxScroll = _monthScrollController.position.maxScrollExtent;
    final minScroll = _monthScrollController.position.minScrollExtent;
    targetOffset = targetOffset.clamp(minScroll, maxScroll);

    _monthScrollController.animateTo(
      targetOffset,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOutCubic,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _widgetUpdateDebounceTimer?.cancel();
    _monthScrollController.dispose();
    _analyticsPageController.dispose();
    super.dispose();
  }

  String? _getGroupForExpense(Expense expense) {
    if (transactionGroups.containsKey(expense.id)) {
      return transactionGroups[expense.id];
    }
    final normalizedName = expense.name.trim().toUpperCase();
    return categoryGroups[normalizedName];
  }

  bool _isWarningEnabledForMonth(ExpenseState state, int monthIndex) {
    if (state is! ExpenseLoaded) return false;
    if (!(cardBudgetEnabled[cardName] ?? true)) return false;
    final cardBoundary = cardBoundaries[cardName];
    if (cardBoundary == null || cardBoundary <= 0) return false;
    final cardDueDateVal = cardDueDates[cardName];

    final filteredForMonth = state.data.expenses.where((expense) {
      if (isDueDateFiltered && cardDueDateVal != null) {
        final endDate = DateTime(
          DateTime.now().year,
          monthIndex + 1,
          cardDueDateVal.day,
        );
        final startDate = DateTime(
          endDate.year,
          endDate.month - 1,
          endDate.day,
        );
        bool withinRange =
            (expense.date.isAfter(startDate) ||
                expense.date.isAtSameMomentAs(startDate)) &&
            (expense.date.isBefore(endDate) ||
                expense.date.isAtSameMomentAs(endDate));
        bool matchesBank =
            cardName.isEmpty ||
            expense.bank.toUpperCase().contains(cardName.toUpperCase()) ||
            cardName.toUpperCase().contains(expense.bank.toUpperCase());
        bool isSpending =
            (expense.type == 'spent' || expense.type == 'debited') &&
            _getGroupForExpense(expense) != 'Unread';
        return withinRange && matchesBank && isSpending;
      }
      bool matchesMonth =
          expense.date.month == (monthIndex + 1) &&
          expense.date.year == DateTime.now().year;
      bool matchesBank =
          cardName.isEmpty ||
          expense.bank.toUpperCase().contains(cardName.toUpperCase()) ||
          cardName.toUpperCase().contains(expense.bank.toUpperCase());
      bool isSpending =
          (expense.type == 'spent' || expense.type == 'debited') &&
          _getGroupForExpense(expense) != 'Unread';
      return matchesMonth && matchesBank && isSpending;
    }).toList();

    final currentTotal = filteredForMonth.fold(
      0.0,
      (sum, item) => sum + item.amount,
    );
    return currentTotal >= cardBoundary;
  }

  Future<void> _syncSms() async {
    if (_isSyncing) return;
    setState(() => _isSyncing = true);
    try {
      // 1. Sync any pending background notification cache
      final notifCount = await di.sl<SmsService>().syncPendingNotificationCache(
        manualCards: manualCards,
      );

      // 2. Read and sync SMS messages from phone message folder
      final smsCount = await di.sl<SmsService>().readAndPrintSms(
        targetMonth: selectedMonth + 1,
        targetYear: DateTime.now().year,
        manualCards: manualCards,
      );

      final totalCount = notifCount + smsCount;

      await _loadBankGroups();
      if (mounted) {
        ref.read(expenseNotifierProvider.notifier).loadExpenses();
        _scheduleWidgetUpdate();
        _showCustomSyncToast(count: totalCount > 0 ? totalCount : null);
      }
    } catch (e) {
      debugPrint('Error during _syncSms: $e');
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  Future<void> _loadBankGroups() async {
    List<BankSmsGroup> groups = [];
    try {
      final expenseData = await di.sl<ExpenseRepository>().getExpenses().first;
      final allExpenses = expenseData.expenses;

      // Automatically purge any previously stored expenses that are not from valid bank cards,
      // or that do not have valid financial transaction types (spent / debited / credited),
      // or that are declined / failed / card-ending noise items
      final invalidExpenses = allExpenses.where((e) {
        final bankName = normalizeBankName(e.bank, body: e.name);
        final isValidCard = isValidBankCardName(bankName, manualCards: manualCards);
        final hasValidType = e.type == 'spent' || e.type == 'debited' || e.type == 'credited';
        final isDeclinedOrCardNoise = isCardEndingOrDeclinedMerchant(e.name) ||
            isDeclinedOrFailedText(e.name) ||
            isStatementOrBillText(e.name);
        return !isValidCard || !hasValidType || isDeclinedOrCardNoise;
      }).toList();
      if (invalidExpenses.isNotEmpty) {
        for (final inv in invalidExpenses) {
          await di.sl<ExpenseRepository>().deleteExpense(inv.id);
        }
      }

      // Group valid saved expenses by bank/card name
      final Map<String, List<BankSmsEntry>> groupedByBank = {};

      for (final e in allExpenses) {
        final bankName = normalizeBankName(e.bank, body: e.name);
        if (!isValidBankCardName(bankName, manualCards: manualCards)) continue;
        if (e.type != 'spent' && e.type != 'debited' && e.type != 'credited') continue;
        if (isCardEndingOrDeclinedMerchant(e.name) ||
            isDeclinedOrFailedText(e.name) ||
            isStatementOrBillText(e.name)) continue;

        if (!groupedByBank.containsKey(bankName)) {
          groupedByBank[bankName] = [];
        }
        groupedByBank[bankName]!.add(
          BankSmsEntry(
            sender: bankName,
            body: '${e.name} - ₹${e.amount}',
            amount: e.amount,
            date: e.date,
            type: e.type == 'credited' ? 'bank_credited' : 'credit_card_spent',
          ),
        );
      }

      // Include manual cards if not already present
      for (final entry in manualCards.entries) {
        final normalizedManual = normalizeBankName(entry.key);
        if (isValidBankCardName(normalizedManual, manualCards: manualCards)) {
          if (!groupedByBank.containsKey(normalizedManual)) {
            groupedByBank[normalizedManual] = [];
          }
        }
      }

      // Include all configured active cards from visibleCards only if valid and they have transactions or are manual cards
      for (final card in visibleCards) {
        final normalizedCard = normalizeBankName(card);
        if (isValidBankCardName(normalizedCard, manualCards: manualCards)) {
          if (groupedByBank.containsKey(normalizedCard) ||
              manualCards.containsKey(card) ||
              manualCards.containsKey(normalizedCard)) {
            if (!groupedByBank.containsKey(normalizedCard)) {
              groupedByBank[normalizedCard] = [];
            }
          }
        }
      }

      groups = groupedByBank.entries
          .map((e) {
            final hasCC =
                e.key.toUpperCase().contains('CARD') ||
                e.key.toUpperCase().contains('SBI') ||
                e.key.toUpperCase().contains('HDFC') ||
                e.key.toUpperCase().contains('AXIS');
            return BankSmsGroup(
              type: hasCC ? 'credit_card' : 'bank',
              label: e.key,
              emoji: '',
              entries: e.value,
            );
          })
          .where((g) =>
              isValidBankCardName(g.label, manualCards: manualCards) &&
              !_isCardDeleted(g.label) &&
              (g.entries.isNotEmpty || manualCards.containsKey(g.label)))
          .toList();
    } catch (e) {
      debugPrint('Error loading bank groups from notification expenses: $e');
    }

    bool shouldSave = false;
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey('disabledCards') && prefs.containsKey('visibleCards')) {
      for (final g in groups) {
        final isVis = visibleCards.contains(g.label) ||
            visibleCards.contains(normalizeBankName(g.label));
        if (!isVis && !_isCardDeleted(g.label)) {
          disabledCards.add(g.label);
          disabledCards.add(normalizeBankName(g.label));
          shouldSave = true;
        }
      }
    }

    setState(() {
      _bankGroups = groups;

      // Clean visibleCards to remove any non-bank cards or cards without transactions
      final validCardLabels = groups.map((g) => g.label).toSet();
      final cleanVisible = visibleCards
          .map((c) => normalizeBankName(c))
          .where((c) =>
              isValidBankCardName(c, manualCards: manualCards) &&
              !_isCardDeleted(c) &&
              !_isCardDisabled(c) &&
              (validCardLabels.contains(c) || manualCards.containsKey(c)))
          .toSet()
          .toList();
      if (cleanVisible.length != visibleCards.length) {
        shouldSave = true;
      }
      visibleCards = cleanVisible;

      if (_tempVisibleCards != null) {
        _tempVisibleCards = _tempVisibleCards!
            .map((c) => normalizeBankName(c))
            .where((c) =>
                isValidBankCardName(c, manualCards: manualCards) &&
                !_isCardDeleted(c) &&
                !_isCardDisabled(c) &&
                (validCardLabels.contains(c) || manualCards.containsKey(c)))
            .toSet()
            .toList();
      }

      // Auto-add newly discovered clean bank card IDs/names into visibleCards filters and auto-save
      // DO NOT auto-enable cards that were explicitly disabled by the user
      for (final g in groups) {
        final isTempDisabled = _tempDisabledCards?.contains(g.label) ?? false;
        final isTempExcluded =
            _tempVisibleCards != null && !_tempVisibleCards!.contains(g.label);
        if (!visibleCards.contains(g.label) &&
            !_isCardDeleted(g.label) &&
            !_isCardDisabled(g.label) &&
            !isTempDisabled &&
            !isTempExcluded &&
            (g.entries.isNotEmpty || manualCards.containsKey(g.label))) {
          visibleCards.add(g.label);
          shouldSave = true;
        }
      }

      if ((cardName.isEmpty || !visibleCards.contains(cardName)) &&
          visibleCards.isNotEmpty) {
        cardName = visibleCards[0];
        shouldSave = true;
      }
    });

    if (shouldSave) {
      await _saveSettings();
    }
  }

  Widget _buildTempConfigureTab(StateSetter setDrawerState) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildNotificationPermissionCard(setDrawerState),
          if (SmsService.isSmsSupported)
            _buildSmsPermissionCard(setDrawerState),
          if (AppUpdateService.isUpdateSupported)
            _buildAppUpdateCard(setDrawerState),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Manage Cards',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.5,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Toggle card visibility or add manual cards',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: () =>
                    _showAddManualCardDialog(context, setDrawerState),
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text(
                  'Add Card',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          if (_bankGroups.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Column(
                  children: [
                    Icon(
                      Icons.credit_card_off_outlined,
                      size: 48,
                      color: Colors.grey.shade300,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'No cards available. Tap "Add Card" to add one.',
                      style: TextStyle(color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          else
            ..._bankGroups
                .where((g) => !_isCardDeleted(g.label))
                .map((group) {
              final isSelected = _tempVisibleCards!.contains(group.label);

              IconData bankIcon = Icons.account_balance_wallet_outlined;
              if (group.label.toUpperCase().contains('SBI')) {
                bankIcon = Icons.account_balance_outlined;
              }
              if (group.label.toUpperCase().contains('AXIS')) {
                bankIcon = Icons.credit_card_outlined;
              }
              if (group.label.toUpperCase().contains('HDFC')) {
                bankIcon = Icons.payments_outlined;
              }

              final isManual = manualCards.containsKey(group.label);

              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.white
                      : Colors.grey.shade50.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected
                        ? Colors.black.withOpacity(0.1)
                        : Colors.grey.shade200,
                    width: 0.8,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.03),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ]
                      : [],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Colors.blue.shade50
                            : Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Icon(
                        bankIcon,
                        color: isSelected ? Colors.black : Colors.grey.shade600,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            group.label,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: isSelected
                                  ? Colors.black
                                  : Colors.grey.shade600,
                            ),
                          ),
                          if (isManual)
                            Text(
                              'Msg ID: ${manualCards[group.label]}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.blue.shade700,
                              ),
                            )
                          else
                            Text(
                              isSelected
                                  ? 'Active on dashboard'
                                  : 'Hidden from view',
                              style: TextStyle(
                                fontSize: 11,
                                color: isSelected
                                    ? Colors.blue.shade700
                                    : Colors.grey.shade500,
                              ),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        color: Colors.redAccent,
                        size: 20,
                      ),
                      tooltip: 'Delete Card',
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => Dialog(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                            elevation: 12,
                            backgroundColor: Colors.white,
                            child: Padding(
                              padding: const EdgeInsets.all(22),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 56,
                                    height: 56,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFEF2F2),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: const Color(0xFFFCA5A5),
                                        width: 1.2,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(
                                            0xFFEF4444,
                                          ).withValues(alpha: 0.15),
                                          blurRadius: 12,
                                          offset: const Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: const Icon(
                                      Icons.delete_forever_rounded,
                                      color: Color(0xFFEF4444),
                                      size: 28,
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  const Text(
                                    'Delete Bank Card',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF0F172A),
                                      letterSpacing: -0.3,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF8FAFC),
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: const Color(0xFFE2E8F0),
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.credit_card_rounded,
                                          size: 14,
                                          color: Color(0xFF64748B),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          group.label,
                                          style: const TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: Color(0xFF334155),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  const Text(
                                    'Are you sure you want to delete this card? This will remove it permanently from your dashboard and card settings.',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      height: 1.4,
                                      color: Color(0xFF64748B),
                                    ),
                                  ),
                                  const SizedBox(height: 22),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: OutlinedButton(
                                          style: OutlinedButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 12,
                                            ),
                                            side: BorderSide(
                                              color: Colors.grey.shade300,
                                            ),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                            ),
                                          ),
                                          onPressed: () =>
                                              Navigator.pop(ctx, false),
                                          child: const Text(
                                            'Cancel',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                              color: Color(0xFF475569),
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: ElevatedButton(
                                          style: ElevatedButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 12,
                                            ),
                                            backgroundColor: const Color(
                                              0xFFEF4444,
                                            ),
                                            elevation: 4,
                                            shadowColor: const Color(
                                              0xFFEF4444,
                                            ).withValues(alpha: 0.4),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                            ),
                                          ),
                                          onPressed: () =>
                                              Navigator.pop(ctx, true),
                                          child: const Text(
                                            'Delete',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: Colors.white,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                        if (confirm == true) {
                          final cardToDelete = group.label;
                          final normCardToDelete = normalizeBankName(cardToDelete);

                          // Add to deletedCards set so auto-discovery won't re-add it
                          deletedCards.add(cardToDelete);
                          deletedCards.add(normCardToDelete);
                          deletedCards.add(cardToDelete.toUpperCase());
                          deletedCards.add(normCardToDelete.toUpperCase());

                          // Delete all expenses belonging to this card from Hive and Riverpod state
                          final state = ref.read(expenseNotifierProvider);
                          if (state is ExpenseLoaded) {
                            final toDelete = state.data.expenses.where((e) {
                              final bName = normalizeBankName(e.bank, body: e.name);
                              return _isCardDeleted(e.bank) ||
                                  _isCardDeleted(bName) ||
                                  bName.toUpperCase() == cardToDelete.toUpperCase() ||
                                  bName.toUpperCase() == normCardToDelete.toUpperCase() ||
                                  e.bank.toUpperCase() == cardToDelete.toUpperCase() ||
                                  e.bank.toUpperCase() == normCardToDelete.toUpperCase() ||
                                  (e.bank.isNotEmpty &&
                                      (e.bank.toUpperCase().contains(cardToDelete.toUpperCase()) ||
                                          cardToDelete.toUpperCase().contains(e.bank.toUpperCase())));
                            }).toList();

                            for (final exp in toDelete) {
                              ref.read(expenseNotifierProvider.notifier).deleteExpense(exp.id);
                            }
                          }

                          setState(() {
                            manualCards.removeWhere((k, v) => _isCardDeleted(k));

                            _bankGroups.removeWhere((g) => _isCardDeleted(g.label));

                            visibleCards.removeWhere((c) => _isCardDeleted(c));
                            disabledCards.removeWhere((c) => _isCardDeleted(c));

                            _tempVisibleCards?.removeWhere((c) => _isCardDeleted(c));
                            _tempDisabledCards?.removeWhere((c) => _isCardDeleted(c));

                            cardLimits.removeWhere((k, v) => _isCardDeleted(k));
                            _tempCardLimits?.removeWhere((k, v) => _isCardDeleted(k));

                            cardBoundaries.removeWhere((k, v) => _isCardDeleted(k));
                            _tempCardBoundaries?.removeWhere((k, v) => _isCardDeleted(k));

                            cardBudgetEnabled.removeWhere((k, v) => _isCardDeleted(k));
                            _tempCardBudgetEnabled?.removeWhere((k, v) => _isCardDeleted(k));

                            isCreditCardOverrides.removeWhere((k, v) => _isCardDeleted(k));
                            _tempIsCreditCardOverrides?.removeWhere((k, v) => _isCardDeleted(k));

                            hideCreditDataOverrides.removeWhere((k, v) => _isCardDeleted(k));
                            _tempHideCreditData?.removeWhere((k, v) => _isCardDeleted(k));

                            cardDueDates.removeWhere((k, v) => _isCardDeleted(k));
                            _tempCardDueDates?.removeWhere((k, v) => _isCardDeleted(k));

                            includeInTotalBudget.removeWhere((k, v) => _isCardDeleted(k));
                            _tempIncludeInTotalBudget?.removeWhere((k, v) => _isCardDeleted(k));

                            cardThemes.removeWhere((k, v) => _isCardDeleted(k));
                            _tempCardThemes?.removeWhere((k, v) => _isCardDeleted(k));

                            if (_isCardDeleted(cardName)) {
                              cardName = visibleCards.isNotEmpty ? visibleCards.first : '';
                            }

                            if (_tempEditingCardName != null && _isCardDeleted(_tempEditingCardName!)) {
                              _tempEditingCardName =
                                  _tempVisibleCards != null && _tempVisibleCards!.isNotEmpty
                                      ? _tempVisibleCards!.first
                                      : null;
                            }
                          });

                          setDrawerState(() {});
                          await _saveSettings();
                        }
                      },
                    ),
                    Switch.adaptive(
                      value: isSelected,
                      activeColor: getThemeColor(group.label),
                      trackColor: const WidgetStatePropertyAll(Colors.white),
                      trackOutlineColor: WidgetStatePropertyAll(
                        Colors.grey.shade300,
                      ),
                      activeThumbColor: Colors.black,
                      inactiveTrackColor: Colors.white,
                      onChanged: (selected) {
                        setDrawerState(() {
                          if (selected) {
                            _tempVisibleCards!.add(group.label);
                            _tempDisabledCards?.removeWhere((dc) =>
                                dc.toUpperCase() == group.label.toUpperCase() ||
                                dc.toUpperCase() ==
                                    normalizeBankName(group.label).toUpperCase() ||
                                group.label.toUpperCase().contains(dc.toUpperCase()) ||
                                dc.toUpperCase().contains(group.label.toUpperCase()));
                          } else {
                            _tempVisibleCards!.remove(group.label);
                            _tempDisabledCards ??= {};
                            _tempDisabledCards!.add(group.label);
                            _tempDisabledCards!.add(normalizeBankName(group.label));
                          }
                        });
                      },
                    ),
                  ],
                ),
              );
            }),
          SizedBox(height: MediaQuery.of(context).viewInsets.bottom + 100),
        ],
      ),
    );
  }

  void _showAddManualCardDialog(
    BuildContext context,
    StateSetter setDrawerState,
  ) {
    final TextEditingController cardNameController = TextEditingController();
    final TextEditingController msgIdController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          elevation: 16,
          backgroundColor: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFF1E40AF), Color(0xFF3B82F6)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
                              0xFF2563EB,
                            ).withValues(alpha: 0.35),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.credit_card_rounded,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Add Card Manually',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 19,
                              color: Color(0xFF0F172A),
                              letterSpacing: -0.3,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'Track custom card expenses via SMS',
                            style: TextStyle(
                              fontSize: 12,
                              color: Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: Color(0xFF2563EB),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'CARD NAME',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF475569),
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: cardNameController,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF0F172A),
                        ),
                        decoration: InputDecoration(
                          hintText: 'e.g. HDFC Millennia, Axis Card',
                          hintStyle: TextStyle(
                            color: Colors.grey.shade400,
                            fontSize: 13,
                          ),
                          prefixIcon: const Icon(
                            Icons.credit_card_outlined,
                            color: Color(0xFF2563EB),
                            size: 20,
                          ),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(
                              color: Color(0xFFE2E8F0),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(
                              color: Color(0xFF2563EB),
                              width: 2,
                            ),
                          ),
                          errorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(
                              color: Color(0xFFEF4444),
                            ),
                          ),
                          focusedErrorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(
                              color: Color(0xFFEF4444),
                              width: 2,
                            ),
                          ),
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Please enter a card name';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: Color(0xFF2563EB),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          const Text(
                            'MSG ID / SENDER ID',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF475569),
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: msgIdController,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF0F172A),
                        ),
                        decoration: InputDecoration(
                          hintText: 'e.g. HDFCBK, SBICRD, 12345',
                          hintStyle: TextStyle(
                            color: Colors.grey.shade400,
                            fontSize: 13,
                          ),
                          prefixIcon: const Icon(
                            Icons.sms_outlined,
                            color: Color(0xFF2563EB),
                            size: 20,
                          ),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(
                              color: Color(0xFFE2E8F0),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(
                              color: Color(0xFF2563EB),
                              width: 2,
                            ),
                          ),
                          errorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(
                              color: Color(0xFFEF4444),
                            ),
                          ),
                          focusedErrorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(
                              color: Color(0xFFEF4444),
                              width: 2,
                            ),
                          ),
                        ),
                        validator: (val) {
                          if (val == null || val.trim().isEmpty) {
                            return 'Please enter a message ID or sender ID';
                          }
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 26),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: const BorderSide(color: Color(0xFFE2E8F0)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(
                            color: Color(0xFF64748B),
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFF0F172A,
                              ).withValues(alpha: 0.3),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ElevatedButton(
                          onPressed: () async {
                            if (formKey.currentState?.validate() ?? false) {
                              final newCardName = cardNameController.text
                                  .trim();
                              final newMsgId = msgIdController.text.trim();

                              setState(() {
                                manualCards[newCardName] = newMsgId;

                                if (!_bankGroups.any(
                                  (g) =>
                                      g.label.toLowerCase() ==
                                      newCardName.toLowerCase(),
                                )) {
                                  _bankGroups.add(
                                    BankSmsGroup(
                                      type: 'credit_card',
                                      label: newCardName,
                                      emoji: '',
                                      entries: [],
                                    ),
                                  );
                                }

                                deletedCards.removeWhere((dc) =>
                                    dc.toUpperCase() == newCardName.toUpperCase() ||
                                    dc.toUpperCase() == normalizeBankName(newCardName).toUpperCase() ||
                                    newCardName.toUpperCase().contains(dc.toUpperCase()) ||
                                    dc.toUpperCase().contains(newCardName.toUpperCase()));

                                disabledCards.removeWhere((dc) =>
                                    dc.toUpperCase() == newCardName.toUpperCase() ||
                                    dc.toUpperCase() == normalizeBankName(newCardName).toUpperCase() ||
                                    newCardName.toUpperCase().contains(dc.toUpperCase()) ||
                                    dc.toUpperCase().contains(newCardName.toUpperCase()));
                                _tempDisabledCards?.removeWhere((dc) =>
                                    dc.toUpperCase() == newCardName.toUpperCase() ||
                                    dc.toUpperCase() == normalizeBankName(newCardName).toUpperCase() ||
                                    newCardName.toUpperCase().contains(dc.toUpperCase()) ||
                                    dc.toUpperCase().contains(newCardName.toUpperCase()));

                                if (!visibleCards.contains(newCardName)) {
                                  visibleCards.add(newCardName);
                                }
                                if (_tempVisibleCards != null &&
                                    !_tempVisibleCards!.contains(newCardName)) {
                                  _tempVisibleCards!.add(newCardName);
                                }

                                _tempCardLimits ??= {};
                                _tempCardLimits![newCardName] = maxValue;
                                _tempCardBoundaries ??= {};
                                _tempIsCreditCardOverrides ??= {};
                                _tempIsCreditCardOverrides![newCardName] = true;
                                _tempCardBudgetEnabled ??= {};
                                _tempCardBudgetEnabled![newCardName] = true;
                                cardBudgetEnabled[newCardName] = true;
                                _tempIncludeInTotalBudget ??= {};
                                _tempIncludeInTotalBudget![newCardName] = true;
                                _tempCardThemes ??= {};
                                _tempCardThemes![newCardName] = 'Ocean';
                                cardThemes[newCardName] = 'Ocean';
                              });

                              setDrawerState(() {});
                              await _saveSettings();

                              if (context.mounted) {
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      'Card "$newCardName" added successfully',
                                    ),
                                    behavior: SnackBarBehavior.floating,
                                    backgroundColor: const Color(0xFF0F172A),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                );
                              }
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.add_rounded,
                                size: 18,
                                color: Colors.white,
                              ),
                              SizedBox(width: 6),
                              Text(
                                'Add Card',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }


  Widget _buildNotificationPermissionCard(StateSetter setDrawerState) {
    return FutureBuilder<bool>(
      future: di.sl<SmsService>().isNotificationListenerPermissionGranted(),
      builder: (context, snapshot) {
        final isGranted = snapshot.data ?? false;
        return Container(
          margin: const EdgeInsets.only(bottom: 20),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isGranted ? Colors.green.shade50 : Colors.blue.shade50,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isGranted ? Colors.green.shade200 : Colors.blue.shade200,
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isGranted
                          ? Colors.green.shade100
                          : Colors.blue.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isGranted
                          ? Icons.notifications_active_rounded
                          : Icons.notifications_none_rounded,
                      color: isGranted
                          ? Colors.green.shade800
                          : Colors.blue.shade800,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Notification Auto-Sync',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: isGranted
                                ? Colors.green.shade900
                                : Colors.blue.shade900,
                          ),
                        ),
                        Text(
                          isGranted
                              ? 'Active: Automatically logs expenses from bank notifications'
                              : 'Enable to auto-sync transactions when bank notifications arrive',
                          style: TextStyle(
                            fontSize: 11,
                            color: isGranted
                                ? Colors.green.shade700
                                : Colors.blue.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (!isGranted) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _showNotificationAccessDisclosure(
                      context,
                      setDrawerState,
                    ),
                    icon: const Icon(Icons.security_rounded, size: 16),
                    label: const Text(
                      'Enable Notification Access',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade800,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildSmsPermissionCard(StateSetter setDrawerState) {
    return FutureBuilder<bool>(
      future: di.sl<SmsService>().isSmsPermissionGranted(),
      builder: (context, snapshot) {
        final isGranted = snapshot.data ?? false;
        return Container(
          margin: const EdgeInsets.only(bottom: 20),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isGranted ? Colors.teal.shade50 : Colors.indigo.shade50,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isGranted ? Colors.teal.shade200 : Colors.indigo.shade200,
              width: 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isGranted
                          ? Colors.teal.shade100
                          : Colors.indigo.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isGranted
                          ? Icons.sms_rounded
                          : Icons.sms_outlined,
                      color: isGranted
                          ? Colors.teal.shade800
                          : Colors.indigo.shade800,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SMS Messages Sync',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: isGranted
                                ? Colors.teal.shade900
                                : Colors.indigo.shade900,
                          ),
                        ),
                        Text(
                          isGranted
                              ? 'Active: Syncs transactions from phone messages folder'
                              : 'Grant SMS permission to import & sync bank messages',
                          style: TextStyle(
                            fontSize: 11,
                            color: isGranted
                                ? Colors.teal.shade700
                                : Colors.indigo.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    if (!isGranted) {
                      final granted = await di.sl<SmsService>().requestSmsPermission();
                      setDrawerState(() {});
                      if (granted) {
                        await _syncSms();
                      }
                    } else {
                      await _syncSms();
                    }
                  },
                  icon: Icon(
                    isGranted ? Icons.sync_rounded : Icons.mark_email_read_rounded,
                    size: 16,
                  ),
                  label: Text(
                    isGranted ? 'Sync Messages Now' : 'Grant SMS Permission & Sync',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isGranted
                        ? Colors.teal.shade800
                        : Colors.indigo.shade800,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAppUpdateCard(StateSetter setDrawerState) {
    final info = _latestUpdateInfo;
    final hasUpdate = info?.hasUpdate == true;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: hasUpdate ? const Color(0xFFFFFBEB) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: hasUpdate ? const Color(0xFFFCD34D) : const Color(0xFFE2E8F0),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: hasUpdate
                ? const Color(0xFFF59E0B).withValues(alpha: 0.1)
                : Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: hasUpdate
                      ? const Color(0xFFFEF3C7)
                      : const Color(0xFFE2E8F0),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  hasUpdate
                      ? Icons.system_update_rounded
                      : Icons.verified_rounded,
                  color: hasUpdate
                      ? const Color(0xFFD97706)
                      : const Color(0xFF475569),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasUpdate
                          ? 'Update Available (v${info!.latestVersion})'
                          : 'Spender Pro (GitHub Variant)',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                        color: hasUpdate
                            ? const Color(0xFF92400E)
                            : const Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      info != null
                          ? (hasUpdate
                              ? 'Installed: v${info.currentVersion} • Tap Update to install'
                              : 'Installed: v${info.currentVersion} • Up to date')
                          : 'Installed: v1.0.1 • Full Permissions',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: hasUpdate
                            ? const Color(0xFFB45309)
                            : const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isCheckingUpdate
                  ? null
                  : () async {
                      if (hasUpdate && info != null) {
                        di.sl<AppUpdateService>().launchUpdate(info.downloadUrl);
                      } else {
                        await _checkForAppUpdate(showToastIfUpToDate: true);
                        setDrawerState(() {});
                      }
                    },
              icon: _isCheckingUpdate
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Icon(
                      hasUpdate
                          ? Icons.download_rounded
                          : Icons.refresh_rounded,
                      size: 16,
                    ),
              label: Text(
                _isCheckingUpdate
                    ? 'Checking for updates...'
                    : hasUpdate
                        ? 'Update to v${info!.latestVersion}'
                        : 'Check for Updates',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: hasUpdate
                    ? const Color(0xFF2563EB)
                    : const Color(0xFF0F172A),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppUpdateBanner() {
    if (_availableUpdate == null || _isUpdateDismissed) return const SizedBox.shrink();
    final update = _availableUpdate!;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1E3A8A), Color(0xFF2563EB)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2563EB).withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.system_update_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Text(
                      'Update Available',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade400,
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        'v${update.latestVersion}',
                        style: const TextStyle(
                          color: Colors.black87,
                          fontWeight: FontWeight.bold,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'A newer GitHub release is available.',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          ElevatedButton(
            onPressed: () {
              HapticFeedback.lightImpact();
              di.sl<AppUpdateService>().launchUpdate(update.downloadUrl);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF1E3A8A),
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              minimumSize: Size.zero,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Update',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 11,
              ),
            ),
          ),
          const SizedBox(width: 2),
          InkWell(
            onTap: () {
              setState(() => _isUpdateDismissed = true);
            },
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(
                Icons.close_rounded,
                color: Colors.white.withValues(alpha: 0.7),
                size: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _checkForAppUpdate({bool showToastIfUpToDate = false}) async {
    if (!AppUpdateService.isUpdateSupported) return;
    if (mounted) setState(() => _isCheckingUpdate = true);
    try {
      final update = await di.sl<AppUpdateService>().checkForUpdate();
      if (mounted) {
        setState(() {
          _latestUpdateInfo = update;
          _availableUpdate = update?.hasUpdate == true ? update : null;
          _isCheckingUpdate = false;
        });
        if (update?.hasUpdate == true) {
          if (showToastIfUpToDate) {
            _showUpdateDialog(update!);
          }
        } else if (showToastIfUpToDate) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
                  SizedBox(width: 10),
                  Text('You are using the latest version of Spender Pro'),
                ],
              ),
              backgroundColor: Colors.teal.shade700,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          );
        }
      }
    } catch (_) {
      if (mounted) setState(() => _isCheckingUpdate = false);
    }
  }

  void _showUpdateDialog(AppUpdateInfo update) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.system_update_rounded, color: Colors.blue.shade700, size: 24),
            ),
            const SizedBox(width: 12),
            const Text('Update Available', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'A new version (${update.latestVersion}) is available. Current installed version: ${update.currentVersion}.',
              style: const TextStyle(fontSize: 13, height: 1.4),
            ),
            if (update.releaseNotes.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text('Changelog:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
              const SizedBox(height: 4),
              Container(
                constraints: const BoxConstraints(maxHeight: 120),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    update.releaseNotes,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade800),
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Later', style: TextStyle(color: Colors.grey.shade600)),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              di.sl<AppUpdateService>().launchUpdate(update.downloadUrl);
            },
            icon: const Icon(Icons.download_rounded, size: 16),
            label: const Text('Update Now'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2563EB),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }

  void _showNotificationAccessDisclosure(
    BuildContext context,
    StateSetter setDrawerState,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        elevation: 16,
        backgroundColor: Colors.white,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF1E40AF), Color(0xFF3B82F6)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF2563EB).withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.privacy_tip_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Notification Access',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 19,
                  color: Color(0xFF0F172A),
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Spender Pro processes status bar bank notifications locally on your device to automatically detect and log your bank transactions and credit card expenses.\n\nNo notification data is uploaded to remote servers.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: const BorderSide(color: Color(0xFFE2E8F0)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          color: Color(0xFF64748B),
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFF0F172A),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
                              0xFF0F172A,
                            ).withValues(alpha: 0.3),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: ElevatedButton(
                        onPressed: () async {
                          Navigator.pop(ctx);
                          await di
                              .sl<SmsService>()
                              .requestNotificationListenerPermission();
                          setDrawerState(() {});
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          'Open Settings',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<PieChartSectionData> _getAllocationSections(double limit) {
    List<PieChartSectionData> sections = [];
    double totalAllocated = 0;

    groupLimits.forEach((name, gLimit) {
      if (gLimit > 0) {
        totalAllocated += gLimit;
        sections.add(
          PieChartSectionData(
            color: Color(groupColors[name] ?? Colors.blue.value),
            value: gLimit,
            radius: 35,
            showTitle: false,
          ),
        );
      }
    });

    final remaining = limit - totalAllocated;
    if (remaining > 0) {
      sections.add(
        PieChartSectionData(
          color: Colors.grey.withOpacity(0.1),
          value: remaining,
          radius: 30,
          showTitle: false,
        ),
      );
    }
    if (sections.isEmpty) {
      sections.add(
        PieChartSectionData(
          color: Colors.grey.withOpacity(0.05),
          value: 1,
          radius: 30,
          showTitle: false,
        ),
      );
    }
    return sections;
  }

  Widget _buildSection(String title, Widget child, {Widget? trailing}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8, right: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title.toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade600,
                  letterSpacing: 1.2,
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
        ),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade100),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: child,
            ),
          ),
        ),
        SizedBox(height: 10),
      ],
    );
  }

  Widget _buildTempSettingsTab(StateSetter setDrawerState, ExpenseState state) {
    final targetCard = _tempEditingCardName ?? cardName;
    final isBudgetEnabled =
        _tempCardBudgetEnabled?[targetCard] ??
        cardBudgetEnabled[targetCard] ??
        true;
    final currentCardLimit =
        _tempCardLimits![targetCard] ??
        (state is ExpenseLoaded ? state.data.limit : maxValue);
    final defaultLimit = (state is ExpenseLoaded ? state.data.limit : maxValue);
    final defaultBoundary = defaultLimit * 0.8;

    _tempLimitControllers[targetCard] ??= TextEditingController(
      text:
          _tempCardLimits![targetCard] != null &&
              _tempCardLimits![targetCard]! > 0
          ? _tempCardLimits![targetCard]!.toStringAsFixed(0)
          : defaultLimit.toStringAsFixed(0),
    );
    _tempBoundaryControllers[targetCard] ??= TextEditingController(
      text:
          _tempCardBoundaries![targetCard] != null &&
              _tempCardBoundaries![targetCard]! > 0
          ? _tempCardBoundaries![targetCard]!.toStringAsFixed(0)
          : '',
    );

    return SingleChildScrollView(
      padding: EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Card Selector Switcher Bar if multiple cards exist
          if (_tempVisibleCards != null && _tempVisibleCards!.length > 1) ...[
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: _tempVisibleCards!.map((card) {
                  final isSelected = card == targetCard;
                  final themeGradients = AppConstants.themeGradients;
                  final cardColors = themeGradients[_tempCardThemes?[card] ?? getCardTheme(card)] ?? themeGradients['Ocean']!;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8, bottom: 14),
                    child: InkWell(
                      onTap: () {
                        setDrawerState(() {
                          _tempEditingCardName = card;
                        });
                      },
                      borderRadius: BorderRadius.circular(14),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isSelected ? const Color(0xFF0F172A) : const Color(0xFFE2E8F0),
                            width: 1,
                          ),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.15),
                                    blurRadius: 8,
                                    offset: const Offset(0, 4),
                                  )
                                ]
                              : [],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: LinearGradient(
                                  colors: cardColors,
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              card,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                color: isSelected ? Colors.white : const Color(0xFF475569),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],

          // Sleek, Classic & Modern Card Header Banner
          Builder(
            builder: (context) {
              final themeGradients = AppConstants.themeGradients;
              final headerGradient = themeGradients[_tempCardThemes?[targetCard] ?? getCardTheme(targetCard)] ?? themeGradients['Ocean']!;
              final isCredit = ((_tempHideCreditData?[targetCard] ?? false) ||
                  (_tempIsCreditCardOverrides?.containsKey(targetCard) ?? false
                      ? _tempIsCreditCardOverrides![targetCard]!
                      : false));

              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [
                      Color(0xFF0F172A),
                      Color(0xFF1E293B),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.12),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.15),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    // Theme Icon Badge
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: headerGradient,
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(11),
                        boxShadow: [
                          BoxShadow(
                            color: headerGradient.last.withValues(alpha: 0.4),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.credit_card_rounded,
                        color: Colors.white,
                        size: 19,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  targetCard,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                    letterSpacing: 0.1,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: (isCredit ? const Color(0xFFF59E0B) : const Color(0xFF10B981)).withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: (isCredit ? const Color(0xFFFBBF24) : const Color(0xFF34D399)).withValues(alpha: 0.4),
                                    width: 0.8,
                                  ),
                                ),
                                child: Text(
                                  isCredit ? 'CREDIT' : 'DEBIT',
                                  style: TextStyle(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w800,
                                    color: isCredit ? const Color(0xFFFDE68A) : const Color(0xFFA7F3D0),
                                    letterSpacing: 0.6,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(
                                Icons.tune_rounded,
                                size: 12,
                                color: Colors.white.withValues(alpha: 0.6),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Card Preferences & Controls',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.white.withValues(alpha: 0.65),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          Padding(
            padding: EdgeInsets.only(left: 2, bottom: 8),
            child: Text(
              'CARD THEME',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade600,
                letterSpacing: 1.2,
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200, width: 0.5),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
              child: Builder(
                builder: (context) {
                  final themeGradients = AppConstants.themeGradients;

                  final currentTheme = getCardTheme(targetCard);

                  return PopupMenuButton<String>(
                    offset: const Offset(0, 60),
                    color: Colors.white,
                    elevation: 8,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                    onSelected: (theme) {
                      setDrawerState(() {
                        _tempCardThemes ??= Map.from(cardThemes);
                        _tempCardThemes![targetCard] = theme;
                      });
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem<String>(
                        enabled: false,
                        padding: EdgeInsets.zero,
                        child: SizedBox(
                          width: 285,
                          height: 380,
                          child: SingleChildScrollView(
                            physics: const BouncingScrollPhysics(),
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Wrap(
                                spacing: 8,
                                runSpacing: 12,
                                children: themeGradients.keys.map((theme) {
                                  final isSelected = currentTheme == theme;
                                  return InkWell(
                                    onTap: () => Navigator.pop(context, theme),
                                    borderRadius: BorderRadius.circular(12),
                                    child: Container(
                                      width: 120, // Forces 2 items per row
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(12),
                                        color: isSelected
                                            ? Colors.grey.shade50
                                            : Colors.transparent,
                                        border: Border.all(
                                          color: isSelected
                                              ? Colors.blue.shade300
                                              : Colors.transparent,
                                          width: 1.5,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Container(
                                            width: 22,
                                            height: 22,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              gradient: LinearGradient(
                                                colors: themeGradients[theme]!,
                                                begin: Alignment.topLeft,
                                                end: Alignment.bottomRight,
                                              ),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: themeGradients[theme]!
                                                      .last
                                                      .withOpacity(0.4),
                                                  blurRadius: 4,
                                                  offset: const Offset(0, 2),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              theme,
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: isSelected
                                                    ? FontWeight.bold
                                                    : FontWeight.w500,
                                                color: Colors.black87,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        color: Colors.white,
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 35,
                            height: 30,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(5),
                              gradient: LinearGradient(
                                colors: themeGradients[currentTheme]!,
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: themeGradients[currentTheme]!.last
                                      .withOpacity(0.4),
                                  blurRadius: 6,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              currentTheme,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 0.5,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                          const Icon(
                            Icons.expand_more_rounded,
                            color: Colors.black54,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 10),
          _buildSection(
            'Budget Control',
            Builder(
              builder: (context) {
                final themeColor = getThemeColor(targetCard);
                return Opacity(
                  opacity: isBudgetEnabled ? 1.0 : 0.45,
                  child: IgnorePointer(
                    ignoring: !isBudgetEnabled,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.account_balance_wallet_outlined,
                                        size: 14,
                                        color: isBudgetEnabled
                                            ? Colors.grey.shade700
                                            : Colors.grey,
                                      ),
                                      const SizedBox(width: 5),
                                      Text(
                                        'Limit',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.grey.shade700,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  TextField(
                                    controller: _tempLimitControllers[targetCard],
                                    enabled: isBudgetEnabled,
                                    keyboardType: TextInputType.number,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.black87,
                                    ),
                                    decoration: InputDecoration(
                                      isDense: true,
                                      prefixText: '₹ ',
                                      prefixStyle: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: themeColor,
                                      ),
                                      hintText: defaultLimit.toStringAsFixed(0),
                                      filled: true,
                                      fillColor: isBudgetEnabled
                                          ? const Color(0xFFF8FAFC)
                                          : Colors.grey.shade100,
                                      contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 12,
                                      ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(
                                          color: Colors.grey.shade200,
                                        ),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(
                                          color: Colors.grey.shade200,
                                        ),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(
                                          color: themeColor,
                                          width: 1.5,
                                        ),
                                      ),
                                    ),
                                    onChanged: (val) {
                                      final limit = double.tryParse(val);
                                      _tempCardLimits![targetCard] =
                                          limit ?? defaultLimit;
                                    },
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.shield_outlined,
                                        size: 14,
                                        color: isBudgetEnabled
                                            ? Colors.grey.shade700
                                            : Colors.grey,
                                      ),
                                      const SizedBox(width: 5),
                                      Text(
                                        'Boundary',
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.grey.shade700,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  TextField(
                                    controller:
                                        _tempBoundaryControllers[targetCard],
                                    enabled: isBudgetEnabled,
                                    keyboardType: TextInputType.number,
                                    style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.black87,
                                    ),
                                    decoration: InputDecoration(
                                      isDense: true,
                                      prefixText: '₹ ',
                                      prefixStyle: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: themeColor,
                                      ),
                                      hintText: '0',
                                      filled: true,
                                      fillColor: isBudgetEnabled
                                          ? const Color(0xFFF8FAFC)
                                          : Colors.grey.shade100,
                                      contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 12,
                                      ),
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(
                                          color: Colors.grey.shade200,
                                        ),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(
                                          color: Colors.grey.shade200,
                                        ),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(12),
                                        borderSide: BorderSide(
                                          color: themeColor,
                                          width: 1.5,
                                        ),
                                      ),
                                    ),
                                    onChanged: (val) {
                                      final bl = double.tryParse(val);
                                      _tempCardBoundaries![targetCard] =
                                          (bl != null && bl > 0) ? bl : 0.0;
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Padding(
                          padding: const EdgeInsets.only(left: 2, bottom: 8),
                          child: Text(
                            'SCHEDULING',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey.shade500,
                              letterSpacing: 1.1,
                            ),
                          ),
                        ),
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: () async {
                              final picked = await showDialog<DateTime>(
                                context: context,
                                builder: (context) => CustomBlueDatePickerDialog(
                                  initialDate:
                                      (_tempCardDueDates![targetCard] ??
                                              DateTime.now())
                                          .isAfter(DateTime.now())
                                      ? DateTime.now()
                                      : (_tempCardDueDates![targetCard] ??
                                            DateTime.now()),
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime.now(),
                                  primaryColor: (AppConstants
                                                  .themeGradients[_tempCardThemes?[targetCard] ??
                                                  getCardTheme(targetCard)] ??
                                              AppConstants.themeGradients['Ocean']!)
                                          .first,
                                ),
                              );
                              if (picked != null) {
                                setDrawerState(
                                  () => _tempCardDueDates![targetCard] = picked,
                                );
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: themeColor.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: themeColor.withValues(alpha: 0.15),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(9),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          themeColor,
                                          themeColor.withValues(alpha: 0.8),
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      ),
                                      borderRadius: BorderRadius.circular(10),
                                      boxShadow: [
                                        BoxShadow(
                                          color: themeColor.withValues(alpha: 0.25),
                                          blurRadius: 6,
                                          offset: const Offset(0, 2),
                                        ),
                                      ],
                                    ),
                                    child: const Icon(
                                      Icons.calendar_month_rounded,
                                      size: 18,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text(
                                          'Billing Due Date',
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.black87,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          _tempCardDueDates![targetCard] == null
                                              ? 'Not set'
                                              : DateFormat('MMMM dd, yyyy').format(
                                                  _tempCardDueDates![targetCard]!,
                                                ),
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                            color: _tempCardDueDates![targetCard] == null
                                                ? Colors.grey.shade500
                                                : themeColor,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                        color: Colors.grey.shade200,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          _tempCardDueDates![targetCard] == null
                                              ? 'Set'
                                              : 'Change',
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                            color: themeColor,
                                          ),
                                        ),
                                        const SizedBox(width: 2),
                                        Icon(
                                          Icons.chevron_right_rounded,
                                          size: 14,
                                          color: themeColor,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Divider(color: Colors.grey.shade200, height: 1),
                        const SizedBox(height: 12),
                        Wrap(
                          alignment: WrapAlignment.spaceBetween,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.visibility_off_outlined,
                                  size: 16,
                                  color: isBudgetEnabled
                                      ? Colors.grey.shade700
                                      : Colors.grey,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'Hide Credit Data',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: isBudgetEnabled
                                        ? Colors.grey.shade800
                                        : Colors.grey,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Transform.scale(
                                  scale: 0.85,
                                  child: Switch.adaptive(
                                    value:
                                        _tempHideCreditData?[targetCard] ?? false,
                                    activeColor: themeColor,
                                    onChanged: isBudgetEnabled
                                        ? (val) {
                                            setDrawerState(() {
                                              _tempHideCreditData![targetCard] =
                                                  val;
                                            });
                                          }
                                        : null,
                                  ),
                                ),
                              ],
                            ),
                            InkWell(
                              borderRadius: BorderRadius.circular(10),
                              onTap: () {
                                setDrawerState(() {
                                  _tempCardLimits![targetCard] = defaultLimit;
                                  _tempCardBoundaries![targetCard] = 0.0;
                                  _tempLimitControllers[targetCard]?.text =
                                      defaultLimit.toStringAsFixed(0);
                                  _tempBoundaryControllers[targetCard]?.text = '';
                                  _tempCardDueDates?.remove(targetCard);
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: Colors.red.shade100,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.restart_alt_rounded,
                                      size: 14,
                                      color: Colors.red.shade700,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Reset Values',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.red.shade700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
            trailing: Transform.scale(
              scale: 0.85,
              child: Switch.adaptive(
                value: isBudgetEnabled,
                activeColor: getThemeColor(targetCard),
                onChanged: (val) {
                  setDrawerState(() {
                    _tempCardBudgetEnabled![targetCard] = val;
                  });
                },
              ),
            ),
          ),
          Builder(
            builder: (context) {
              final currentTheme = getCardTheme(targetCard);
              final themeColor =
                  (AppConstants.themeGradients[currentTheme] ??
                          AppConstants.themeGradients['Ocean']!)
                      .last;

              return _buildSection(
                'Card Behavior',
                Column(
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'Is Credit Card?',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      subtitle: Text(
                        'Toggles credit limit visualization',
                        style: TextStyle(fontSize: 11),
                      ),
                      value: _tempIsCreditCardOverrides![targetCard] ?? false,
                      onChanged: (val) => setDrawerState(() {
                        _tempIsCreditCardOverrides![targetCard] = val;
                        if (val) {
                          _tempCardBudgetEnabled![targetCard] = true;
                        }
                      }),
                      activeThumbColor: themeColor,
                      activeTrackColor: themeColor.withOpacity(0.3),
                      inactiveTrackColor: Colors.grey.shade300,
                    ),
                    const Divider(height: 1, color: Color(0xFFF3F4F6)),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'Include in Total Budget?',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      subtitle: Text(
                        'Include this card\'s limit in total budget',
                        style: TextStyle(fontSize: 11),
                      ),
                      value: _tempIncludeInTotalBudget![targetCard] ?? true,
                      onChanged: (val) => setDrawerState(
                        () => _tempIncludeInTotalBudget![targetCard] =
                            val ?? true,
                      ),
                      activeColor: themeColor,
                      controlAffinity: ListTileControlAffinity.trailing,
                    ),
                  ],
                ),
              );
            },
          ),
          SizedBox(height: MediaQuery.of(context).viewInsets.bottom + 100),
        ],
      ),
    );
  }

  Widget _buildTempBudgetTab(StateSetter setDrawerState, ExpenseState state) {
    final totalCardLimit = visibleCards.fold(0.0, (sum, bank) {
      final isIncluded = _tempIncludeInTotalBudget?[bank] ?? true;
      if (!isIncluded) return sum;
      final limit = _tempCardLimits?[bank] ?? cardLimits[bank] ?? 0;
      return sum + (limit > 0 ? limit : maxValue);
    });
    final totalGroupLimits = groupLimits.values.fold(0.0, (s, v) => s + v);
    final isBudgetExceeded = totalGroupLimits > totalCardLimit;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSection(
            'Budget Display',
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Show Budget on Home Screen',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
              subtitle: const Text(
                'Show overview card and budget summary on home screen',
                style: TextStyle(fontSize: 11),
              ),
              value: _tempShowBudgetOverview ?? showBudgetOverview,
              onChanged: (val) {
                setDrawerState(() {
                  _tempShowBudgetOverview = val;
                });
              },
              activeColor: Colors.black,
              controlAffinity: ListTileControlAffinity.trailing,
            ),
          ),
          const SizedBox(height: 16),
          _buildSection(
            'Budget Allocation',
            Column(
              children: [
                if (isBudgetExceeded)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFEF2F2), Color(0xFFFFF1F1)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: const Color(0xFFFECACA),
                          width: 1.0,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFEF4444).withValues(alpha: 0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEE2E2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(
                              Icons.warning_amber_rounded,
                              color: Color(0xFFDC2626),
                              size: 16,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: RichText(
                              text: TextSpan(
                                style: const TextStyle(
                                  color: Color(0xFF991B1B),
                                  fontSize: 11.5,
                                  height: 1.35,
                                ),
                                children: [
                                  const TextSpan(
                                    text: 'Allocated ',
                                    style: TextStyle(fontWeight: FontWeight.w500),
                                  ),
                                  TextSpan(
                                    text: '₹${totalGroupLimits.toStringAsFixed(0)}',
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  const TextSpan(
                                    text: ' exceeds total budget of ',
                                    style: TextStyle(fontWeight: FontWeight.w500),
                                  ),
                                  TextSpan(
                                    text: '₹${totalCardLimit.toStringAsFixed(0)}',
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                SizedBox(
                  height: 180,
                  child: Row(
                    children: [
                      // Pie Chart Side
                      Expanded(
                        flex: 3,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            PieChart(
                              PieChartData(
                                sectionsSpace: 2,
                                centerSpaceRadius: 40,
                                sections: _getAllocationSections(
                                  totalCardLimit,
                                ),
                              ),
                            ),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Total Budget',
                                  style: TextStyle(
                                    fontSize: 8,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey.shade500,
                                  ),
                                ),
                                Text(
                                  '₹${totalCardLimit.toStringAsFixed(0)}',
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Details Side
                      Expanded(
                        flex: 2,
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'GROUPS',
                                style: TextStyle(
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blue,
                                  letterSpacing: 1,
                                ),
                              ),
                              const SizedBox(height: 8),
                              if (groupLimits.isEmpty)
                                Text(
                                  'None',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: Colors.grey.shade400,
                                  ),
                                )
                              else
                                ...groupLimits.entries
                                    .where((e) => e.value > 0)
                                    .map((e) {
                                      final color = Color(
                                        groupColors[e.key] ?? Colors.blue.value,
                                      );
                                      return Padding(
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 2,
                                        ),
                                        child: Row(
                                          children: [
                                            Container(
                                              width: 6,
                                              height: 6,
                                              decoration: BoxDecoration(
                                                color: color,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                            const SizedBox(width: 6),
                                            Expanded(
                                              child: Text(
                                                e.key,
                                                style: const TextStyle(
                                                  fontSize: 9,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            Text(
                                              '₹${(e.value / 1000).toStringAsFixed(1)}k',
                                              style: TextStyle(
                                                fontSize: 9,
                                                color: Colors.grey.shade600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }),
                              const Divider(height: 12),
                              Row(
                                children: [
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: const BoxDecoration(
                                      color: Colors.green,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  const Expanded(
                                    child: Text(
                                      'FREE',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  Text(
                                    '₹${((totalCardLimit - totalGroupLimits) / 1000).toStringAsFixed(1)}k',
                                    style: const TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(
                  'LABELS & GROUPS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade600,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => _showGroupingDialog(context, targetNames: []),
                icon: const Icon(Icons.add_rounded, size: 14),
                label: const Text(
                  'Add Group',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          if (groupColors.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(30),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade100),
              ),
              child: Column(
                children: [
                  Icon(
                    Icons.label_off_outlined,
                    color: Colors.grey.shade300,
                    size: 32,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'No custom labels yet',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            ),

          ...groupColors.keys.map((groupName) {
            final merchants = categoryGroups.entries
                .where((e) => e.value == groupName)
                .map((e) => e.key)
                .toList();
            final color = Color(groupColors[groupName]!);

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: color.withValues(alpha: 0.2)),
              ),
              child: Material(
                color: color.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16),
                clipBehavior: Clip.antiAlias,
                child: ExpansionTile(
                  shape: const Border(),
                  collapsedShape: const Border(),
                  tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  leading: Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color,
                    ),
                  ),
                  title: Text(
                    groupName,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    '₹${groupLimits[groupName]?.toStringAsFixed(0) ?? "0"} limit • ${merchants.length} merchants',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                  trailing: groupName == 'Unread'
                      ? const SizedBox()
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: Image.asset(
                                'assets/edit_icon.png',
                                width: 18,
                                height: 18,
                                color: Colors.black,
                              ),
                              tooltip: 'Edit Group',
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.all(4),
                              constraints: const BoxConstraints(),
                              onPressed: () =>
                                  _showEditGroupDialog(context, groupName),
                            ),
                            const SizedBox(width: 6),
                            IconButton(
                              color: Colors.red,
                              icon: const Icon(
                                Icons.remove_circle_outline_outlined,
                                color: Colors.black,
                                size: 20,
                              ),
                              tooltip: 'Delete Group',
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.all(4),
                              constraints: const BoxConstraints(),
                              onPressed: () async {
                                final confirm = await _showAttractiveDeleteDialog(
                                  context: context,
                                  title: 'Delete Group',
                                  itemName: groupName,
                                  message:
                                      'Are you sure you want to delete the group "$groupName"? Merchants assigned to this group will become unassigned.',
                                );
                                if (confirm == true) {
                                  setState(() {
                                    categoryGroups.removeWhere(
                                      (m, g) => g == groupName,
                                    );
                                    transactionGroups.removeWhere(
                                      (t, g) => g == groupName,
                                    );
                                    groupColors.remove(groupName);
                                    groupLimits.remove(groupName);
                                    _cachedUniqueNames = null;
                                    _cachedLabelGroups = null;
                                  });
                                  setDrawerState(() {});
                                  await _saveSettings();
                                }
                              },
                            ),
                          ],
                        ),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (groupName != 'Unread') ...[
                            Row(
                              children: [
                                const Text(
                                  'Monthly Limit:',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: TextField(
                                    key: ValueKey('group_limit_$groupName'),
                                    keyboardType: TextInputType.number,
                                    style: const TextStyle(fontSize: 13),
                                    decoration: InputDecoration(
                                      filled: true,
                                      fillColor: Colors.white,
                                      isDense: true,
                                      prefixText: '₹ ',
                                      hintText:
                                          groupLimits[groupName]?.toStringAsFixed(
                                            0,
                                          ) ??
                                          'Set budget',
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide(
                                          color: Colors.grey.shade300,
                                        ),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide(
                                          color: Colors.grey.shade300,
                                        ),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: const BorderSide(
                                          color: Colors.blue,
                                          width: 1.5,
                                        ),
                                      ),
                                      contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 10,
                                      ),
                                    ),
                                    onChanged: (val) async {
                                      final limit = double.tryParse(val) ?? 0.0;
                                      setState(() {
                                        groupLimits[groupName] = limit;
                                      });
                                      setDrawerState(() {});
                                      await _saveSettings();
                                    },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                          ],
                          const Text(
                            'Assigned Merchants:',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: merchants
                                .map(
                                  (m) => Chip(
                                    label: Text(
                                      m,
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: Colors.black,
                                      ),
                                    ),
                                    deleteIcon: const Icon(
                                      Icons.close,
                                      size: 12,
                                      color: Colors.black,
                                    ),
                                    onDeleted: () {
                                      setState(() => categoryGroups.remove(m));
                                      setDrawerState(() {});
                                      _saveSettings();
                                    },
                                    backgroundColor: Colors.blue.shade50,
                                    side: BorderSide(
                                      color: Colors.blue.withOpacity(0.3),
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    visualDensity: VisualDensity.compact,
                                  ),
                                )
                                .toList(),
                          ),
                          if (groupName != 'Unread') ...[
                            const SizedBox(height: 12),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                onPressed: () =>
                                    _showEditGroupDialog(context, groupName),
                                icon: Image.asset(
                                  'assets/edit_icon.png',
                                  width: 14,
                                  height: 14,
                                  color: color,
                                ),
                                label: const Text(
                                  'Edit Name, Limit & Theme Color',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                style: TextButton.styleFrom(
                                  foregroundColor: color,
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
          SizedBox(height: MediaQuery.of(context).viewInsets.bottom + 100),
        ],
      ),
    );
  }

  Widget _buildTempInfoTab(BuildContext context, [StateSetter? setDrawerState]) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Banner Image Card
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Container(
              height: 140,
              width: double.infinity,
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Image.asset(
                      'assets/privacy_banner.jpg',
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          color: const Color(0xFF0F172A),
                          child: const Center(
                            child: Icon(
                              Icons.shield_outlined,
                              size: 50,
                              color: Color(0xFF10B981),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.black.withValues(alpha: 0.75),
                            Colors.transparent,
                          ],
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 12,
                    left: 16,
                    right: 16,
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: const Color(
                              0xFF10B981,
                            ).withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: const Color(0xFF10B981),
                              width: 1.2,
                            ),
                          ),
                          child: const Icon(
                            Icons.verified_user_rounded,
                            color: Color(0xFF10B981),
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Offline Financial Intelligence',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),

          // Official Mandatory Privacy Note Box
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFECFDF5),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFA7F3D0), width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF10B981).withValues(alpha: 0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(
                    color: Color(0xFF10B981),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.lock_rounded,
                    color: Colors.white,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Privacy Note',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF047857),
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Zero data is sent to external servers or cloud databases. All transaction data remains strictly offline inside your device\'s private app sandbox.',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF065F46),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Online Privacy Policy Button Card
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () async {
                try {
                  final Uri url = Uri.parse('https://privacypolicyofspenderpro.web.app/');
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  } else {
                    await launchUrl(url, mode: LaunchMode.platformDefault);
                  }
                } catch (e) {
                  debugPrint('Error launching privacy policy URL: $e');
                }
              },
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F172A),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.privacy_tip_rounded,
                        color: Color(0xFF10B981),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Official Privacy Policy',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'privacypolicyofspenderpro.web.app',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: Colors.white.withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.open_in_new_rounded,
                      color: Colors.white70,
                      size: 18,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // App Version & Update Card (GitHub Variant)
          if (AppUpdateService.isUpdateSupported) ...[
            _buildAppUpdateCard(setDrawerState ?? (fn) => setState(fn)),
            const SizedBox(height: 14),
          ],

          const Text(
            'HOW THE APPLICATION WORKS',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 12),

          _buildInfoItem(
            icon: Icons.security_rounded,
            title: 'AES-256 Offline Encryption',
            description:
                'All expenses and bank card budget configurations are encrypted locally before saving to device storage.',
            accentColor: Colors.teal.shade600,
          ),
          const SizedBox(height: 12),

          _buildInfoItem(
            icon: Icons.widgets_rounded,
            title: 'Widget & Analytics Sync',
            description:
                'Syncs spend totals with home screen widgets and renders real-time budget line graphs dynamically.',
            accentColor: Colors.indigo.shade600,
          ),
          const SizedBox(height: 24),

          const Text(
            'TAB & BUTTON FUNCTIONALITY GUIDE',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.grey,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 12),

          _buildTabGuideSection(
            icon: Icons.settings_suggest_rounded,
            tabName: 'SETTINGS TAB (Card Configurations)',
            color: Colors.blue.shade700,
            features: [
              {
                'title': 'Credit / Debit Toggle',
                'desc':
                    'Switch card mode between Credit Card (SPENT) and Bank Account (DEBITED).',
              },
              {
                'title': 'Budget Limit & Boundary',
                'desc':
                    'Set maximum monthly spend limit and warning threshold alert amounts.',
              },
              {
                'title': 'Hide Credit Data Switch',
                'desc':
                    'Hide or show CREDITED values (SEP CREDITED & amount) on the card header.',
              },
              {
                'title': 'Reset Values Button',
                'desc':
                    'Instantly restores default card budget limits and alert boundary threshold values.',
              },
              {
                'title': 'Card Theme Selector',
                'desc':
                    'Choose custom visual gradient styles (Amethyst, Emerald, Sunset, etc.).',
              },
              {
                'title': 'Include in Total Budget',
                'desc':
                    'Toggle whether this card\'s expenses count towards the overall home total.',
              },
              {
                'title': 'Billing Due Date Cycle',
                'desc':
                    'Filter card expenses strictly within your credit card monthly billing cycle date.',
              },
            ],
          ),

          _buildTabGuideSection(
            icon: Icons.filter_alt_rounded,
            tabName: 'FILTER TAB (Categories & Merchant Grouping)',
            color: Colors.purple.shade700,
            features: [
              {
                'title': 'Category & Group Chips',
                'desc':
                    'Filter transaction log by Shopping, Travel, Dining, Unread, and custom groups.',
              },
              {
                'title': 'Group Selected Button',
                'desc':
                    'Multi-select unassigned merchant chips and bundle them into custom categories.',
              },
              {
                'title': 'Merchant Long-Press',
                'desc':
                    'Long-press any merchant filter chip to permanently delete its mapping.',
              },
            ],
          ),

          _buildTabGuideSection(
            icon: Icons.credit_card_rounded,
            tabName: 'CONFIGURE TAB (Bank Card Manager)',
            color: Colors.teal.shade700,
            features: [
              {
                'title': 'Card Visibility Checkboxes',
                'desc':
                    'Check or uncheck bank cards to show or hide them from the main stack.',
              },
              {
                'title': 'Reorder Card Order',
                'desc':
                    'Drag and reorder bank cards to prioritize your primary financial accounts.',
              },
              {
                'title': 'Add Custom Card',
                'desc':
                    'Manually add new bank card SMS headers for custom tracking.',
              },
            ],
          ),

          _buildTabGuideSection(
            icon: Icons.touch_app_rounded,
            tabName: 'MAIN SCREEN CONTROLS & BUTTONS',
            color: Colors.amber.shade800,
            features: [
              {
                'title': 'Sync SMS Button (🔁)',
                'desc':
                    'Triggers a fresh scan of incoming bank SMS notifications to sync expenses.',
              },
              {
                'title': 'Month Selector Strip',
                'desc':
                    'Switch between months (JAN, FEB, MAR...) to inspect historical financial logs.',
              },
              {
                'title': 'Due Date Filter Chip (📅)',
                'desc':
                    'Quickly toggle between Calendar Month mode and Credit Card Billing Cycle mode.',
              },
              {
                'title': 'Bottom Drawer Save / Cancel',
                'desc':
                    'Save updates settings & widgets; Cancel discards uncommitted drawer changes.',
              },
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildTabGuideSection({
    required IconData icon,
    required String tabName,
    required Color color,
    required List<Map<String, String>> features,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
              border: Border(
                bottom: BorderSide(
                  color: color.withValues(alpha: 0.15),
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(icon, color: color, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tabName,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.bold,
                      color: color,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: features.map((f) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        margin: const EdgeInsets.only(top: 5),
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: RichText(
                          text: TextSpan(
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF334155),
                              height: 1.4,
                            ),
                            children: [
                              TextSpan(
                                text: '${f['title']}: ',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF0F172A),
                                ),
                              ),
                              TextSpan(text: f['desc']),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoItem({
    required IconData icon,
    required String title,
    required String description,
    required Color accentColor,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200, width: 0.8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: accentColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  description,
                  style: const TextStyle(
                    fontSize: 11.5,
                    height: 1.35,
                    color: Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTempFilterTab(StateSetter setDrawerState, ExpenseState state) {
    if (state is! ExpenseLoaded) {
      return const Center(child: Text('No categories available'));
    }

    if (_cachedUniqueNames == null) {
      bool isUpiRef(String name) {
        final lower = name.toLowerCase().trim();
        return lower.startsWith('upi ref') ||
            lower.contains('upi ref:') ||
            lower.startsWith('ref no:') ||
            lower.startsWith('ref:') ||
            RegExp(r'\bupi\s*ref\b', caseSensitive: false).hasMatch(lower);
      }

      final rawCleanedNames = state.data.expenses
          .where((e) =>
              !isDeclinedOrFailedText(e.name) &&
              !isCardEndingOrDeclinedMerchant(e.name) &&
              !isStatementOrBillText(e.name))
          .map((e) => canonicalFilterMerchantName(cleanMerchantName(e.name)).trim().toUpperCase())
          .where((name) =>
              name.isNotEmpty &&
              !isUpiRef(name) &&
              !isDeclinedOrFailedText(name) &&
              !isCardEndingOrDeclinedMerchant(name) &&
              !isStatementOrBillText(name))
          .toSet();

      // Deduplicate core names so items like "adhnan.e-2", "adhnan.e-3" combine into "adhnan.e"
      // and duplicate entries between name and name (UPI) are combined into a single chip.
      final Map<String, String> deduplicatedMap = {};
      for (final name in rawCleanedNames) {
        final core = name.replaceAll(RegExp(r'\s*\(?UPI\)?', caseSensitive: false), '').trim();
        if (deduplicatedMap.containsKey(core)) {
          if (name.contains('(UPI)')) {
            deduplicatedMap[core] = name;
          }
        } else {
          deduplicatedMap[core] = name;
        }
      }

      _cachedUniqueNames = deduplicatedMap.values.toList()..sort();

      final Map<String, List<String>> groups = {};
      for (final name in _cachedUniqueNames!) {
        if (categoryGroups.containsKey(name)) {
          final label = categoryGroups[name]!;
          groups.putIfAbsent(label, () => []).add(name);
        }
      }
      _cachedLabelGroups = groups;
      _cachedOtherMerchants = _cachedUniqueNames!
          .where((name) => !categoryGroups.containsKey(name))
          .toList();
    }

    final labelGroups = _cachedLabelGroups ?? {};
    final otherMerchants = _cachedOtherMerchants ?? [];

    return StatefulBuilder(
      builder: (context, setFilterState) {
        final selectedSet = _tempSelectedExpenseNames != null
            ? _tempSelectedExpenseNames!.toSet()
            : <String>{};
        final hasUngroupedSelected = selectedSet.any(
          (name) => !categoryGroups.containsKey(name),
        );

        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Filter by Group',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.5,
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      _showGroupingDialog(
                        context,
                        targetNames: _tempSelectedExpenseNames,
                      );
                      _cachedUniqueNames = null;
                      setFilterState(() {});
                      setDrawerState(() {});
                    },
                    icon: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.add, color: Colors.white, size: 18),
                    ),
                    tooltip: 'Create New Group',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Select specific categories to isolate expenses',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 24),

              if (labelGroups.isNotEmpty) ...[
                ...labelGroups.entries.map((entry) {
                  final label = entry.key;
                  final merchants = entry.value;
                  final isSelected = selectedSet.contains(label);
                  final color = Color(groupColors[label] ?? Colors.black.value);

                  return GestureDetector(
                    onTap: () {
                      setFilterState(() {
                        if (isSelected) {
                          _tempSelectedExpenseNames!.remove(label);
                        } else {
                          _tempSelectedExpenseNames!.add(label);
                        }
                      });
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: isSelected ? color.withValues(alpha: 0.08) : Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected
                              ? color.withValues(alpha: 0.3)
                              : Colors.grey.shade200,
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  label,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                                Text(
                                  '${merchants.length} merchants linked',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            isSelected ? Icons.check_circle : Icons.circle_outlined,
                            color: isSelected ? color : Colors.grey.shade300,
                            size: 24,
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],

              if (otherMerchants.isNotEmpty) ...[
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'INDIVIDUAL MERCHANTS',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                        letterSpacing: 1.2,
                      ),
                    ),
                    if (hasUngroupedSelected)
                      TextButton.icon(
                        onPressed: () {
                          _showGroupingDialog(
                            context,
                            targetNames: _tempSelectedExpenseNames,
                          );
                          _cachedUniqueNames = null;
                          setFilterState(() {});
                          setDrawerState(() {});
                        },
                        icon: const Icon(Icons.group_add_outlined, size: 18),
                        label: const Text(
                          'Group Selected',
                          style: TextStyle(fontSize: 14),
                        ),
                        style: TextButton.styleFrom(
                          foregroundColor: getThemeColor(cardName),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: otherMerchants.map((name) {
                    final isSelected = selectedSet.contains(name) ||
                        matchesExpenseNameFilter(name, _tempSelectedExpenseNames ?? []);
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        setFilterState(() {
                          if (isSelected) {
                            _tempSelectedExpenseNames!.removeWhere((n) =>
                                n == name || matchesExpenseNameFilter(n, [name]));
                          } else {
                            _tempSelectedExpenseNames!.add(name);
                          }
                        });
                      },
                      onLongPress: () {
                        _confirmDeleteMerchant(context, name, (fn) {
                          _cachedUniqueNames = null;
                          setFilterState(fn);
                          setDrawerState(fn);
                        });
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Colors.blue.shade50
                              : Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSelected
                                ? Colors.blue.withValues(alpha: 0.4)
                                : Colors.grey.shade300,
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isSelected) ...[
                              const Icon(
                                Icons.check_rounded,
                                size: 13,
                                color: Colors.blue,
                              ),
                              const SizedBox(width: 4),
                            ],
                            Text(
                              name.toLowerCase(),
                              style: TextStyle(
                                color: isSelected
                                    ? Colors.blue.shade900
                                    : Colors.black87,
                                fontSize: 11,
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
              SizedBox(height: MediaQuery.of(context).viewInsets.bottom + 100),
            ],
          ),
        );
      },
    );
  }

  Timer? _widgetUpdateDebounceTimer;

  void _scheduleWidgetUpdate() {
    _widgetUpdateDebounceTimer?.cancel();
    _widgetUpdateDebounceTimer = Timer(const Duration(milliseconds: 800), () {
      if (mounted) {
        _updateWidget();
      }
    });
  }

  Future<void> _captureAndSaveChart(GlobalKey key, String name) async {
    if (kIsWeb) return;
    try {
      final renderObject = key.currentContext?.findRenderObject();
      if (renderObject is! RenderRepaintBoundary || !renderObject.hasSize) {
        return;
      }

      final image = await renderObject.toImage(pixelRatio: 2.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) return;

      final directory = await getApplicationDocumentsDirectory();
      final filePath = p.join(directory.path, '$name.png');
      final file = File(filePath);
      await file.writeAsBytes(byteData.buffer.asUint8List());

      await HomeWidget.saveWidgetData<String>('${name}_path', filePath);
    } catch (_) {}
  }

  Future<void> _updateWidget() async {
    if (kIsWeb) return;
    final state = ref.read(expenseNotifierProvider);
    if (state is! ExpenseLoaded || visibleCards.isEmpty) return;
    final allExpenses = state.data.expenses;

    final targetCard = visibleCards[0];
    final monthName = months[selectedMonth];

    // Calculate totals for targetCard respecting due cycle and unread filters
    final cardDueDateVal = cardDueDates[targetCard];
    final cardExpenses = allExpenses.where((e) {
      bool matchesBank =
          e.bank.toUpperCase().contains(targetCard.toUpperCase()) ||
          targetCard.toUpperCase().contains(e.bank.toUpperCase());
      if (!matchesBank) return false;
      if (_getGroupForExpense(e) == 'Unread') return false;

      if (isDueDateFiltered && cardDueDateVal != null) {
        final endDate = DateTime(
          DateTime.now().year,
          selectedMonth + 1,
          cardDueDateVal.day,
        );
        final startDate = DateTime(
          endDate.year,
          endDate.month - 1,
          endDate.day,
        );
        return (e.date.isAfter(startDate) ||
                e.date.isAtSameMomentAs(startDate)) &&
            (e.date.isBefore(endDate) || e.date.isAtSameMomentAs(endDate)) &&
            (e.type == 'spent' || e.type == 'debited');
      } else {
        return e.date.month == (selectedMonth + 1) &&
            e.date.year == DateTime.now().year &&
            (e.type == 'spent' || e.type == 'debited');
      }
    }).toList();

    final spent = cardExpenses.fold(0.0, (sum, item) => sum + item.amount);
    final limit = cardLimits[targetCard] ?? maxValue;
    final boundary = cardBoundaries[targetCard];
    final hasBoundary = boundary != null && boundary > 0;
    final isWarning = hasBoundary && spent >= boundary;
    final displayCardName = isWarning ? '$targetCard ⚠️' : targetCard;
    final effectiveLimit = hasBoundary ? boundary : limit;
    final remainingBudget = effectiveLimit - spent;

    try {
      await HomeWidget.saveWidgetData<String>(
        'current_value',
        spent.toStringAsFixed(0),
      );
      await HomeWidget.saveWidgetData<String>(
        'max_value',
        limit.toStringAsFixed(0),
      );
      await HomeWidget.saveWidgetData<String>(
        'boundary_value',
        hasBoundary ? boundary.toStringAsFixed(0) : "0",
      );
      await HomeWidget.saveWidgetData<bool>(
        'has_boundary',
        hasBoundary,
      );
      await HomeWidget.saveWidgetData<String>(
        'remaining_budget',
        remainingBudget.toStringAsFixed(0),
      );
      await HomeWidget.saveWidgetData<int>(
        'progress',
        limit > 0 ? ((spent / limit) * 100).toInt() : 0,
      );
      await HomeWidget.saveWidgetData<String>('month_name', monthName);
      await HomeWidget.saveWidgetData<String>('card_name', displayCardName);
      await HomeWidget.saveWidgetData<bool>('is_warning', isWarning);

      // Capture charts for widgets
      await _captureAndSaveChart(_pieChartKey, 'pie_chart');
      await _captureAndSaveChart(_lineChartKey, 'line_chart');

      // Update all widget providers
      await HomeWidget.updateWidget(
        name: 'NagavalliWidgetProvider',
        iOSName: 'NagavalliWidgetProvider',
      );
      await HomeWidget.updateWidget(
        name: 'NagavalliPieWidgetProvider',
        iOSName: 'NagavalliPieWidgetProvider',
      );
      await HomeWidget.updateWidget(
        name: 'NagavalliLineWidgetProvider',
        iOSName: 'NagavalliLineWidgetProvider',
      );
      _checkBoundaryAlerts(state);
    } catch (e) {
      print("Failed to update home widget: $e");
    }
  }

  void _onSliderChanged(double value) {
    HapticFeedback.selectionClick();
    setState(() => _currentValue = value);
    _scheduleWidgetUpdate();
  }

  void _openDrawer(int tabIndex, [String? targetCard]) {
    HapticFeedback.selectionClick();
    _drawerTabIndex = tabIndex;
    editingCardName = targetCard ?? cardName;
    // Reset temp state to current actual values
    _tempVisibleCards = null;
    _tempDisabledCards = null;
    _tempSelectedExpenseNames = null;
    _tempEditingCardName = null;
    _tempCardLimits = null;
    _tempCardBoundaries = null;
    _tempCardDueDates = null;
    _tempIsCreditCardOverrides = null;
    _tempHideCreditData = null;
    _tempCardThemes = null;
    _cachedUniqueNames = null;
    _cachedLabelGroups = null;
    _cachedOtherMerchants = null;

    _scaffoldKey.currentState?.openEndDrawer();
  }

  void _checkBoundaryAlerts(ExpenseState state) {
    if (state is! ExpenseLoaded || visibleCards.isEmpty) return;

    for (final card in visibleCards) {
      final isEnabled = cardBudgetEnabled[card] ?? true;
      if (!isEnabled) continue;

      final maxLimit = cardLimits[card] ?? maxValue;
      final boundary = cardBoundaries[card];
      final cardDueDateVal = cardDueDates[card];

      final cardExpenses = state.data.expenses.where((e) {
        bool matchesBank =
            e.bank.toUpperCase().contains(card.toUpperCase()) ||
            card.toUpperCase().contains(e.bank.toUpperCase());
        if (!matchesBank) return false;
        if (_getGroupForExpense(e) == 'Unread') return false;

        if (isDueDateFiltered && cardDueDateVal != null) {
          final endDate = DateTime(
            DateTime.now().year,
            selectedMonth + 1,
            cardDueDateVal.day,
          );
          final startDate = DateTime(
            endDate.year,
            endDate.month - 1,
            endDate.day,
          );
          return (e.date.isAfter(startDate) ||
                  e.date.isAtSameMomentAs(startDate)) &&
              (e.date.isBefore(endDate) || e.date.isAtSameMomentAs(endDate)) &&
              (e.type == 'spent' || e.type == 'debited');
        } else {
          return e.date.month == (selectedMonth + 1) &&
              e.date.year == DateTime.now().year &&
              (e.type == 'spent' || e.type == 'debited');
        }
      }).toList();

      final spent = cardExpenses.fold(0.0, (sum, item) => sum + item.amount);

      // 1. Check Max Budget Limit Alert (Triggered when spending reaches/exceeds Max Limit)
      if (maxLimit > 0 && spent >= maxLimit) {
        if (_lastNotifiedMaxSpending[card] != spent) {
          _lastNotifiedMaxSpending[card] = spent;
          final excess = spent - maxLimit;
          final excessText = excess > 0
              ? ' Exceeded limit by ₹${excess.toStringAsFixed(0)}.'
              : '';
          _notificationChannel
              .invokeMethod('showNotification', {
                'title': '🚨 Max Budget Exceeded: $card',
                'body':
                    'Total spending of ₹${spent.toStringAsFixed(0)} reached max budget limit of ₹${maxLimit.toStringAsFixed(0)}.$excessText',
              })
              .catchError((e) {
                print("Failed to trigger max limit system notification: $e");
              });
        }
      }

      // 2. Check Warning Boundary Alert (Triggered when spending reaches warning boundary threshold)
      if (boundary != null && boundary > 0 && spent >= boundary && spent < maxLimit) {
        if (_lastNotifiedBoundarySpending[card] != spent) {
          _lastNotifiedBoundarySpending[card] = spent;
          final excess = spent - boundary;
          _notificationChannel
              .invokeMethod('showNotification', {
                'title': '⚠️ Warning Boundary Reached: $card',
                'body':
                    'Spending of ₹${spent.toStringAsFixed(0)} reached boundary threshold of ₹${boundary.toStringAsFixed(0)} (exceeded by ₹${excess.toStringAsFixed(0)}).',
              })
              .catchError((e) {
                print("Failed to trigger boundary system notification: $e");
              });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final gradientColors = getCardThemeGradient(cardName);

    ref.listen<ExpenseState>(expenseNotifierProvider, (previous, next) {
      if (next is ExpenseLoaded) {
        _updateWidget();
        _checkBoundaryAlerts(next);
      }
    });

    final state = ref.watch(expenseNotifierProvider);

    double totalAmount = 0.0;
    if (state is ExpenseLoaded) {
      final filteredForMonth = state.data.expenses.where((expense) {
        bool matchesMonth =
            expense.date.month == (selectedMonth + 1) &&
            expense.date.year == DateTime.now().year;
        final normalizedName = expense.name.trim().toUpperCase();
        final groupLabel = _getGroupForExpense(expense);
        bool matchesName =
            selectedExpenseNames.isEmpty ||
            matchesExpenseNameFilter(expense.name, selectedExpenseNames) ||
            (groupLabel != null &&
                selectedExpenseNames.contains(groupLabel));
        bool isNotUnread = _getGroupForExpense(expense) != 'Unread';
        return matchesMonth && matchesName && isNotUnread;
      }).toList();
      totalAmount = filteredForMonth.fold(
        0.0,
        (sum, item) => sum + item.amount,
      );
    }

    return Scaffold(
          key: _scaffoldKey,
          backgroundColor: Colors.grey.shade50,
          endDrawer: Drawer(
            backgroundColor: Colors.white,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(30),
                bottomLeft: Radius.circular(30),
              ),
            ),
            width: math.min(MediaQuery.of(context).size.width * 0.93, 420.0),
            child: SafeArea(
              top: true,
              bottom: true,
              child: StatefulBuilder(
                builder: (context, setDrawerState) {
                  // Initialize local temp state once per drawer open
                  _tempVisibleCards ??= List.from(visibleCards);
                  _tempDisabledCards ??= Set.from(disabledCards);
                  _tempSelectedExpenseNames ??= List.from(selectedExpenseNames);
                  _tempEditingCardName ??= editingCardName ?? cardName;
                  _tempCardLimits ??= Map.from(cardLimits);
                  _tempCardBoundaries ??= Map.from(cardBoundaries);
                  _tempCardBudgetEnabled ??= Map.from(cardBudgetEnabled);
                  _tempCardDueDates ??= Map.from(cardDueDates);
                  _tempIsCreditCardOverrides ??= Map.from(
                    isCreditCardOverrides,
                  );
                  _tempHideCreditData ??= Map.from(hideCreditDataOverrides);
                  _tempIncludeInTotalBudget ??= Map.from(includeInTotalBudget);
                  _tempCardThemes ??= Map.from(cardThemes);
                  _tempShowBudgetOverview ??= showBudgetOverview;

                  return DefaultTabController(
                    length: _tempVisibleCards!.isEmpty ? 2 : 5,
                    initialIndex: _tempVisibleCards!.isEmpty
                        ? 0
                        : _drawerTabIndex.clamp(0, 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                          padding: const EdgeInsets.all(4),
                          height: 48,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: const Color(0xFFE2E8F0),
                              width: 0.8,
                            ),
                          ),
                          child: TabBar(
                            dividerColor: Colors.transparent,
                            indicatorSize: TabBarIndicatorSize.tab,
                            indicator: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.08),
                                  blurRadius: 4,
                                  offset: const Offset(0, 1),
                                ),
                              ],
                            ),
                            labelColor: const Color(0xFF0F172A),
                            unselectedLabelColor: const Color(0xFF64748B),
                            labelStyle: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                              letterSpacing: -0.2,
                            ),
                            unselectedLabelStyle: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                              letterSpacing: -0.2,
                            ),
                            splashFactory: NoSplash.splashFactory,
                            overlayColor: WidgetStateProperty.all(Colors.transparent),
                            labelPadding: EdgeInsets.zero,
                            onTap: (index) {
                              _drawerTabIndex = index;
                            },
                            tabs: _tempVisibleCards!.isEmpty
                                ? const [
                                    Tab(
                                      height: 40,
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.credit_card_rounded, size: 15),
                                            SizedBox(width: 5),
                                            Text('Configure'),
                                          ],
                                        ),
                                      ),
                                    ),
                                    Tab(
                                      height: 40,
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.info_outline_rounded, size: 15),
                                            SizedBox(width: 5),
                                            Text('Info'),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ]
                                : const [
                                    Tab(
                                      height: 40,
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.tune_rounded, size: 14),
                                            SizedBox(width: 3),
                                            Text('Settings'),
                                          ],
                                        ),
                                      ),
                                    ),
                                    Tab(
                                      height: 40,
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.pie_chart_rounded, size: 14),
                                            SizedBox(width: 3),
                                            Text('Budget'),
                                          ],
                                        ),
                                      ),
                                    ),
                                    Tab(
                                      height: 40,
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.filter_list_rounded, size: 14),
                                            SizedBox(width: 3),
                                            Text('Filter'),
                                          ],
                                        ),
                                      ),
                                    ),
                                    Tab(
                                      height: 40,
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.credit_card_rounded, size: 14),
                                            SizedBox(width: 3),
                                            Text('Configure'),
                                          ],
                                        ),
                                      ),
                                    ),
                                    Tab(
                                      height: 40,
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.info_outline_rounded, size: 14),
                                            SizedBox(width: 3),
                                            Text('Info'),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                          ),
                        ),
                        Expanded(
                          child: TabBarView(
                            children: _tempVisibleCards!.isEmpty
                                ? [
                                    _buildTempConfigureTab(setDrawerState),
                                    _buildTempInfoTab(context, setDrawerState),
                                  ]
                                : [
                                    _buildTempSettingsTab(
                                      setDrawerState,
                                      state,
                                    ),
                                    _buildTempBudgetTab(
                                      setDrawerState,
                                      state,
                                    ),
                                    _buildTempFilterTab(setDrawerState, state),
                                    _buildTempConfigureTab(setDrawerState),
                                    _buildTempInfoTab(context, setDrawerState),
                                  ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(20),
                          child: Row(
                            children: [
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () {
                                    setState(() {
                                      _tempVisibleCards = null;
                                      _tempDisabledCards = null;
                                      _tempSelectedExpenseNames = null;
                                      _tempEditingCardName = null;
                                      _tempCardLimits = null;
                                      _tempCardBoundaries = null;
                                      _tempCardBudgetEnabled = null;
                                      _tempCardDueDates = null;
                                      _tempIsCreditCardOverrides = null;
                                      _tempHideCreditData = null;
                                      _tempIncludeInTotalBudget = null;
                                      _tempCardThemes = null;
                                      _cachedUniqueNames = null;
                                      _cachedLabelGroups = null;
                                      _cachedOtherMerchants = null;
                                      _tempShowBudgetOverview = null;
                                    });
                                    Navigator.pop(context);
                                  },
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size(0, 50),
                                    side: BorderSide(
                                      color: Colors.grey.shade300,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(15),
                                    ),
                                  ),
                                  child: const Text(
                                    'Cancel',
                                    style: TextStyle(
                                      color: Colors.grey,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: ElevatedButton(
                                  onPressed: () {
                                    HapticFeedback.lightImpact();
                                    setState(() {
                                      visibleCards = List.from(
                                        _tempVisibleCards!,
                                      );
                                      disabledCards = Set.from(_tempDisabledCards ?? disabledCards);
                                      for (final g in _bankGroups) {
                                        final norm = normalizeBankName(g.label);
                                        if (visibleCards.contains(g.label) ||
                                            visibleCards.contains(norm)) {
                                          disabledCards.removeWhere((dc) =>
                                              dc.toUpperCase() == g.label.toUpperCase() ||
                                              dc.toUpperCase() == norm.toUpperCase() ||
                                              g.label.toUpperCase().contains(dc.toUpperCase()) ||
                                              dc.toUpperCase().contains(g.label.toUpperCase()));
                                        } else {
                                          disabledCards.add(g.label);
                                          disabledCards.add(norm);
                                        }
                                      }
                                      if (cardName.isNotEmpty && !visibleCards.contains(cardName)) {
                                        cardName = visibleCards.isNotEmpty ? visibleCards.first : '';
                                      }
                                      selectedExpenseNames = List.from(
                                        _tempSelectedExpenseNames!,
                                      );
                                      editingCardName = _tempEditingCardName;
                                      cardLimits = Map.from(_tempCardLimits!);
                                      cardBoundaries = Map.from(
                                        _tempCardBoundaries!,
                                      )..removeWhere((key, val) => val <= 0);
                                      cardBudgetEnabled = Map.from(
                                        _tempCardBudgetEnabled!,
                                      );
                                      cardDueDates = Map.from(
                                        _tempCardDueDates!,
                                      );
                                      isCreditCardOverrides = Map.from(
                                        _tempIsCreditCardOverrides!,
                                      );
                                      hideCreditDataOverrides = Map.from(
                                        _tempHideCreditData!,
                                      );
                                      includeInTotalBudget = Map.from(
                                        _tempIncludeInTotalBudget!,
                                      );
                                      cardThemes = Map.from(_tempCardThemes!);
                                      showBudgetOverview =
                                          _tempShowBudgetOverview ?? showBudgetOverview;

                                      // Reset temp state for next time
                                      _tempVisibleCards = null;
                                      _tempDisabledCards = null;
                                      _tempSelectedExpenseNames = null;
                                      _tempEditingCardName = null;
                                      _tempCardLimits = null;
                                      _tempCardBoundaries = null;
                                      _tempCardBudgetEnabled = null;
                                      _tempCardDueDates = null;
                                      _tempIsCreditCardOverrides = null;
                                      _tempHideCreditData = null;
                                      _tempIncludeInTotalBudget = null;
                                      _tempCardThemes = null;
                                      _tempShowBudgetOverview = null;
                                      _cachedUniqueNames = null;
                                      _cachedLabelGroups = null;
                                      _cachedOtherMerchants = null;
                                    });

                                    Navigator.pop(context);
                                    _scheduleWidgetUpdate();
                                    _saveSettings();
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.black,
                                    minimumSize: const Size(0, 50),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(15),
                                    ),
                                    elevation: 0,
                                  ),
                                  child: const Text(
                                    'Apply Changes',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
                ),
              ),
            ),
          body: SafeArea(
            child: Builder(
              builder: (context) {
                List<Expense> debitExpenses = [];
                List<Expense> creditExpenses = [];
                Color cardThemeColor = gradientColors.first;
                bool hideCreditData = false;

                if (state is ExpenseLoaded) {
                  final cardDueDateVal = cardDueDates[cardName];
                  final filteredExpenses = state.data.expenses.where((expense) {
                    if (isDueDateFiltered && cardDueDateVal != null) {
                      final endDate = DateTime(
                        DateTime.now().year,
                        selectedMonth + 1,
                        cardDueDateVal.day,
                      );
                      final startDate = DateTime(
                        endDate.year,
                        endDate.month - 1,
                        endDate.day,
                      );
                      bool withinRange =
                          (expense.date.isAfter(startDate) ||
                              expense.date.isAtSameMomentAs(startDate)) &&
                          (expense.date.isBefore(endDate) ||
                              expense.date.isAtSameMomentAs(endDate));
                      bool matchesBank =
                          cardName.isEmpty ||
                          expense.bank.toUpperCase().contains(
                            cardName.toUpperCase(),
                          ) ||
                          cardName.toUpperCase().contains(
                            expense.bank.toUpperCase(),
                          );
                      final groupLabel = _getGroupForExpense(expense);
                      bool matchesFilter =
                          selectedExpenseNames.isEmpty ||
                          matchesExpenseNameFilter(expense.name, selectedExpenseNames) ||
                          (groupLabel != null &&
                              selectedExpenseNames.contains(groupLabel));
                      bool matchesWeek = true;
                      if (selectedWeek != null) {
                        int day = expense.date.day;
                        if (selectedWeek == 1 && day > 7) matchesWeek = false;
                        if (selectedWeek == 2 && (day < 8 || day > 14)) matchesWeek = false;
                        if (selectedWeek == 3 && (day < 15 || day > 21)) matchesWeek = false;
                        if (selectedWeek == 4 && day < 22) matchesWeek = false;
                      }

                      return withinRange &&
                          matchesWeek &&
                          matchesBank &&
                          matchesFilter;
                    }
                    bool matchesMonth =
                        expense.date.month == (selectedMonth + 1) &&
                        expense.date.year == DateTime.now().year;

                    bool matchesWeek = true;
                    if (selectedWeek != null) {
                      int day = expense.date.day;
                      if (selectedWeek == 1 && day > 7) matchesWeek = false;
                      if (selectedWeek == 2 && (day < 8 || day > 14)) matchesWeek = false;
                      if (selectedWeek == 3 && (day < 15 || day > 21)) matchesWeek = false;
                      if (selectedWeek == 4 && day < 22) matchesWeek = false;
                    }

                    bool matchesBank =
                        cardName.isEmpty ||
                        expense.bank.toUpperCase().contains(
                          cardName.toUpperCase(),
                        ) ||
                        cardName.toUpperCase().contains(
                          expense.bank.toUpperCase(),
                        );
                    final groupLabel = _getGroupForExpense(expense);
                    bool matchesFilter =
                        selectedExpenseNames.isEmpty ||
                        matchesExpenseNameFilter(expense.name, selectedExpenseNames) ||
                        (groupLabel != null &&
                            selectedExpenseNames.contains(groupLabel));
                    return matchesMonth &&
                        matchesWeek &&
                        matchesBank &&
                        matchesFilter;
                  }).toList()..sort(
                    (a, b) => b.date.compareTo(a.date),
                  );

                  debitExpenses = filteredExpenses
                      .where((e) => e.type == 'spent' || e.type == 'debited')
                      .toList();
                  creditExpenses = filteredExpenses
                      .where((e) => e.type == 'credited')
                      .toList();

                  final gColors = getCardThemeGradient(cardName);
                  cardThemeColor = gColors.first;

                  hideCreditData =
                      (hideCreditDataOverrides[cardName] ?? false) ||
                      (isCreditCardOverrides[cardName] ?? false);
                }

                return CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(
                      child: Column(
                        children: [
                          _buildAppUpdateBanner(),
                  Builder(
                    builder: (context) {
                      final visibleGroups = visibleCards
                          .map((label) {
                            try {
                              return _bankGroups.firstWhere(
                                (g) => g.label == label,
                              );
                            } catch (_) {
                              return null;
                            }
                          })
                          .whereType<BankSmsGroup>()
                          .toList();
                      return CreditCardStack(
                        bankGroups: visibleGroups,
                        selectedMonth: selectedMonth,
                        cardLimits: cardLimits,
                        cardBudgetEnabled: cardBudgetEnabled,
                        maxValue: maxValue,
                        cardThemes: cardThemes,
                        isSyncing: _isSyncing,
                        onCardChanged: (name) {
                          setState(() {
                            cardName = name;
                            if (cardDueDates[name] == null) {
                              isDueDateFiltered = false;
                            }
                          });
                        },
                        onSync: _syncSms,
                        onSettingsTap: (name) => _openDrawer(0, name),
                        onFilterTap: (name) {
                          if (selectedExpenseNames.isNotEmpty) {
                            setState(() {
                              selectedExpenseNames.clear();
                              _tempSelectedExpenseNames = null;
                            });
                          } else {
                            _openDrawer(2, name);
                          }
                        },
                        initialCardName:
                            cardName.isEmpty && visibleGroups.isNotEmpty
                            ? visibleGroups.first.label
                            : cardName,
                        onReorder: (newList) async {
                          setState(() {
                            visibleCards = newList;
                            _updateWidget();
                          });
                          await _saveSettings();
                        },
                        groupLimits: groupLimits,
                        groupColors: groupColors,
                        categoryGroups: categoryGroups,
                        transactionGroups: transactionGroups,
                        isDueDateFiltered: isDueDateFiltered,
                        cardDueDates: cardDueDates,
                        isCreditCardOverrides: isCreditCardOverrides,
                        hideCreditDataOverrides: hideCreditDataOverrides,
                      );
                    },
                  ),
                  if (visibleCards.isNotEmpty) ...[
                    // Restore Month Selector
                    Builder(
                      builder: (context) {
                        final currentCard = cardName.isNotEmpty
                            ? cardName
                            : (visibleCards.isNotEmpty ? visibleCards.first : '');
                        final cardColors = getCardThemeGradient(currentCard);
                        final activeGradient = cardColors.length >= 2
                            ? [cardColors.first, cardColors.last]
                            : [cardColors.first, cardColors.first];
                        final primaryCardColor = cardColors.first;

                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 15,
                            vertical: 8,
                          ),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(40),
                              color: Colors.white,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.04),
                                  blurRadius: 14,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                              border: Border.all(
                                color: const Color(0xFFF1F5F9),
                                width: 1.2,
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 6,
                              ),
                              child: SizedBox(
                                height: 30,
                                child: ListView.builder(
                                  controller: _monthScrollController,
                                  itemCount: months.length,
                                  scrollDirection: Axis.horizontal,
                                  physics: const BouncingScrollPhysics(),
                                  itemBuilder: (context, index) {
                                    final isSelected = index == selectedMonth;
                                    return GestureDetector(
                                      onTap: () {
                                        if (selectedMonth != index) {
                                          HapticFeedback.selectionClick();
                                          setState(() {
                                            selectedMonth = index;
                                          });
                                          _scrollToMonth(index);
                                          _scheduleWidgetUpdate();
                                        }
                                      },
                                      child: AnimatedContainer(
                                        duration: const Duration(
                                          milliseconds: 200,
                                        ),
                                        margin: const EdgeInsets.only(right: 8,),
                                        padding: isSelected
                                            ? const EdgeInsets.fromLTRB(3, 5, 8, 5,)
                                            : const EdgeInsets.symmetric(
                                                horizontal: 18,
                                                vertical: 8,
                                              ),
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(30,),
                                          gradient: isSelected
                                              ? LinearGradient(
                                                  colors: activeGradient,
                                                  begin: Alignment.centerLeft,
                                                  end: Alignment.centerRight,
                                                )
                                              : null,
                                          color: isSelected
                                              ? null
                                              : const Color(0xFFF1F4F8),
                                          border: isSelected
                                              ? null
                                              : Border.all(
                                                  color: const Color(
                                                    0xFFE2E8F0,
                                                  ).withValues(alpha: 0.7),
                                                  width: 0.8,
                                                ),
                                          boxShadow: isSelected
                                              ? [
                                                  BoxShadow(
                                                    color: primaryCardColor
                                                        .withValues(
                                                          alpha: 0.35,
                                                        ),
                                                    blurRadius: 10,
                                                    offset: const Offset(
                                                      0,
                                                      3,
                                                    ),
                                                  ),
                                                ]
                                              : null,
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            if (isSelected) ...[
                                              Container(
                                                width: 28,
                                                height: 28,
                                                decoration: const BoxDecoration(
                                                  color: Colors.white,
                                                  shape: BoxShape.circle,
                                                ),
                                                alignment: Alignment.center,
                                                child: Text(
                                                  '${DateTime.now().day}',
                                                  style: TextStyle(
                                                    color: primaryCardColor,
                                                    fontSize: 12.5,
                                                    fontWeight: FontWeight.w800,
                                                    height: 1.0,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 2),
                                            ],
                                            Text(
                                              months[index].toUpperCase(),
                                              style: TextStyle(
                                                color: isSelected
                                                    ? Colors.white
                                                    : const Color(0xFF475569),
                                                fontWeight: FontWeight.bold,
                                                fontSize: 12.5,
                                                letterSpacing: 0.8,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    // Restore Warning Box
                    if (state is ExpenseLoaded)
                      Builder(
                        builder: (context) {
                          final cardLimit = cardLimits[cardName];
                          final cardBoundary = cardBoundaries[cardName];
                          final cardDueDateVal = cardDueDates[cardName];

                          final filteredForMonth = state.data.expenses
                              .where((expense) {
                                if (isDueDateFiltered &&
                                    cardDueDateVal != null) {
                                  final endDate = DateTime(
                                    DateTime.now().year,
                                    selectedMonth + 1,
                                    cardDueDateVal.day,
                                  );
                                  final startDate = DateTime(
                                    endDate.year,
                                    endDate.month - 1,
                                    endDate.day,
                                  );
                                  bool withinRange =
                                      (expense.date.isAfter(startDate) ||
                                          expense.date.isAtSameMomentAs(
                                            startDate,
                                          )) &&
                                      (expense.date.isBefore(endDate) ||
                                          expense.date.isAtSameMomentAs(
                                            endDate,
                                          ));
                                  bool matchesBank =
                                      cardName.isEmpty ||
                                      expense.bank.toUpperCase().contains(
                                        cardName.toUpperCase(),
                                      ) ||
                                      cardName.toUpperCase().contains(
                                        expense.bank.toUpperCase(),
                                      );
                                  bool isSpending =
                                      (expense.type == 'spent' ||
                                          expense.type == 'debited') &&
                                      _getGroupForExpense(expense) !=
                                          'Unread';
                                  return withinRange &&
                                      matchesBank &&
                                      isSpending;
                                }
                                bool matchesMonth =
                                    expense.date.month ==
                                        (selectedMonth + 1) &&
                                    expense.date.year ==
                                        DateTime.now().year;
                                bool matchesBank =
                                    cardName.isEmpty ||
                                    expense.bank.toUpperCase().contains(
                                      cardName.toUpperCase(),
                                    ) ||
                                    cardName.toUpperCase().contains(
                                      expense.bank.toUpperCase(),
                                    );
                                bool isSpending =
                                    (expense.type == 'spent' ||
                                        expense.type == 'debited') &&
                                    _getGroupForExpense(expense) !=
                                        'Unread';
                                return matchesMonth &&
                                    matchesBank &&
                                    isSpending;
                              })
                              .toList();

                          final currentTotal = filteredForMonth.fold(
                            0.0,
                            (sum, item) => sum + item.amount,
                          );

                          final isBudgetEnabled =
                              cardBudgetEnabled[cardName] ?? true;
                          if (isBudgetEnabled &&
                              cardBoundary != null &&
                              cardBoundary > 0 &&
                              currentTotal >= cardBoundary) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 15,
                                vertical: 5,
                              ),
                              child: WarningBox(
                                cardBoundary: cardBoundary,
                                currentTotal: currentTotal,
                                cardName: cardName,
                              ),
                            );
                          }
                          return const SizedBox.shrink();
                        },
                      ),
                    // Restore Chart
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 15),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Builder(
                            builder: (context) {
                              final cardLimit = cardLimits[cardName];
                              final cardBoundary = cardBoundaries[cardName];
                              final cardDueDateVal = cardDueDates[cardName];

                              final allFiltered = state is ExpenseLoaded
                                  ? state.data.expenses.where((expense) {
                                      if (_getGroupForExpense(expense) ==
                                          'Unread')
                                        return false;
                                      if (isDueDateFiltered &&
                                          cardDueDateVal != null) {
                                        final endDate = DateTime(
                                          DateTime.now().year,
                                          selectedMonth + 1,
                                          cardDueDateVal.day,
                                        );
                                        final startDate = DateTime(
                                          endDate.year,
                                          endDate.month - 1,
                                          endDate.day,
                                        );
                                        bool withinRange =
                                            (expense.date.isAfter(startDate) ||
                                                expense.date.isAtSameMomentAs(
                                                  startDate,
                                                )) &&
                                            (expense.date.isBefore(endDate) ||
                                                expense.date.isAtSameMomentAs(
                                                  endDate,
                                                ));
                                        bool matchesBank =
                                            cardName.isEmpty ||
                                            expense.bank.toUpperCase().contains(
                                              cardName.toUpperCase(),
                                            ) ||
                                            cardName.toUpperCase().contains(
                                              expense.bank.toUpperCase(),
                                            );
                                        final normalizedName = expense.name
                                            .trim()
                                            .toUpperCase();
                                        final groupLabel = _getGroupForExpense(
                                          expense,
                                        );
                                        bool matchesFilter =
                                            selectedExpenseNames.isEmpty ||
                                            matchesExpenseNameFilter(expense.name, selectedExpenseNames) ||
                                            (groupLabel != null &&
                                                selectedExpenseNames.contains(
                                                  groupLabel,
                                                ));
                                        bool matchesWeek = true;
                                        if (selectedWeek != null) {
                                          int day = expense.date.day;
                                          if (selectedWeek == 1 && day > 7)
                                            matchesWeek = false;
                                          if (selectedWeek == 2 &&
                                              (day < 8 || day > 14))
                                            matchesWeek = false;
                                          if (selectedWeek == 3 &&
                                              (day < 15 || day > 21))
                                            matchesWeek = false;
                                          if (selectedWeek == 4 && day < 22)
                                            matchesWeek = false;
                                        }
                                        return withinRange &&
                                            matchesWeek &&
                                            matchesBank &&
                                            matchesFilter;
                                      }
                                      bool matchesMonth =
                                          expense.date.month ==
                                              (selectedMonth + 1) &&
                                          expense.date.year ==
                                              DateTime.now().year;

                                      bool matchesBank =
                                          cardName.isEmpty ||
                                          expense.bank.toUpperCase().contains(
                                            cardName.toUpperCase(),
                                          ) ||
                                          cardName.toUpperCase().contains(
                                            expense.bank.toUpperCase(),
                                          );
                                      final normalizedName = expense.name
                                          .trim()
                                          .toUpperCase();
                                      final groupLabel = _getGroupForExpense(
                                        expense,
                                      );
                                      bool matchesFilter =
                                          selectedExpenseNames.isEmpty ||
                                          matchesExpenseNameFilter(expense.name, selectedExpenseNames) ||
                                          (groupLabel != null &&
                                              selectedExpenseNames.contains(
                                                groupLabel,
                                              ));
                                      bool matchesWeek = true;
                                      if (selectedWeek != null) {
                                        int day = expense.date.day;
                                        if (selectedWeek == 1 && day > 7)
                                          matchesWeek = false;
                                        if (selectedWeek == 2 &&
                                            (day < 8 || day > 14))
                                          matchesWeek = false;
                                        if (selectedWeek == 3 &&
                                            (day < 15 || day > 21))
                                          matchesWeek = false;
                                        if (selectedWeek == 4 && day < 22)
                                          matchesWeek = false;
                                      }
                                      return matchesMonth &&
                                          matchesWeek &&
                                          matchesBank &&
                                          matchesFilter;
                                    }).toList()
                                  : <Expense>[];

                              final globalFiltered = state is ExpenseLoaded
                                  ? state.data.expenses.where((expense) {
                                      bool matchesMonth =
                                          expense.date.month ==
                                              (selectedMonth + 1) &&
                                          expense.date.year ==
                                              DateTime.now().year;

                                      final normalizedName = expense.name
                                          .trim()
                                          .toUpperCase();
                                      final groupLabel = _getGroupForExpense(
                                        expense,
                                      );
                                      bool matchesFilter =
                                          selectedExpenseNames.isEmpty ||
                                          matchesExpenseNameFilter(expense.name, selectedExpenseNames) ||
                                          (groupLabel != null &&
                                              selectedExpenseNames.contains(
                                                groupLabel,
                                              ));
                                      bool matchesWeek = true;
                                      if (selectedWeek != null) {
                                        int day = expense.date.day;
                                        if (selectedWeek == 1 && day > 7)
                                          matchesWeek = false;
                                        if (selectedWeek == 2 &&
                                            (day < 8 || day > 14))
                                          matchesWeek = false;
                                        if (selectedWeek == 3 &&
                                            (day < 15 || day > 21))
                                          matchesWeek = false;
                                        if (selectedWeek == 4 && day < 22)
                                          matchesWeek = false;
                                      }
                                      return matchesMonth &&
                                          matchesWeek &&
                                          matchesFilter;
                                    }).toList()
                                  : <Expense>[];

                              final debitExpenses = allFiltered
                                  .where(
                                    (e) =>
                                        e.type == 'spent' ||
                                        e.type == 'debited',
                                  )
                                  .toList();
                              final creditExpenses = allFiltered
                                  .where((e) => e.type == 'credited')
                                  .toList();

                              final currentTotal = debitExpenses.fold(
                                0.0,
                                (sum, e) => sum + e.amount,
                              );

                              final yearExpenses = state is ExpenseLoaded
                                  ? state.data.expenses.where((expense) {
                                      final matchesYear =
                                          expense.date.year ==
                                              DateTime.now().year;
                                      final matchesBank =
                                          cardName.isEmpty ||
                                          expense.bank.toUpperCase().contains(
                                            cardName.toUpperCase(),
                                          ) ||
                                          cardName.toUpperCase().contains(
                                            expense.bank.toUpperCase(),
                                          );
                                      final isNotUnread =
                                          _getGroupForExpense(expense) !=
                                              'Unread';
                                      final isSpent =
                                          expense.type == 'spent' ||
                                          expense.type == 'debited';
                                      final groupLabel =
                                          _getGroupForExpense(expense);
                                      final matchesFilter =
                                          selectedExpenseNames.isEmpty ||
                                          matchesExpenseNameFilter(
                                            expense.name,
                                            selectedExpenseNames,
                                          ) ||
                                          (groupLabel != null &&
                                              selectedExpenseNames.contains(
                                                groupLabel,
                                              ));
                                      return matchesYear &&
                                          matchesBank &&
                                          isNotUnread &&
                                          isSpent &&
                                          matchesFilter;
                                    }).toList()
                                  : <Expense>[];

                              return Column(
                                children: [
                                  Container(
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(24),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(
                                            0.015,
                                          ),
                                          blurRadius: 12,
                                          offset: const Offset(0, 6),
                                        ),
                                      ],
                                      border: Border.all(
                                        color: Colors.grey.shade100,
                                        width: 1,
                                      ),
                                    ),
                                    padding: const EdgeInsets.all(19),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.insights_rounded,
                                              color: gradientColors.first,
                                              size: 16,
                                            ),
                                            const SizedBox(width: 8),
                                            const Text(
                                              'ANALYTICS SUMMARY',
                                              style: TextStyle(
                                                fontWeight: FontWeight.bold,
                                                color: Color(0xFF1E293B),
                                                fontSize: 11,
                                                letterSpacing: 1.2,
                                              ),
                                            ),
                                            const Spacer(),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 3,
                                                vertical: 2,
                                              ),
                                              decoration: BoxDecoration(
                                                color: Colors.grey.shade100,
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                border: Border.all(
                                                  color: Colors.grey.shade200,
                                                  width: 0.5,
                                                ),
                                              ),
                                              child: Row(
                                                mainAxisSize:
                                                    MainAxisSize.min,
                                                children: [
                                                  GestureDetector(
                                                    onTap: () {
                                                      if (_analyticsPageController
                                                          .hasClients) {
                                                        _analyticsPageController
                                                            .animateToPage(
                                                          0,
                                                          duration:
                                                              const Duration(
                                                            milliseconds: 300,
                                                          ),
                                                          curve:
                                                              Curves.easeInOut,
                                                        );
                                                      }
                                                    },
                                                    child: Container(
                                                      padding:
                                                          const EdgeInsets
                                                              .symmetric(
                                                        horizontal: 8,
                                                        vertical: 3,
                                                      ),
                                                      decoration:
                                                          BoxDecoration(
                                                        color:
                                                            _analyticsPageIndex ==
                                                                    0
                                                                ? Colors.white
                                                                : Colors
                                                                    .transparent,
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(9),
                                                        boxShadow:
                                                            _analyticsPageIndex ==
                                                                    0
                                                                ? [
                                                                    BoxShadow(
                                                                      color: Colors
                                                                          .black
                                                                          .withValues(
                                                                            alpha:
                                                                                0.06,
                                                                          ),
                                                                      blurRadius:
                                                                          4,
                                                                      offset:
                                                                          const Offset(
                                                                        0,
                                                                        1,
                                                                      ),
                                                                    ),
                                                                  ]
                                                                : null,
                                                      ),
                                                      child: Text(
                                                        'TREND',
                                                        style: TextStyle(
                                                          color:
                                                              _analyticsPageIndex ==
                                                                      0
                                                                  ? gradientColors
                                                                      .first
                                                                  : const Color(
                                                                    0xFF64748B,
                                                                  ),
                                                          fontSize: 8.5,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          letterSpacing: 0.5,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                  GestureDetector(
                                                    onTap: () {
                                                      if (_analyticsPageController
                                                          .hasClients) {
                                                        _analyticsPageController
                                                            .animateToPage(
                                                          1,
                                                          duration:
                                                              const Duration(
                                                            milliseconds: 300,
                                                          ),
                                                          curve:
                                                              Curves.easeInOut,
                                                        );
                                                      }
                                                    },
                                                    child: Container(
                                                      padding:
                                                          const EdgeInsets
                                                              .symmetric(
                                                        horizontal: 8,
                                                        vertical: 3,
                                                      ),
                                                      decoration:
                                                          BoxDecoration(
                                                        color:
                                                            _analyticsPageIndex ==
                                                                    1
                                                                ? Colors.white
                                                                : Colors
                                                                    .transparent,
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(9),
                                                        boxShadow:
                                                            _analyticsPageIndex ==
                                                                    1
                                                                ? [
                                                                    BoxShadow(
                                                                      color: Colors
                                                                          .black
                                                                          .withValues(
                                                                            alpha:
                                                                                0.06,
                                                                          ),
                                                                      blurRadius:
                                                                          4,
                                                                      offset:
                                                                          const Offset(
                                                                        0,
                                                                        1,
                                                                      ),
                                                                    ),
                                                                  ]
                                                                : null,
                                                      ),
                                                      child: Text(
                                                        'YEAR',
                                                        style: TextStyle(
                                                          color:
                                                              _analyticsPageIndex ==
                                                                      1
                                                                  ? gradientColors
                                                                      .first
                                                                  : const Color(
                                                                    0xFF64748B,
                                                                  ),
                                                          fontSize: 8.5,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          letterSpacing: 0.5,
                                                        ),
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 10),
                                        SizedBox(
                                          height: 270,
                                          child: PageView(
                                            controller:
                                                _analyticsPageController,
                                            onPageChanged: (index) {
                                              setState(() {
                                                _analyticsPageIndex = index;
                                              });
                                            },
                                            children: [
                                              RepaintBoundary(
                                                key: _lineChartKey,
                                                child: ExpenseLineChart(
                                                  debitExpenses:
                                                      debitExpenses,
                                                  creditExpenses:
                                                      (isCreditCardOverrides[cardName] ??
                                                              false)
                                                          ? []
                                                          : creditExpenses,
                                                  totalAmount: currentTotal,
                                                  limit:
                                                      (cardBudgetEnabled[cardName] ??
                                                              true)
                                                          ? ((cardLimits[cardName] ??
                                                                        0) >
                                                                  0
                                                              ? cardLimits[cardName]!
                                                              : maxValue)
                                                          : maxValue,
                                                  boundaryLimit:
                                                      (cardBudgetEnabled[cardName] ??
                                                              true)
                                                          ? cardBoundary
                                                          : null,
                                                  selectedMonth:
                                                      selectedMonth,
                                                  isDueDateFiltered:
                                                      isDueDateFiltered,
                                                  dueDate:
                                                      cardDueDateVal?.day,
                                                  selectedWeek: selectedWeek,
                                                  cardTheme: getCardTheme(
                                                    cardName,
                                                  ),
                                                ),
                                              ),
                                              YearContributionHeatmap(
                                                expenses: yearExpenses,
                                                cardName: cardName,
                                                themeColor:
                                                    gradientColors.first,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (showBudgetOverview &&
                                      (cardBudgetEnabled[cardName] ?? true)) ...[
                                    const SizedBox(height: 10),
                                    TotalBudgetOverviewCard(
                                      visibleCards: visibleCards,
                                      expenses: state is ExpenseLoaded
                                          ? state.data.expenses
                                          : [],
                                      selectedMonth: selectedMonth,
                                      selectedYear: DateTime.now().year,
                                      selectedCard: cardName,
                                      selectedCardColors: getCardThemeGradient(cardName),
                                      cardThemeGradients: Map.fromEntries(
                                        visibleCards.map(
                                          (c) => MapEntry(c, getCardThemeGradient(c)),
                                        ),
                                      ),
                                      onCardTap: (selectedCard) {
                                        HapticFeedback.selectionClick();
                                        setState(() {
                                          cardName = selectedCard;
                                        });
                                      },
                                    ),
                                    const SizedBox(height: 10),
                                    Container(
                                       decoration: BoxDecoration(
                                         color: Colors.white,
                                         borderRadius: BorderRadius.circular(24),
                                         boxShadow: [
                                           BoxShadow(
                                             color: Colors.black.withOpacity(
                                               0.015,
                                             ),
                                             blurRadius: 12,
                                             offset: const Offset(0, 6),
                                           ),
                                         ],
                                         border: Border.all(
                                           color: Colors.grey.shade100,
                                           width: 1,
                                         ),
                                       ),
                                       padding: const EdgeInsets.all(19),
                                       child: Column(
                                         crossAxisAlignment:
                                             CrossAxisAlignment.start,
                                         children: [
                                           Row(
                                             children: [
                                               Icon(
                                                 Icons.insights_rounded,
                                                 color: gradientColors.first,
                                                 size: 16,
                                               ),
                                               const SizedBox(width: 8),
                                               const Text(
                                                 'BUDGET SUMMARY',
                                                 style: TextStyle(
                                                   fontWeight: FontWeight.bold,
                                                   color: Color(0xFF1E293B),
                                                   fontSize: 11,
                                                   letterSpacing: 1.2,
                                                 ),
                                               ),
                                               const Spacer(),
                                               Container(
                                                 padding:
                                                     const EdgeInsets.symmetric(
                                                       horizontal: 10,
                                                       vertical: 4,
                                                     ),
                                                 decoration: BoxDecoration(
                                                   color: gradientColors.first
                                                       .withOpacity(0.05),
                                                   borderRadius:
                                                       BorderRadius.circular(12),
                                                   border: Border.all(
                                                     color: Colors.grey.shade100,
                                                     width: 0.5,
                                                   ),
                                                 ),
                                                 child: Text(
                                                   'SWIPE PANEL',
                                                   style: TextStyle(
                                                     color: gradientColors.first,
                                                     fontSize: 8,
                                                     fontWeight: FontWeight.bold,
                                                     letterSpacing: 0.5,
                                                   ),
                                                 ),
                                               ),
                                             ],
                                           ),
                                           const SizedBox(height: 10),
                                           SizedBox(
                                             height: 260,
                                             child: PageView(
                                               children: [
                                                 CombinedGroupBarChart(
                                                   debitExpenses: globalFiltered
                                                       .where(
                                                         (e) =>
                                                             (e.type == 'spent' ||
                                                                 e.type ==
                                                                     'debited') &&
                                                             _getGroupForExpense(
                                                                   e,
                                                                 ) !=
                                                                 'Unread',
                                                       )
                                                       .toList(),
                                                   groupLimits: groupLimits,
                                                   groupColors: groupColors,
                                                   categoryGroups: categoryGroups,
                                                   transactionGroups:
                                                       transactionGroups,
                                                   totalBudget: visibleCards
                                                       .where(
                                                         (bank) =>
                                                             includeInTotalBudget[bank] ??
                                                             true,
                                                       )
                                                       .fold(0.0, (sum, bank) {
                                                         final setLimit =
                                                             cardLimits[bank] ?? 0;
                                                         return sum +
                                                             (setLimit > 0
                                                                 ? setLimit
                                                                 : maxValue);
                                                       }),
                                                 ),
                                                 RepaintBoundary(
                                                   key: _pieChartKey,
                                                   child: ExpensePieChart(
                                                     cardLimits: Map.fromEntries(
                                                       visibleCards
                                                           .where(
                                                             (bank) =>
                                                                 includeInTotalBudget[bank] ??
                                                                 true,
                                                           )
                                                           .map((bank) {
                                                             final setLimit =
                                                                 cardLimits[bank] ??
                                                                 0;
                                                             return MapEntry(
                                                               bank,
                                                               setLimit > 0
                                                                   ? setLimit
                                                                   : maxValue,
                                                             );
                                                           }),
                                                     ),
                                                     groupLimits: groupLimits,
                                                     groupColors: groupColors,
                                                     cardThemes: _tempCardThemes ?? cardThemes,
                                                     cardColors: Map.fromEntries(
                                                       visibleCards.map(
                                                         (bank) => MapEntry(bank, getCardThemeGradient(bank)[1]),
                                                       ),
                                                     ),
                                                   ),
                                                 ),
                                               ],
                                             ),
                                           ),
                                         ],
                                       ),
                                     ),
                                   ],
                                ],
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
            if (visibleCards.isNotEmpty) ...[
              if (state is ExpenseLoading)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(40),
                    child: Center(
                      child: CircularProgressIndicator(),
                    ),
                  ),
                )
              else if (state is ExpenseLoaded) ...[
                PinnedHeaderSliver(
                  child: Container(
                    color: Colors.grey.shade50,
                    padding: const EdgeInsets.symmetric(horizontal: 15),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(24),
                        ),
                        border: Border(
                          left: BorderSide(
                            color: Colors.grey.shade100,
                            width: 1,
                          ),
                          right: BorderSide(
                            color: Colors.grey.shade100,
                            width: 1,
                          ),
                          top: BorderSide(
                            color: Colors.grey.shade100,
                            width: 1,
                          ),
                          bottom: BorderSide(
                            color: Colors.grey.shade200,
                            width: 0.8,
                          ),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Padding(
                                      padding: const EdgeInsets.all(18),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Text(
                                            'TRANSACTIONS',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: Color(0xFF1E293B),
                                              fontSize: 13,
                                              letterSpacing: 1.2,
                                            ),
                                          ),
                                          const SizedBox(height: 12),
                                          Wrap(
                                            spacing: 8,
                                            runSpacing: 10,
                                            crossAxisAlignment:
                                                WrapCrossAlignment.center,
                                            children: [
                                              _buildSyncButton(context),
                                              GestureDetector(
                                                onTap: () {
                                                  final cardDueDateVal =
                                                      cardDueDates[cardName];
                                                  if (cardDueDateVal == null) {
                                                    ScaffoldMessenger.of(
                                                      context,
                                                    ).showSnackBar(
                                                      SnackBar(
                                                        content: Text(
                                                          'Please set a due date for $cardName in Card Settings first.',
                                                          style:
                                                              const TextStyle(
                                                                fontWeight:
                                                                    FontWeight
                                                                        .bold,
                                                              ),
                                                        ),
                                                        backgroundColor: const Color(0xFFEF4444),
                                                      ),
                                                    );
                                                  } else {
                                                    setState(() {
                                                      isDueDateFiltered =
                                                          !isDueDateFiltered;
                                                    });
                                                  }
                                                },
                                                child: AnimatedContainer(
                                                  duration: const Duration(
                                                    milliseconds: 200,
                                                  ),
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 14,
                                                        vertical: 8,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: isDueDateFiltered
                                                        ? const Color(
                                                            0xFFEF4444,
                                                          ).withOpacity(0.08)
                                                        : Colors.grey.shade50,
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          30,
                                                        ),
                                                    border: Border.all(
                                                      color: isDueDateFiltered
                                                          ? const Color(
                                                              0xFFEF4444,
                                                            ).withOpacity(0.3)
                                                          : Colors
                                                                .grey
                                                                .shade200,
                                                      width: 1,
                                                    ),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      Icon(
                                                        Icons
                                                            .calendar_today_rounded,
                                                        size: 12,
                                                        color: isDueDateFiltered
                                                            ? const Color(
                                                                0xFFEF4444,
                                                              )
                                                            : Colors
                                                                  .grey
                                                                  .shade600,
                                                      ),
                                                      const SizedBox(width: 6),
                                                      Text(
                                                        'DUE CYCLE',
                                                        style: TextStyle(
                                                          color:
                                                              isDueDateFiltered
                                                              ? const Color(
                                                                  0xFFEF4444,
                                                                )
                                                              : Colors
                                                                    .grey
                                                                    .shade700,
                                                          fontSize: 10,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          letterSpacing: 0.5,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                              //Date filters
                                              PopupMenuButton<int?>(
                                                onSelected: (week) {
                                                  setState(() {
                                                    selectedWeek = week == 0
                                                        ? null
                                                        : week;
                                                  });
                                                },
                                                shape: RoundedRectangleBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(16),
                                                ),
                                                elevation: 8,
                                                offset: const Offset(0, 20),
                                                color: Colors.white,
                                                tooltip: 'Filter by Week',
                                                child: Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 12,
                                                        vertical: 6.5,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: selectedWeek != null
                                                        ? gradientColors.first
                                                              .withOpacity(0.05)
                                                        : Colors.grey
                                                              .withOpacity(0.1),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          20,
                                                        ),
                                                    border: Border.all(
                                                      color:
                                                          selectedWeek != null
                                                          ? gradientColors.first
                                                                .withOpacity(
                                                                  0.4,
                                                                )
                                                          : Colors.transparent,
                                                    ),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      Icon(
                                                        selectedWeek != null
                                                            ? Icons
                                                                  .calendar_month
                                                            : Icons
                                                                  .calendar_today_rounded,
                                                        color:
                                                            selectedWeek != null
                                                            ? gradientColors
                                                                  .first
                                                            : const Color(
                                                                0xFF1E293B,
                                                              ),
                                                        size: 13,
                                                      ),
                                                      const SizedBox(width: 6),
                                                      Text(
                                                        selectedWeek == null
                                                            ? 'All Weeks'
                                                            : 'Week $selectedWeek',
                                                        style: TextStyle(
                                                          fontSize: 11,
                                                          letterSpacing: 0.5,
                                                          fontWeight:
                                                              selectedWeek !=
                                                                  null
                                                              ? FontWeight.w600
                                                              : FontWeight.w600,
                                                          color:
                                                              selectedWeek !=
                                                                  null
                                                              ? gradientColors
                                                                    .first
                                                              : const Color(
                                                                  0xFF1E293B,
                                                                ),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 4),
                                                      Icon(
                                                        Icons
                                                            .keyboard_arrow_down_rounded,
                                                        color:
                                                            selectedWeek != null
                                                            ? gradientColors
                                                                  .first
                                                            : Colors
                                                                  .grey
                                                                  .shade600,
                                                        size: 16,
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                itemBuilder: (context) {
                                                  PopupMenuItem<int?>
                                                  buildCardItem(
                                                    int? value,
                                                    String label,
                                                    IconData icon,
                                                  ) {
                                                    final isSelected =
                                                        selectedWeek == value;
                                                    return PopupMenuItem<int?>(
                                                      value: value ?? 0,
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 8,
                                                            vertical: 4,
                                                          ),
                                                      child: Container(
                                                        decoration: BoxDecoration(
                                                          color: isSelected
                                                              ? gradientColors
                                                                    .first
                                                                    .withOpacity(
                                                                      0.06,
                                                                    )
                                                              : Colors
                                                                    .transparent,
                                                          borderRadius:
                                                              BorderRadius.circular(
                                                                12,
                                                              ),
                                                          border: isSelected
                                                              ? Border.all(
                                                                  color: gradientColors
                                                                      .first
                                                                      .withOpacity(
                                                                        0.3,
                                                                      ),
                                                                  width: 1,
                                                                )
                                                              : Border.all(
                                                                  color: Colors
                                                                      .transparent,
                                                                  width: 1,
                                                                ),
                                                        ),
                                                        padding:
                                                            const EdgeInsets.symmetric(
                                                              horizontal: 9,
                                                              vertical: 7,
                                                            ),
                                                        child: Row(
                                                          children: [
                                                            Container(
                                                              padding:
                                                                  const EdgeInsets.all(
                                                                    6,
                                                                  ),
                                                              decoration: BoxDecoration(
                                                                color:
                                                                    isSelected
                                                                    ? gradientColors
                                                                          .first
                                                                          .withOpacity(
                                                                            0.18,
                                                                          )
                                                                    : Colors
                                                                          .grey
                                                                          .shade100,
                                                                borderRadius:
                                                                    BorderRadius.circular(
                                                                      8,
                                                                    ),
                                                              ),
                                                              child: Icon(
                                                                icon,
                                                                color:
                                                                    isSelected
                                                                    ? gradientColors
                                                                          .first
                                                                          .withOpacity(
                                                                            1,
                                                                          )
                                                                    : Colors
                                                                          .grey
                                                                          .shade600,
                                                                size: 18,
                                                              ),
                                                            ),
                                                            const SizedBox(
                                                              width: 14,
                                                            ),
                                                            Text(
                                                              label,
                                                              style: TextStyle(
                                                                color:
                                                                    isSelected
                                                                    ? gradientColors.first.withOpacity(0.8,)
                                                                    : const Color(
                                                                        0xFF334155,
                                                                      ),
                                                                fontWeight:
                                                                    isSelected
                                                                    ? FontWeight
                                                                          .w700
                                                                    : FontWeight
                                                                          .w500,
                                                                fontSize: 13,
                                                                letterSpacing:
                                                                    0.3,
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    );
                                                  }

                                                  return [
                                                    buildCardItem(
                                                      null,
                                                      'All Weeks',
                                                      Icons
                                                          .all_inclusive_rounded,
                                                    ),
                                                    buildCardItem(
                                                      1,
                                                      'Week (1st - 7th)',
                                                      Icons.looks_one_rounded,
                                                    ),
                                                    buildCardItem(
                                                      2,
                                                      'Week (8th - 14th)',
                                                      Icons.looks_two_rounded,
                                                    ),
                                                    buildCardItem(
                                                      3,
                                                      'Week (15th - 21st)',
                                                      Icons.looks_3_rounded,
                                                    ),
                                                    buildCardItem(
                                                      4,
                                                      'Week (22nd - End)',
                                                      Icons.looks_4_rounded,
                                                    ),
                                                  ];
                                                },
                                              ),
                                              // Add More Chip (Rule Addition)
                                              InkWell(
                                                onTap: () {
                                                  HapticFeedback.lightImpact();
                                                  if (selectedExpenseNames.isNotEmpty) {
                                                    setState(() {
                                                      selectedExpenseNames.clear();
                                                      _tempSelectedExpenseNames = null;
                                                    });
                                                  } else {
                                                    _openDrawer(1, cardName);
                                                  }
                                                },
                                                onLongPress: () {
                                                  HapticFeedback.selectionClick();
                                                  _openDrawer(0, cardName);
                                                },
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                child: Container(
                                                  padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 15,
                                                        vertical: 6.5,
                                                      ),
                                                  decoration: BoxDecoration(
                                                    color: gradientColors.first
                                                        .withOpacity(0.05),
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          30,
                                                        ),
                                                    border: Border.all(
                                                      color: gradientColors
                                                          .first
                                                          .withOpacity(0.5),
                                                      width: 1,
                                                    ),
                                                  ),
                                                  child: Row(
                                                    mainAxisSize:
                                                        MainAxisSize.min,
                                                    children: [
                                                      Icon(
                                                        Icons.tune_rounded,
                                                        color:
                                                            gradientColors.first,
                                                        size: 16,
                                                      ),
                                                      const SizedBox(width: 5),
                                                      Text(
                                                        selectedExpenseNames
                                                                .isNotEmpty
                                                            ? 'Filter (${selectedExpenseNames.length})'
                                                            : 'Filter',
                                                        style: TextStyle(
                                                          fontSize: 12,
                                                          fontWeight:
                                                              FontWeight.bold,
                                                          color: gradientColors.first,
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                              _buildAddNewButton(context),
                                            ],
                                          ),
                                          const SizedBox(height: 10),
                                        ],
                                      ),
                                    ),
                                    // Classic, Elegant & Modern Card-Based Tab Switcher
                                    hideCreditData
                                        ? Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 18,
                                              vertical: 6,
                                            ),
                                            child: Container(
                                              width: double.infinity,
                                              padding: const EdgeInsets.symmetric(
                                                horizontal: 16,
                                                vertical: 11,
                                              ),
                                              decoration: BoxDecoration(
                                                color: const Color(0xFFF8FAFC),
                                                borderRadius:
                                                    BorderRadius.circular(14),
                                                border: Border.all(
                                                  color: const Color(0xFFE2E8F0),
                                                  width: 0.8,
                                                ),
                                              ),
                                              child: Row(
                                                children: [
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.all(6),
                                                    decoration: BoxDecoration(
                                                      color: cardThemeColor,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            8,
                                                          ),
                                                    ),
                                                    child: const Icon(
                                                      Icons
                                                          .receipt_long_rounded,
                                                      size: 14,
                                                      color: Colors.white,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 10),
                                                  Text(
                                                    'DEBIT TRANSACTIONS',
                                                    style: TextStyle(
                                                      fontWeight: FontWeight.w700,
                                                      fontSize: 12,
                                                      letterSpacing: 0.8,
                                                      color: cardThemeColor,
                                                    ),
                                                  ),
                                                  const Spacer(),
                                                  Container(
                                                    padding:
                                                        const EdgeInsets.symmetric(
                                                          horizontal: 10,
                                                          vertical: 4,
                                                        ),
                                                    decoration: BoxDecoration(
                                                      color: Colors.white,
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                            12,
                                                          ),
                                                      border: Border.all(
                                                        color: cardThemeColor
                                                            .withValues(alpha: 0.25),
                                                      ),
                                                    ),
                                                    child: Text(
                                                      '${debitExpenses.length}',
                                                      style: TextStyle(
                                                        fontWeight: FontWeight.bold,
                                                        fontSize: 11.5,
                                                        color: cardThemeColor,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          )
                                        : Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 18,
                                              vertical: 6,
                                            ),
                                            child: Row(
                                              children: [
                                                // DEBIT CARD TAB
                                                Expanded(
                                                  child: GestureDetector(
                                                    onTap: () => setState(
                                                      () => _transactionTabIndex = 0,
                                                    ),
                                                    child: AnimatedContainer(
                                                      duration: const Duration(
                                                        milliseconds: 200,
                                                      ),
                                                      padding: const EdgeInsets.symmetric(
                                                        horizontal: 12,
                                                        vertical: 10,
                                                      ),
                                                      decoration: BoxDecoration(
                                                        borderRadius: BorderRadius.circular(
                                                          14,
                                                        ),
                                                        border: Border.all(
                                                          color: _transactionTabIndex == 0
                                                              ? cardThemeColor
                                                              : const Color(0xFFE2E8F0),
                                                          width: _transactionTabIndex == 0
                                                              ? 1
                                                              : 0.8,
                                                        ),
                                                        boxShadow: _transactionTabIndex == 0
                                                            ? [
                                                                BoxShadow(
                                                                  color: cardThemeColor
                                                                      .withValues(
                                                                        alpha: 0.05,
                                                                      ),
                                                                  blurRadius: 8,
                                                                  offset: const Offset(
                                                                    0,
                                                                    1,
                                                                  ),
                                                                ),
                                                              ]
                                                            : null,
                                                      ),
                                                      child: Row(
                                                        children: [
                                                          Container(
                                                            padding: const EdgeInsets.all(
                                                              5,
                                                            ),
                                                            decoration: BoxDecoration(
                                                              color: _transactionTabIndex == 0
                                                                  ? cardThemeColor
                                                                  : Colors.grey.shade200,
                                                              borderRadius: BorderRadius.circular(
                                                                7,
                                                              ),
                                                            ),
                                                            child: Icon(
                                                              Icons.receipt_long_rounded,
                                                              size: 13,
                                                              color: _transactionTabIndex == 0
                                                                  ? Colors.white
                                                                  : Colors.grey.shade600,
                                                            ),
                                                          ),
                                                          const SizedBox(width: 8),
                                                          Text(
                                                            'DEBIT',
                                                            style: TextStyle(
                                                              fontWeight: _transactionTabIndex == 0
                                                                  ? FontWeight.bold
                                                                  : FontWeight.w600,
                                                              fontSize: 11.5,
                                                              letterSpacing: 0.8,
                                                              color: _transactionTabIndex == 0
                                                                  ? cardThemeColor
                                                                  : const Color(0xFF64748B),
                                                            ),
                                                          ),
                                                          const Spacer(),
                                                          Container(
                                                            padding: const EdgeInsets.symmetric(
                                                              horizontal: 8,
                                                              vertical: 3,
                                                            ),
                                                            decoration: BoxDecoration(
                                                              color: Colors.white,
                                                              borderRadius: BorderRadius.circular(
                                                                10,
                                                              ),
                                                              border: Border.all(
                                                                color: _transactionTabIndex == 0
                                                                    ? cardThemeColor
                                                                        .withValues(alpha: 0.25)
                                                                    : Colors.grey.shade200,
                                                              ),
                                                            ),
                                                            child: Text(
                                                              '${debitExpenses.length}',
                                                              style: TextStyle(
                                                                fontWeight: FontWeight.bold,
                                                                fontSize: 11,
                                                                color: _transactionTabIndex == 0
                                                                    ? cardThemeColor
                                                                    : const Color(0xFF64748B),
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 10),
                                                // CREDIT CARD TAB
                                                Expanded(
                                                  child: GestureDetector(
                                                    onTap: () => setState(
                                                      () => _transactionTabIndex = 1,
                                                    ),
                                                    child: AnimatedContainer(
                                                      duration: const Duration(
                                                        milliseconds: 200,
                                                      ),
                                                      padding: const EdgeInsets.symmetric(
                                                        horizontal: 12,
                                                        vertical: 10,
                                                      ),
                                                      decoration: BoxDecoration(
                                                        borderRadius: BorderRadius.circular(
                                                          14,
                                                        ),
                                                        border: Border.all(
                                                          color: _transactionTabIndex == 1
                                                              ? cardThemeColor
                                                              : const Color(0xFFE2E8F0),
                                                          width: _transactionTabIndex == 1
                                                              ? 1
                                                              : 0.8,
                                                        ),
                                                        boxShadow: _transactionTabIndex == 1
                                                            ? [
                                                          BoxShadow(
                                                            color: cardThemeColor
                                                                .withValues(
                                                              alpha: 0.05,
                                                            ),
                                                            blurRadius: 8,
                                                            offset: const Offset(
                                                              0,
                                                              1,
                                                            ),
                                                          ),
                                                        ]
                                                            : null,
                                                      ),
                                                      child: Row(
                                                        children: [
                                                          Container(
                                                            padding: const EdgeInsets.all(
                                                              5,
                                                            ),
                                                            decoration: BoxDecoration(
                                                              color: _transactionTabIndex == 1
                                                                  ? cardThemeColor
                                                                  : Colors.grey.shade200,
                                                              borderRadius: BorderRadius.circular(
                                                                7,
                                                              ),
                                                            ),
                                                            child: Icon(
                                                              Icons.account_balance_wallet_rounded,
                                                              size: 13,
                                                              color: _transactionTabIndex == 1
                                                                  ? Colors.white
                                                                  : Colors.grey.shade600,
                                                            ),
                                                          ),
                                                          const SizedBox(width: 8),
                                                          Text(
                                                            'CREDIT',
                                                            style: TextStyle(
                                                              fontWeight: _transactionTabIndex == 1
                                                                  ? FontWeight.bold
                                                                  : FontWeight.w600,
                                                              fontSize: 11.5,
                                                              letterSpacing: 0.8,
                                                              color: _transactionTabIndex == 1
                                                                  ? cardThemeColor
                                                                  : const Color(0xFF64748B),
                                                            ),
                                                          ),
                                                          const Spacer(),
                                                          Container(
                                                            padding: const EdgeInsets.symmetric(
                                                              horizontal: 8,
                                                              vertical: 3,
                                                            ),
                                                            decoration: BoxDecoration(
                                                              color: Colors.white,
                                                              borderRadius: BorderRadius.circular(
                                                                10,
                                                              ),
                                                              border: Border.all(
                                                                color: _transactionTabIndex == 1
                                                                    ? cardThemeColor
                                                                        .withValues(alpha: 0.25)
                                                                    : Colors.grey.shade200,
                                                              ),
                                                            ),
                                                            child: Text(
                                                              '${creditExpenses.length}',
                                                              style: TextStyle(
                                                                fontWeight: FontWeight.bold,
                                                                fontSize: 11,
                                                                color: _transactionTabIndex == 1
                                                                    ? cardThemeColor
                                                                    : const Color(0xFF64748B),
                                                              ),
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                  const SizedBox(height: 8),
                                ],
                              ),
                            ),
                          ),
                        ),
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(15, 0, 15, 30),
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: const BorderRadius.vertical(
                                  bottom: Radius.circular(24),
                                ),
                                border: Border(
                                  left: BorderSide(
                                    color: Colors.grey.shade100,
                                    width: 1,
                                  ),
                                  right: BorderSide(
                                    color: Colors.grey.shade100,
                                    width: 1,
                                  ),
                                  bottom: BorderSide(
                                    color: Colors.grey.shade100,
                                    width: 1,
                                  ),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.02),
                                    blurRadius: 12,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: (!hideCreditData &&
                                      _transactionTabIndex == 1)
                                  ? _buildTransactionList(creditExpenses)
                                  : _buildTransactionList(debitExpenses),
                            ),
                          ),
                        ),
                      ],
                    ],
                    if (visibleCards.isEmpty) ...[
                      SliverToBoxAdapter(
                        child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        children: [
                          const Text(
                            'TRANSACTIONS',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1E293B),
                              fontSize: 13,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              _buildSyncButton(context),
                              _buildAddNewButton(context),
                            ],
                          ),
                          const SizedBox(height: 16),
                          // Welcome & Action Container
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(22),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: const Color(0xFFE2E8F0),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.03),
                                  blurRadius: 16,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: Column(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.shade50,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.credit_card_rounded,
                                    size: 36,
                                    color: Colors.blue.shade600,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                const Text(
                                  'No Cards Configured',
                                  style: TextStyle(
                                    fontSize: 19,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF0F172A),
                                    letterSpacing: -0.3,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Select your active bank cards from settings to automatically sync SMS and track your monthly spending.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: Colors.grey.shade600,
                                    height: 1.4,
                                  ),
                                ),
                                const SizedBox(height: 20),
                                ElevatedButton.icon(
                                  onPressed: () => _openDrawer(3),
                                  icon: const Icon(
                                    Icons.tune_rounded,
                                    size: 18,
                                    color: Colors.white,
                                  ),
                                  label: const Text(
                                    'Configure Cards Now',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13.5,
                                    ),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF0F172A),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 24,
                                      vertical: 14,
                                    ),
                                    elevation: 4,
                                    shadowColor: Colors.black.withValues(
                                      alpha: 0.3,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(14),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 24),

                          // Header Title for Features Section
                          Row(
                            children: const [
                              Icon(
                                Icons.stars_rounded,
                                color: Color(0xFF2563EB),
                                size: 18,
                              ),
                              SizedBox(width: 8),
                              Text(
                                'KEY APP FEATURES',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF94A3B8),
                                  letterSpacing: 1.2,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),

                          // 2x2 Feature Showcase Grid
                          GridView(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 12,
                                  childAspectRatio: 1.2,
                                ),
                            children: [
                              _buildFeatureCard(
                                icon: Icons.sms_rounded,
                                iconColor: const Color(0xFF2563EB),
                                title: 'Smart SMS Sync',
                                subtitle:
                                    'Auto-reads bank SMS alerts for debits & credits.',
                              ),
                              _buildFeatureCard(
                                icon: Icons.pie_chart_rounded,
                                iconColor: const Color(0xFF9333EA),
                                title: 'Category Budgets',
                                subtitle:
                                    'Group expenses into Shopping, Rent & set limits.',
                              ),
                              _buildFeatureCard(
                                icon: Icons.insights_rounded,
                                iconColor: const Color(0xFF0D9488),
                                title: 'Visual Analytics',
                                subtitle:
                                    'Weekly & monthly charts with boundary alerts.',
                              ),
                              _buildFeatureCard(
                                icon: Icons.security_rounded,
                                iconColor: const Color(0xFF16A34A),
                                title: '100% Private',
                                subtitle:
                                    'All data stays on your device. Zero cloud sync.',
                              ),
                            ],
                          ),

                          const SizedBox(height: 24),

                          // App Information Card
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: const Color(0xFFE2E8F0),
                              ),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(10),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.shade50,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    Icons.info_outline_rounded,
                                    color: Colors.blue.shade700,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Expense Tracker AI v1.2.0',
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.bold,
                                          color: Color(0xFF0F172A),
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'Offline-First Expense Engine • Material 3 UI',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SliverToBoxAdapter(
                    child: SizedBox(height: 30),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  void _showConfigureCardAlertDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          elevation: 12,
          backgroundColor: Colors.white,
          child: Container(
            width: MediaQuery.of(context).size.width * 0.85,
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.credit_card_off_rounded,
                    color: Colors.amber.shade800,
                    size: 32,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Configure Card Required',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF0F172A),
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'No bank card is configured or added yet. Please add or enable a card in Settings before adding expenses.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: Colors.grey.shade600,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          side: const BorderSide(color: Color(0xFFCBD5E1)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: () => Navigator.pop(context),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF475569),
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          backgroundColor: const Color(0xFF0F172A),
                          elevation: 4,
                          shadowColor: Colors.black.withValues(alpha: 0.3),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: () {
                          Navigator.pop(context);
                          _openDrawer(3);
                        },
                        icon: const Icon(
                          Icons.tune_rounded,
                          size: 16,
                          color: Colors.white,
                        ),
                        label: const Text(
                          'Configure Card',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAddNewButton(BuildContext context) {
    final bool isConfigured = visibleCards.isNotEmpty;
    final List<Color> gradientColors = getCardThemeGradient(cardName);
    final Color textColor = isConfigured
        ? Colors.white
        : const Color(0xFF94A3B8);

    return GestureDetector(
      onTap: () {
        if (!isConfigured) {
          _showConfigureCardAlertDialog(context);
        } else {
          addAlertDialog(
            context: context,
            ref: ref,
            visibleBanks: visibleCards,
            initialBank: cardName,
            groupColors: groupColors,
            categoryGroups: categoryGroups,
            onGroupAssigned: (merchant, group) async {
              setState(() {
                categoryGroups[merchant.trim().toUpperCase()] = group;
              });
              await _saveSettings();
            },
          );
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          gradient: isConfigured
              ? LinearGradient(
                  colors: gradientColors,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null,
          color: isConfigured ? null : const Color(0xFFE2E8F0),
          border: Border.all(
            color: isConfigured ? Colors.transparent : const Color(0xFFCBD5E1),
            width: 1,
          ),
          boxShadow: isConfigured
              ? [
                  BoxShadow(
                    color: gradientColors.last.withValues(alpha: 0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.add_rounded, size: 14, color: textColor),
            const SizedBox(width: 5),
            Text(
              'ADD NEW',
              style: TextStyle(
                color: textColor,
                fontSize: 10.5,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSyncButton(BuildContext context) {
    final List<Color> gradientColors = getCardThemeGradient(cardName);
    final primaryColor = gradientColors.first;

    return Tooltip(
      message: 'Sync SMS & Notifications',
      child: GestureDetector(
        onTap: _isSyncing ? null : _syncSms,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6.5),
          decoration: BoxDecoration(
            color: _isSyncing
                ? primaryColor.withValues(alpha: 0.12)
                : primaryColor.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(
              color: _isSyncing
                  ? primaryColor.withValues(alpha: 0.6)
                  : primaryColor.withValues(alpha: 0.4),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_isSyncing)
                SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                  ),
                )
              else
                Icon(
                  Icons.sync_rounded,
                  size: 15,
                  color: primaryColor,
                ),
              const SizedBox(width: 5),
              Text(
                _isSyncing ? 'SYNCING...' : 'SYNC',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                  color: primaryColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureCard({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.bold,
              color: Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey.shade600,
              height: 1.2,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionList(List<Expense> expenses) {
    final gradientColors = getCardThemeGradient(cardName);

    if (expenses.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(20),
        child: Center(
          child: Text(
            'No transactions for this selection',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      itemCount: expenses.length,
      separatorBuilder: (context, index) => const SizedBox.shrink(),
      itemBuilder: (context, index) {
        final expense = expenses[index];
        final bool showHeader =
            index == 0 ||
            expenses[index - 1].date.day != expense.date.day ||
            expenses[index - 1].date.month != expense.date.month ||
            expenses[index - 1].date.year != expense.date.year;

        return Column(
          children: [
            if (showHeader)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Expanded(child: Divider(color: Colors.grey.shade200)),
                    const SizedBox(width: 10),
                    Text(
                      DateFormat(
                        'dd/MMM/yyyy',
                      ).format(expense.date).toUpperCase(),
                      style: const TextStyle(
                        color: Colors.grey,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Divider(color: Colors.grey.shade200)),
                  ],
                ),
              ),
            TransactionItem(
              expense: expense,
              isDueDateFiltered: isDueDateFiltered,
              categoryGroups: categoryGroups,
              transactionGroups: transactionGroups,
              groupColors: groupColors,
              onDelete: (id) => _showDeleteConfirmation(context, id),
              onGroup: (name) => _showGroupingDialog(
                context,
                targetNames: [name],
                expenseId: expense.id,
              ),
              onEdit: (exp) {
                final normalizedName = exp.name.trim().toUpperCase();
                final currentGroup =
                    transactionGroups[exp.id] ?? categoryGroups[normalizedName];
                addAlertDialog(
                  context: context,
                  ref: ref,
                  visibleBanks: visibleCards,
                  initialBank: exp.bank,
                  groupColors: groupColors,
                  categoryGroups: categoryGroups,
                  expenseToEdit: exp,
                  initialGroup: currentGroup,
                  onGroupAssigned: (merchant, group) async {
                    setState(() {
                      categoryGroups[merchant.trim().toUpperCase()] = group;
                    });
                    await _saveSettings();
                  },
                );
              },
              gradient: LinearGradient(colors: gradientColors),
            ),
          ],
        );
      },
    );
  }

  void _showDeleteConfirmation(BuildContext context, String id) async {
    final confirm = await _showAttractiveDeleteDialog(
      context: context,
      title: 'Delete Transaction',
      itemName: '',
      message:
          'Are you sure you want to delete this transaction? This action cannot be undone.',
      icon: Icons.delete_forever_rounded,
      deleteButtonText: 'Delete',
    );
    if (confirm == true && context.mounted) {
      ref.read(expenseNotifierProvider.notifier).deleteExpense(id);
    }
  }

  void _confirmDeleteMerchant(
    BuildContext context,
    String merchantName,
    StateSetter setDrawerState,
  ) async {
    HapticFeedback.mediumImpact();
    final confirm = await _showAttractiveDeleteDialog(
      context: context,
      title: 'Delete Merchant?',
      itemName: merchantName,
      message:
          'Are you sure you want to delete all transactions for "$merchantName"? This action cannot be undone.',
      icon: Icons.storefront_rounded,
      deleteButtonText: 'Delete All',
    );
    if (confirm == true && context.mounted) {
      _deleteMerchantAndTransactions(merchantName, setDrawerState);
    }
  }

  void _deleteMerchantAndTransactions(
    String merchantName,
    StateSetter setDrawerState,
  ) {
    final normMerchant = merchantName.trim().toUpperCase();
    final state = ref.read(expenseNotifierProvider);
    if (state is ExpenseLoaded) {
      final toDelete = state.data.expenses.where((e) {
        final dispName = e.name
            .replaceAll(RegExp(r'\s*\(?UPI\)?', caseSensitive: false), '')
            .trim();
        return e.name.trim().toUpperCase() == normMerchant ||
            dispName.toUpperCase() == normMerchant ||
            e.name.toLowerCase() == merchantName.toLowerCase() ||
            matchesExpenseNameFilter(e.name, [merchantName]);
      }).toList();

      for (final exp in toDelete) {
        ref.read(expenseNotifierProvider.notifier).deleteExpense(exp.id);
      }
    }

    setDrawerState(() {
      _tempSelectedExpenseNames?.remove(merchantName);
    });
    setState(() {
      selectedExpenseNames.remove(merchantName);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Deleted merchant "$merchantName"'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        backgroundColor: Colors.red.shade700,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showEditGroupDialog(BuildContext context, String currentGroupName) {
    final TextEditingController nameController =
        TextEditingController(text: currentGroupName);
    final double? currentLimit = groupLimits[currentGroupName];
    final TextEditingController limitController = TextEditingController(
      text: (currentLimit != null && currentLimit > 0)
          ? currentLimit.toStringAsFixed(0)
          : '',
    );
    int selectedColor =
        groupColors[currentGroupName] ?? Colors.blue.toARGB32();
    String? nameError;
    String? colorError;

    final List<Color> colors = [
      const Color(0xFF2563EB), // Royal Blue
      const Color(0xFFDC2626), // Crimson Red
      const Color(0xFF16A34A), // Emerald Green
      const Color(0xFFD97706), // Amber Gold
      const Color(0xFF9333EA), // Deep Purple
      const Color(0xFF0D9488), // Teal
      const Color(0xFFDB2777), // Rose Pink
      const Color(0xFF4F46E5), // Indigo
      const Color(0xFFEA580C), // Sunset Orange
      const Color(0xFF0891B2), // Cyan
      const Color(0xFF84CC16), // Lime Green
      const Color(0xFF7C3AED), // Violet
      const Color(0xFFB45309), // Bronze
      const Color(0xFF0284C7), // Sky Blue
      const Color(0xFF475569), // Slate Gray
      const Color(0xFFE11D48), // Ruby Coral
    ];

    bool showCustomPicker =
        !colors.any((c) => c.toARGB32() == selectedColor);

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final activeColor = Color(selectedColor);
            final assignedMerchants = categoryGroups.entries
                .where((e) => e.value == currentGroupName)
                .map((e) => e.key)
                .toList();

            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              elevation: 12,
              backgroundColor: Colors.white,
              child: Container(
                width: MediaQuery.of(context).size.width * 0.88,
                padding: const EdgeInsets.all(22),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header Badge & Title
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: activeColor.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: Image.asset(
                              'assets/edit_icon.png',
                              color: activeColor,
                              width: 22,
                              height: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Edit Label & Group',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                    color: Color(0xFF0F172A),
                                    letterSpacing: -0.3,
                                  ),
                                ),
                                Text(
                                  currentGroupName,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              color: Colors.red,
                              size: 20,
                            ),
                            tooltip: 'Delete Group',
                            visualDensity: VisualDensity.compact,
                            onPressed: () async {
                              final confirm = await _showAttractiveDeleteDialog(
                                context: context,
                                title: 'Delete Group',
                                itemName: currentGroupName,
                                message:
                                    'Are you sure you want to delete the group "$currentGroupName"? Merchants assigned to this group will become unassigned.',
                              );
                              if (confirm == true) {
                                setState(() {
                                  categoryGroups.removeWhere(
                                    (m, g) => g == currentGroupName,
                                  );
                                  transactionGroups.removeWhere(
                                    (t, g) => g == currentGroupName,
                                  );
                                  groupColors.remove(currentGroupName);
                                  groupLimits.remove(currentGroupName);
                                  _cachedUniqueNames = null;
                                  _cachedLabelGroups = null;
                                });
                                await _saveSettings();
                                if (context.mounted) {
                                  Navigator.pop(context);
                                }
                              }
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      const Text(
                        'LABEL NAME',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF94A3B8),
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 8),

                      TextField(
                        controller: nameController,
                        onChanged: (_) {
                          if (nameError != null) {
                            setDialogState(() => nameError = null);
                          }
                        },
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                        decoration: InputDecoration(
                          hintText: 'e.g. Shopping, Rent',
                          hintStyle: TextStyle(
                            color: Colors.grey.shade400,
                            fontSize: 13,
                          ),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          prefixIcon: const Icon(
                            Icons.label_outline_rounded,
                            size: 20,
                            color: Color(0xFF64748B),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(
                              color: nameError != null
                                  ? Colors.red
                                  : const Color(0xFFE2E8F0),
                              width: nameError != null ? 1.5 : 1.0,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(
                              color: nameError != null
                                  ? Colors.red
                                  : Colors.blue.shade600,
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                      if (nameError != null) ...[
                        const SizedBox(height: 5),
                        Row(
                          children: [
                            const Icon(
                              Icons.error_outline_rounded,
                              color: Colors.red,
                              size: 13,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              nameError!,
                              style: const TextStyle(
                                color: Colors.red,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 16),

                      const Text(
                        'MONTHLY BUDGET LIMIT',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF94A3B8),
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 8),

                      TextField(
                        controller: limitController,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Set monthly budget (optional)',
                          hintStyle: TextStyle(
                            color: Colors.grey.shade400,
                            fontSize: 13,
                          ),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          prefixIcon: const Icon(
                            Icons.account_balance_wallet_outlined,
                            size: 20,
                            color: Color(0xFF64748B),
                          ),
                          prefixText: '₹ ',
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: Color(0xFFE2E8F0),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(
                              color: Colors.blue.shade600,
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Theme Color Section
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'THEME COLOR',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF94A3B8),
                              letterSpacing: 1.2,
                            ),
                          ),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Container(
                                height: 26,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: const Color(0xFFE2E8F0),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Container(
                                      width: 12,
                                      height: 12,
                                      decoration: BoxDecoration(
                                        color: Color(selectedColor),
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: Colors.white,
                                          width: 1.5,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Color(selectedColor)
                                                .withValues(alpha: 0.3),
                                            blurRadius: 4,
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      '#${(selectedColor & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}',
                                      style: const TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.bold,
                                        fontFamily: 'monospace',
                                        color: Color(0xFF334155),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              InkWell(
                                onTap: () {
                                  setDialogState(() {
                                    showCustomPicker = !showCustomPicker;
                                  });
                                },
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  height: 26,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: showCustomPicker
                                        ? const Color(0xFFEFF6FF)
                                        : const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: showCustomPicker
                                          ? const Color(0xFF3B82F6)
                                          : const Color(0xFFCBD5E1),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      Icon(
                                        showCustomPicker
                                            ? Icons.palette_outlined
                                            : Icons.colorize_rounded,
                                        size: 13,
                                        color: showCustomPicker
                                            ? const Color(0xFF2563EB)
                                            : const Color(0xFF475569),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        showCustomPicker
                                            ? 'Presets'
                                            : 'Color Picker',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: showCustomPicker
                                              ? const Color(0xFF2563EB)
                                              : const Color(0xFF475569),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      if (showCustomPicker) ...[
                        SimpleColorSliderPicker(
                          pickerColor: Color(selectedColor),
                          onColorChanged: (newColor) {
                            setDialogState(() {
                              selectedColor = newColor.toARGB32();
                              colorError = null;
                            });
                          },
                        ),
                      ] else ...[
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            ...colors.map((color) {
                              final isSelected =
                                  selectedColor == color.toARGB32();
                              return GestureDetector(
                                onTap: () {
                                  setDialogState(() {
                                    selectedColor = color.toARGB32();
                                    colorError = null;
                                  });
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 150),
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: color,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isSelected
                                          ? const Color(0xFF0F172A)
                                          : Colors.transparent,
                                      width: isSelected ? 2.5 : 0,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: color.withValues(
                                          alpha: isSelected ? 0.45 : 0.2,
                                        ),
                                        blurRadius: isSelected ? 8 : 4,
                                        offset: const Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                  child: isSelected
                                      ? const Icon(
                                          Icons.check_rounded,
                                          color: Colors.white,
                                          size: 18,
                                        )
                                      : null,
                                ),
                              );
                            }),
                            GestureDetector(
                              onTap: () {
                                setDialogState(() {
                                  showCustomPicker = true;
                                });
                              },
                              child: Tooltip(
                                message: 'Open Color Picker',
                                child: Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: const SweepGradient(
                                      colors: [
                                        Colors.red,
                                        Colors.amber,
                                        Colors.green,
                                        Colors.cyan,
                                        Colors.blue,
                                        Colors.purple,
                                        Colors.red,
                                      ],
                                    ),
                                    border: Border.all(
                                      color: !colors.any((c) =>
                                              c.toARGB32() == selectedColor)
                                          ? const Color(0xFF0F172A)
                                          : const Color(0xFFCBD5E1),
                                      width: !colors.any((c) =>
                                              c.toARGB32() == selectedColor)
                                          ? 2.5
                                          : 1.5,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black
                                            .withValues(alpha: 0.1),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Center(
                                    child: Container(
                                      width: 22,
                                      height: 22,
                                      decoration: BoxDecoration(
                                        color: !colors.any((c) =>
                                                c.toARGB32() == selectedColor)
                                            ? Color(selectedColor)
                                            : Colors.white,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        !colors.any((c) =>
                                                c.toARGB32() == selectedColor)
                                            ? Icons.check_rounded
                                            : Icons.colorize_rounded,
                                        size: 13,
                                        color: !colors.any((c) =>
                                                c.toARGB32() == selectedColor)
                                            ? Colors.white
                                            : const Color(0xFF334155),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (colorError != null) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(
                              Icons.error_outline_rounded,
                              color: Colors.red,
                              size: 13,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              colorError!,
                              style: const TextStyle(
                                color: Colors.red,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 16),

                      // Assigned Merchants overview
                      if (assignedMerchants.isNotEmpty) ...[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'LINKED MERCHANTS',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF94A3B8),
                                letterSpacing: 1.2,
                              ),
                            ),
                            Text(
                              '${assignedMerchants.length} linked',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: assignedMerchants.map((m) {
                            return Chip(
                              label: Text(
                                m,
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.black87,
                                ),
                              ),
                              deleteIcon: const Icon(
                                Icons.close,
                                size: 12,
                                color: Colors.black54,
                              ),
                              onDeleted: () {
                                setState(() {
                                  categoryGroups.remove(m);
                                });
                                setDialogState(() {});
                                _saveSettings();
                              },
                              backgroundColor:
                                  activeColor.withValues(alpha: 0.1),
                              side: BorderSide(
                                color: activeColor.withValues(alpha: 0.25),
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              visualDensity: VisualDensity.compact,
                            );
                          }).toList(),
                        ),
                      ],

                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                side:
                                    const BorderSide(color: Color(0xFFCBD5E1)),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              onPressed: () => Navigator.pop(context),
                              child: const Text(
                                'Cancel',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF475569),
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                backgroundColor: const Color(0xFF0F172A),
                                elevation: 4,
                                shadowColor: Colors.black.withValues(alpha: 0.3),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              onPressed: () async {
                                final newName = nameController.text.trim();
                                if (newName.isEmpty) {
                                  setDialogState(() {
                                    nameError = 'Label name cannot be empty';
                                  });
                                  return;
                                }

                                if (newName.toLowerCase() !=
                                        currentGroupName.toLowerCase() &&
                                    groupColors.keys.any((k) =>
                                        k.toLowerCase() ==
                                        newName.toLowerCase())) {
                                  setDialogState(() {
                                    nameError =
                                        'A group named "$newName" already exists';
                                  });
                                  return;
                                }

                                final parsedLimit =
                                    double.tryParse(limitController.text) ??
                                        0.0;

                                setState(() {
                                  if (newName != currentGroupName) {
                                    // Update categoryGroups
                                    final toUpdateCat = <String>[];
                                    categoryGroups.forEach((k, v) {
                                      if (v == currentGroupName) {
                                        toUpdateCat.add(k);
                                      }
                                    });
                                    for (var k in toUpdateCat) {
                                      categoryGroups[k] = newName;
                                    }

                                    // Update transactionGroups
                                    final toUpdateTx = <String>[];
                                    transactionGroups.forEach((k, v) {
                                      if (v == currentGroupName) {
                                        toUpdateTx.add(k);
                                      }
                                    });
                                    for (var k in toUpdateTx) {
                                      transactionGroups[k] = newName;
                                    }

                                    // Remove old keys
                                    groupColors.remove(currentGroupName);
                                    groupLimits.remove(currentGroupName);

                                    // Update temp selections if present
                                    if (_tempSelectedExpenseNames != null) {
                                      final idx = _tempSelectedExpenseNames!
                                          .indexOf(currentGroupName);
                                      if (idx != -1) {
                                        _tempSelectedExpenseNames![idx] =
                                            newName;
                                      }
                                    }
                                  }

                                  groupColors[newName] = selectedColor;
                                  groupLimits[newName] = parsedLimit;

                                  _cachedUniqueNames = null;
                                  _cachedLabelGroups = null;
                                });

                                await _saveSettings();

                                if (context.mounted) {
                                  Navigator.pop(context);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Updated group "$newName"'),
                                      behavior: SnackBarBehavior.floating,
                                      shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(10),
                                      ),
                                      duration: const Duration(seconds: 2),
                                    ),
                                  );
                                }
                              },
                              child: const Text(
                                'Save Changes',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showGroupingDialog(
    BuildContext context, {
    List<String>? targetNames,
    String? expenseId,
  }) {
    final namesToGroup = targetNames ?? selectedExpenseNames;
    final TextEditingController labelController = TextEditingController();
    final TextEditingController limitController = TextEditingController();
    int selectedColor = Colors.blue.toARGB32();
    bool applyToAll = true;
    String? nameError;
    String? colorError;

    final normalizedFirstName = namesToGroup.isNotEmpty
        ? namesToGroup[0].trim().toUpperCase()
        : null;

    // Check for existing group
    String? existingGroup;
    if (expenseId != null && transactionGroups.containsKey(expenseId)) {
      existingGroup = transactionGroups[expenseId];
    } else if (normalizedFirstName != null &&
        categoryGroups.containsKey(normalizedFirstName)) {
      existingGroup = categoryGroups[normalizedFirstName];
    }

    if (existingGroup != null) {
      labelController.text = existingGroup;
      selectedColor = groupColors[existingGroup] ?? Colors.blue.toARGB32();
      limitController.text =
          groupLimits[existingGroup]?.toStringAsFixed(0) ?? '';
    }

    final List<Color> colors = [
      const Color(0xFF2563EB), // Royal Blue
      const Color(0xFFDC2626), // Crimson Red
      const Color(0xFF16A34A), // Emerald Green
      const Color(0xFFD97706), // Amber Gold
      const Color(0xFF9333EA), // Deep Purple
      const Color(0xFF0D9488), // Teal
      const Color(0xFFDB2777), // Rose Pink
      const Color(0xFF4F46E5), // Indigo
      const Color(0xFFEA580C), // Sunset Orange
      const Color(0xFF0891B2), // Cyan
      const Color(0xFF84CC16), // Lime Green
      const Color(0xFF7C3AED), // Violet
      const Color(0xFFB45309), // Bronze
      const Color(0xFF0284C7), // Sky Blue
      const Color(0xFF475569), // Slate Gray
      const Color(0xFFE11D48), // Ruby Coral
    ];

    bool showCustomPicker =
        !colors.any((c) => c.toARGB32() == selectedColor);

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              elevation: 12,
              backgroundColor: Colors.white,
              child: Container(
                width: MediaQuery.of(context).size.width * 0.85,
                padding: const EdgeInsets.all(22),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header Badge & Title
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade50,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.label_rounded,
                              color: Colors.blue.shade700,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              namesToGroup.isEmpty
                                  ? 'Create Label'
                                  : 'Group Selection',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                                color: Color(0xFF0F172A),
                                letterSpacing: -0.3,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),

                      const Text(
                        'NAME & BUDGET',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF94A3B8),
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 10),

                      // Label Name Input with Validation
                      TextField(
                        controller: labelController,
                        onChanged: (_) {
                          if (nameError != null) {
                            setDialogState(() => nameError = null);
                          }
                        },
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                        decoration: InputDecoration(
                          hintText: 'e.g. Shopping, Rent',
                          hintStyle: TextStyle(
                            color: Colors.grey.shade400,
                            fontSize: 13,
                          ),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          prefixIcon: const Icon(
                            Icons.edit_note_rounded,
                            size: 20,
                            color: Color(0xFF64748B),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(
                              color: nameError != null
                                  ? Colors.red
                                  : const Color(0xFFE2E8F0),
                              width: nameError != null ? 1.5 : 1.0,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(
                              color: nameError != null
                                  ? Colors.red
                                  : Colors.blue.shade600,
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                      if (nameError != null) ...[
                        const SizedBox(height: 5),
                        Row(
                          children: [
                            const Icon(
                              Icons.error_outline_rounded,
                              color: Colors.red,
                              size: 13,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              nameError!,
                              style: const TextStyle(
                                color: Colors.red,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 12),

                      // Monthly Limit Input
                      TextField(
                        controller: limitController,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Optional monthly limit',
                          hintStyle: TextStyle(
                            color: Colors.grey.shade400,
                            fontSize: 13,
                          ),
                          filled: true,
                          fillColor: const Color(0xFFF8FAFC),
                          prefixIcon: const Icon(
                            Icons.account_balance_wallet_outlined,
                            size: 20,
                            color: Color(0xFF64748B),
                          ),
                          prefixText: '₹ ',
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: Color(0xFFE2E8F0),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(
                              color: Colors.blue.shade600,
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),

                      if (groupColors.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        const Text(
                          'EXISTING LABELS',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF94A3B8),
                            letterSpacing: 1.2,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: groupColors.keys.map((label) {
                            final color = Color(groupColors[label]!);
                            final isSelected = labelController.text == label;
                            return GestureDetector(
                              onTap: () {
                                setDialogState(() {
                                  if (isSelected) {
                                    labelController.clear();
                                    limitController.clear();
                                    selectedColor = Colors.blue.value;
                                  } else {
                                    labelController.text = label;
                                    selectedColor = groupColors[label]!;
                                    limitController.text =
                                        groupLimits[label]?.toStringAsFixed(
                                          0,
                                        ) ??
                                        '';
                                  }
                                  nameError = null;
                                  colorError = null;
                                });
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? color.withOpacity(0.12)
                                      : const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isSelected
                                        ? color
                                        : const Color(0xFFE2E8F0),
                                    width: isSelected ? 1.8 : 1.0,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Container(
                                      width: 10,
                                      height: 10,
                                      decoration: BoxDecoration(
                                        color: color,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      label,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: isSelected
                                            ? FontWeight.bold
                                            : FontWeight.w500,
                                        color: isSelected
                                            ? color
                                            : const Color(0xFF334155),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],

                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Text(
                                'THEME COLOR',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF94A3B8),
                                  letterSpacing: 1.2,
                                ),
                              ),
                              const Text(
                                ' *',
                                style: TextStyle(
                                  color: Colors.red,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Container(
                                height: 26,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1F5F9),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                    color: const Color(0xFFE2E8F0),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Container(
                                      width: 12,
                                      height: 12,
                                      decoration: BoxDecoration(
                                        color: Color(selectedColor),
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: Colors.white,
                                          width: 1.5,
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Color(selectedColor)
                                                .withValues(alpha: 0.3),
                                            blurRadius: 4,
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      '#${(selectedColor & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}',
                                      style: const TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.bold,
                                        fontFamily: 'monospace',
                                        color: Color(0xFF334155),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 6),
                              InkWell(
                                onTap: () {
                                  setDialogState(() {
                                    showCustomPicker = !showCustomPicker;
                                  });
                                },
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  height: 26,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: showCustomPicker
                                        ? const Color(0xFFEFF6FF)
                                        : const Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: showCustomPicker
                                          ? const Color(0xFF3B82F6)
                                          : const Color(0xFFCBD5E1),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      Icon(
                                        showCustomPicker
                                            ? Icons.palette_outlined
                                            : Icons.colorize_rounded,
                                        size: 13,
                                        color: showCustomPicker
                                            ? const Color(0xFF2563EB)
                                            : const Color(0xFF475569),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        showCustomPicker
                                            ? 'Presets'
                                            : 'Color Picker',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: showCustomPicker
                                              ? const Color(0xFF2563EB)
                                              : const Color(0xFF475569),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      if (showCustomPicker) ...[
                        SimpleColorSliderPicker(
                          pickerColor: Color(selectedColor),
                          onColorChanged: (newColor) {
                            setDialogState(() {
                              selectedColor = newColor.toARGB32();
                              colorError = null;
                            });
                          },
                        ),
                      ] else ...[
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            ...colors.map((color) {
                              final isSelected =
                                  selectedColor == color.toARGB32();
                              return GestureDetector(
                                onTap: () {
                                  setDialogState(() {
                                    selectedColor = color.toARGB32();
                                    colorError = null;
                                  });
                                },
                                child: AnimatedContainer(
                                  duration:
                                      const Duration(milliseconds: 150),
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: color,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: isSelected
                                          ? const Color(0xFF0F172A)
                                          : Colors.transparent,
                                      width: isSelected ? 2.5 : 0,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: color.withValues(
                                          alpha: isSelected ? 0.45 : 0.2,
                                        ),
                                        blurRadius: isSelected ? 8 : 4,
                                        offset: const Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                  child: isSelected
                                      ? const Icon(
                                          Icons.check_rounded,
                                          color: Colors.white,
                                          size: 18,
                                        )
                                      : null,
                                ),
                              );
                            }),
                            GestureDetector(
                              onTap: () {
                                setDialogState(() {
                                  showCustomPicker = true;
                                });
                              },
                              child: Tooltip(
                                message: 'Open Color Picker',
                                child: Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: const SweepGradient(
                                      colors: [
                                        Colors.red,
                                        Colors.amber,
                                        Colors.green,
                                        Colors.cyan,
                                        Colors.blue,
                                        Colors.purple,
                                        Colors.red,
                                      ],
                                    ),
                                    border: Border.all(
                                      color: !colors.any((c) =>
                                              c.toARGB32() == selectedColor)
                                          ? const Color(0xFF0F172A)
                                          : const Color(0xFFCBD5E1),
                                      width: !colors.any((c) =>
                                              c.toARGB32() == selectedColor)
                                          ? 2.5
                                          : 1.5,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black
                                            .withValues(alpha: 0.1),
                                        blurRadius: 4,
                                        offset: const Offset(0, 2),
                                      ),
                                    ],
                                  ),
                                  child: Center(
                                    child: Container(
                                      width: 22,
                                      height: 22,
                                      decoration: BoxDecoration(
                                        color: !colors.any((c) =>
                                                c.toARGB32() ==
                                                selectedColor)
                                            ? Color(selectedColor)
                                            : Colors.white,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        !colors.any((c) =>
                                                c.toARGB32() ==
                                                selectedColor)
                                            ? Icons.check_rounded
                                            : Icons.colorize_rounded,
                                        size: 13,
                                        color: !colors.any((c) =>
                                                c.toARGB32() ==
                                                selectedColor)
                                            ? Colors.white
                                            : const Color(0xFF334155),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (colorError != null) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(
                              Icons.error_outline_rounded,
                              color: Colors.red,
                              size: 13,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              colorError!,
                              style: const TextStyle(
                                color: Colors.red,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],

                      if (expenseId != null) ...[
                        const SizedBox(height: 16),
                        CheckboxListTile(
                          value: applyToAll,
                          onChanged: (val) =>
                              setDialogState(() => applyToAll = val ?? true),
                          title: const Text(
                            'Apply to all transactions?',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          activeColor: Colors.blue.shade600,
                          controlAffinity: ListTileControlAffinity.leading,
                        ),
                      ],

                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                side: const BorderSide(
                                  color: Color(0xFFCBD5E1),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              onPressed: () => Navigator.pop(context),
                              child: const Text(
                                'Cancel',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF475569),
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                backgroundColor: const Color(0xFF0F172A),
                                elevation: 4,
                                shadowColor: Colors.black.withOpacity(0.3),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              onPressed: () async {
                                final label = labelController.text.trim();

                                setDialogState(() {
                                  nameError = label.isEmpty
                                      ? 'Label name is required'
                                      : null;
                                });

                                if (label.isEmpty) {
                                  return;
                                }

                                setState(() {
                                  groupColors[label] = selectedColor;
                                  if (limitController.text.isNotEmpty) {
                                    groupLimits[label] =
                                        double.tryParse(limitController.text) ??
                                        0;
                                  }

                                  if (expenseId != null && !applyToAll) {
                                    transactionGroups[expenseId] = label;
                                  } else {
                                    for (var name in List.from(namesToGroup)) {
                                      final normalized = name
                                          .trim()
                                          .toUpperCase();
                                      categoryGroups[normalized] = label;
                                      if (_tempSelectedExpenseNames != null) {
                                        _tempSelectedExpenseNames!.remove(
                                          normalized,
                                        );
                                      }
                                    }
                                    if (label.isNotEmpty &&
                                        _tempSelectedExpenseNames != null) {
                                      if (!_tempSelectedExpenseNames!.contains(
                                        label,
                                      )) {
                                        _tempSelectedExpenseNames!.add(label);
                                      }
                                    }
                                  }
                                });
                                await _saveSettings();
                                if (context.mounted) {
                                  Navigator.pop(context);
                                }
                              },
                              child: const Text(
                                'Save Label',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

LinearGradient getGradientBasedOnValue(double value) {
  if (value <= 8000) {
    // Below 5000 - Blue gradient
    return LinearGradient(
      colors: [Colors.blue, Colors.lightBlue, Colors.lightBlueAccent],
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
    );
  } else if (value <= 12000) {
    // Between 5000 and 10000 - Green gradient
    return LinearGradient(
      colors: [Colors.green, Colors.lightGreen, Colors.greenAccent],
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
    );
  } else if (value <= 18000) {
    // Between 10000 and 15000 - Yellow/Orange gradient
    return LinearGradient(
      colors: [Colors.yellow, Colors.orange, Colors.orangeAccent],
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
    );
  } else {
    // Above 15000 - Red gradient
    return LinearGradient(
      colors: [Colors.red, Colors.deepOrange, Colors.redAccent],
      begin: Alignment.centerLeft,
      end: Alignment.centerRight,
    );
  }
}

final List<String> months = [
  'JAN',
  'FEB',
  'MAR',
  'APR',
  'MAY',
  'JUN',
  'JUL',
  'AUG',
  'SEP',
  'OCT',
  'NOV',
  'DEC',
];

class CreditCardStack extends ConsumerStatefulWidget {
  final List<BankSmsGroup> bankGroups;
  final int selectedMonth;
  final Map<String, double> cardLimits;
  final Map<String, bool> cardBudgetEnabled;
  final double maxValue;
  final bool isSyncing;
  final Function(String) onCardChanged;
  final VoidCallback onSync;
  final Function(String) onSettingsTap;
  final Function(String) onFilterTap;
  final String initialCardName;
  final Function(List<String>) onReorder;
  final Map<String, double> groupLimits;
  final Map<String, int> groupColors;
  final Map<String, String> categoryGroups;
  final Map<String, String> transactionGroups;
  final bool isDueDateFiltered;
  final Map<String, DateTime> cardDueDates;
  final Map<String, String> cardThemes;
  final Map<String, bool> isCreditCardOverrides;
  final Map<String, bool> hideCreditDataOverrides;

  const CreditCardStack({
    super.key,
    required this.bankGroups,
    required this.selectedMonth,
    required this.cardLimits,
    required this.cardBudgetEnabled,
    required this.maxValue,
    required this.isSyncing,
    required this.onCardChanged,
    required this.onSync,
    required this.onSettingsTap,
    required this.onFilterTap,
    required this.initialCardName,
    required this.onReorder,
    required this.groupLimits,
    required this.groupColors,
    required this.categoryGroups,
    required this.transactionGroups,
    required this.isDueDateFiltered,
    required this.cardDueDates,
    required this.cardThemes,
    required this.isCreditCardOverrides,
    required this.hideCreditDataOverrides,
  });

  @override
  ConsumerState<CreditCardStack> createState() => _CreditCardStackState();
}

class _CreditCardStackState extends ConsumerState<CreditCardStack> {
  late PageController _pageController;
  int _currentIndex = 0;

  String _getCardTheme(String label) {
    if (widget.cardThemes.containsKey(label) &&
        widget.cardThemes[label] != null) {
      return widget.cardThemes[label]!;
    }
    final cleanInput = label.replaceAll(RegExp(r'[^A-Z0-9]'), '').toUpperCase();
    if (cleanInput.isNotEmpty) {
      for (final entry in widget.cardThemes.entries) {
        final cleanKey = entry.key
            .replaceAll(RegExp(r'[^A-Z0-9]'), '')
            .toUpperCase();
        if (cleanKey.isNotEmpty && cleanKey == cleanInput) {
          return entry.value;
        }
      }
    }
    return 'Ocean';
  }

  List<Color> _getCardThemeGradient(String label) {
    final themeName = _getCardTheme(label);
    return AppConstants.themeGradients[themeName] ??
        AppConstants.themeGradients['Ocean']!;
  }

  String? _getGroup(Expense e) {
    if (widget.transactionGroups.containsKey(e.id)) {
      return widget.transactionGroups[e.id];
    }
    return widget.categoryGroups[e.name.trim().toUpperCase()];
  }

  int _findCardIndex(String targetName) {
    if (widget.bankGroups.isEmpty || targetName.isEmpty) return 0;

    // 1. Exact string match
    int idx = widget.bankGroups.indexWhere((g) => g.label == targetName);
    if (idx != -1) return idx;

    // 2. Cleaned exact match (alphanumeric uppercase)
    final targetClean =
        targetName.replaceAll(RegExp(r'[^A-Z0-9]'), '').toUpperCase();
    if (targetClean.isNotEmpty) {
      idx = widget.bankGroups.indexWhere((g) {
        final gClean =
            g.label.replaceAll(RegExp(r'[^A-Z0-9]'), '').toUpperCase();
        return gClean == targetClean;
      });
      if (idx != -1) return idx;

      // 3. Fallback partial match (only if no exact match exists)
      idx = widget.bankGroups.indexWhere((g) {
        final gClean =
            g.label.replaceAll(RegExp(r'[^A-Z0-9]'), '').toUpperCase();
        return gClean.isNotEmpty &&
            (gClean.contains(targetClean) || targetClean.contains(gClean));
      });
      if (idx != -1) return idx;
    }

    return 0;
  }

  @override
  void initState() {
    super.initState();
    int initialIndex = _findCardIndex(widget.initialCardName);
    _currentIndex = initialIndex;
    _pageController = PageController(
      viewportFraction: 0.85,
      initialPage: initialIndex,
    );

    // Ensure parent is in sync with the actual initial index
    if (widget.bankGroups.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onCardChanged(widget.bankGroups[initialIndex].label);
      });
    }
  }

  @override
  void didUpdateWidget(CreditCardStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    final initialCardChanged =
        oldWidget.initialCardName != widget.initialCardName;
    final oldLabels = oldWidget.bankGroups.map((g) => g.label).toList();
    final newLabels = widget.bankGroups.map((g) => g.label).toList();
    final bankGroupsChanged = !listEquals(oldLabels, newLabels);

    if (initialCardChanged || bankGroupsChanged) {
      int newIndex = _findCardIndex(widget.initialCardName);

      if (newIndex != -1 && newIndex != _currentIndex) {
        _currentIndex = newIndex;
        if (_pageController.hasClients) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_pageController.hasClients) {
              _pageController.jumpToPage(newIndex);
            }
          });
        }
      }
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.bankGroups.isEmpty) {
      return Center(
        child: Container(
          height: 200,
          width: MediaQuery.of(context).size.width * 0.88,
          margin: const EdgeInsets.symmetric(vertical: 10),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF0B132B), Color(0xFF1C2541), Color(0xFF0B132B)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF0B132B).withValues(alpha: 0.4),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.15),
              width: 1.2,
            ),
          ),
          child: Stack(
            clipBehavior: Clip.antiAlias,
            children: [
              // Radial Shimmer Accent Background
              Positioned(
                right: -30,
                top: -30,
                child: Container(
                  width: 160,
                  height: 160,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        Colors.blue.shade400.withValues(alpha: 0.22),
                        Colors.blue.shade600.withValues(alpha: 0.05),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 22,
                    vertical: 18,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Top Row: Brand & Contactless Icon
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(5),
                                decoration: BoxDecoration(
                                  color: Colors.blue.shade500.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  Icons.account_balance_wallet_rounded,
                                  color: Colors.blue.shade400,
                                  size: 16,
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'EXPENSE TRACKER',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.5,
                                ),
                              ),
                            ],
                          ),
                          Icon(
                            Icons.contactless_rounded,
                            color: Colors.white.withValues(alpha: 0.6),
                            size: 24,
                          ),
                        ],
                      ),
                      // Middle Row: Card Off Icon + Message
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.08),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.15),
                                width: 1,
                              ),
                            ),
                            child: const Icon(
                              Icons.credit_card_off_rounded,
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  'No Bank Card Active',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: -0.2,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  'Tap Configure below to select cards',
                                  style: TextStyle(
                                    color: Colors.grey.shade400,
                                    fontSize: 11.5,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      // Bottom Row: Security Badge & Masked Card Dots
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4.5,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF10B981).withValues(
                                alpha: 0.15,
                              ),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: const Color(0xFF10B981).withValues(
                                  alpha: 0.3,
                                ),
                                width: 0.8,
                              ),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.shield_outlined,
                                  color: Color(0xFF34D399),
                                  size: 12,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  'Private & Secure',
                                  style: TextStyle(
                                    color: Color(0xFF34D399),
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Text(
                            '••••  ••••  ••••  0000',
                            style: TextStyle(
                              color: Colors.white38,
                              fontSize: 10.5,
                              letterSpacing: 1.2,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return SizedBox(
      height: 220,
      child: PageView.builder(
        controller: _pageController,
        itemCount: widget.bankGroups.length,
        onPageChanged: (index) {
          setState(() => _currentIndex = index);
          widget.onCardChanged(widget.bankGroups[index].label);
        },
        itemBuilder: (context, index) {
          final group = widget.bankGroups[index];
          final state = ref.watch(expenseNotifierProvider);
          double bankDebitedTotal = 0.0;
              double bankCreditedTotal = 0.0;
              final cardDueDateVal = widget.cardDueDates[group.label];

              if (state is ExpenseLoaded) {
                final groupUpper = group.label.toUpperCase();
                final targetMonthVal = widget.selectedMonth + 1;
                final currentYearVal = DateTime.now().year;

                final matchedExpenses = state.data.expenses.where((e) {
                  final eBankUpper = e.bank.toUpperCase();
                  bool matchesBank =
                      eBankUpper.contains(groupUpper) ||
                      groupUpper.contains(eBankUpper);
                  if (!matchesBank) return false;
                  if (_getGroup(e) == 'Unread') return false;

                  if (widget.isDueDateFiltered && cardDueDateVal != null) {
                    final endDate = DateTime(
                      currentYearVal,
                      targetMonthVal,
                      cardDueDateVal.day,
                    );
                    final startDate = DateTime(
                      endDate.year,
                      endDate.month - 1,
                      endDate.day,
                    );
                    return (e.date.isAfter(startDate) ||
                            e.date.isAtSameMomentAs(startDate)) &&
                        (e.date.isBefore(endDate) ||
                            e.date.isAtSameMomentAs(endDate));
                  } else {
                    return e.date.month == targetMonthVal &&
                        e.date.year == currentYearVal;
                  }
                });

                for (final e in matchedExpenses) {
                  if (e.type == 'spent' || e.type == 'debited') {
                    bankDebitedTotal += e.amount;
                  } else if (e.type == 'received' || e.type == 'credited') {
                    bankCreditedTotal += e.amount;
                  }
                }
              }

              return GestureDetector(
                onLongPress: () => _showReorderSheet(context),
                child: CardWidgetUI(
                  cardName: group.label,
                  cardType:
                      ((widget.hideCreditDataOverrides[group.label] ?? false) ||
                          (widget.isCreditCardOverrides.containsKey(group.label)
                              ? widget.isCreditCardOverrides[group.label]!
                              : (group.type == 'credit_card')))
                      ? 'credit_card'
                      : 'debit_card',
                  currentValue: bankDebitedTotal,
                  creditedValue: bankCreditedTotal,
                  isCreditOnly: false,
                  hideCreditData:
                      (widget.hideCreditDataOverrides[group.label] ?? false) ||
                      (widget.isCreditCardOverrides[group.label] ?? false),
                  maxValue:
                      widget.cardLimits[group.label] ??
                      (state is ExpenseLoaded
                          ? state.data.limit
                          : widget.maxValue),
                  isBudgetEnabled:
                      widget.cardBudgetEnabled[group.label] ?? true,
                  isSyncing: widget.isSyncing,
                  onSync: widget.onSync,
                  onSettingsTap: () => widget.onSettingsTap(group.label),
                  onFilterTap: () => widget.onFilterTap(group.label),
                  currentMonth: months[widget.selectedMonth],
                  groupLimits: widget.groupLimits,
                  groupColors: widget.groupColors,
                  cardDueDate: cardDueDateVal,
                  cardTheme: _getCardTheme(group.label),
                ),
              );
            },
          ),
        );
  }

  void _showReorderSheet(BuildContext context) {
    final currentOrder = List<String>.from(
      widget.bankGroups.map((g) => g.label),
    );
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
                top: 8,
                left: 18,
                right: 18,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Drag handle bar
                  Container(
                    width: 44,
                    height: 5,
                    margin: const EdgeInsets.only(top: 6, bottom: 16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFCBD5E1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),

                  // Header row with Icon & Title
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: const Color(0xFFBFDBFE),
                            width: 1,
                          ),
                        ),
                        child: const Icon(
                          Icons.swap_vert_rounded,
                          color: Color(0xFF2563EB),
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            Text(
                              'Rearrange Card Priority',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 17,
                                color: Color(0xFF0F172A),
                                letterSpacing: -0.2,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Hold & drag items to change display order',
                              style: TextStyle(
                                color: Color(0xFF64748B),
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(
                          Icons.close_rounded,
                          color: Color(0xFF64748B),
                          size: 22,
                        ),
                        tooltip: 'Close',
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Reorderable Card List
                  Flexible(
                    child: ReorderableListView.builder(
                      shrinkWrap: true,
                      itemCount: currentOrder.length,
                      proxyDecorator: (child, index, animation) {
                        return AnimatedBuilder(
                          animation: animation,
                          builder: (context, child) {
                            return Material(
                              color: Colors.transparent,
                              elevation: 6,
                              shadowColor: Colors.black.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(16),
                              child: child,
                            );
                          },
                          child: child,
                        );
                      },
                      onReorder: (oldIndex, newIndex) {
                        HapticFeedback.selectionClick();
                        setModalState(() {
                          if (newIndex > oldIndex) newIndex -= 1;
                          final item = currentOrder.removeAt(oldIndex);
                          currentOrder.insert(newIndex, item);
                        });
                        widget.onReorder(currentOrder);
                      },
                      itemBuilder: (context, index) {
                        final name = currentOrder[index];
                        final priorityNum = index + 1;
                        final themeGradient = _getCardThemeGradient(name);
                        final themeColor = themeGradient.first;

                        return Container(
                          key: ValueKey(name),
                          margin: const EdgeInsets.symmetric(vertical: 5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: const Color(0xFFE2E8F0),
                              width: 1.2,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.drag_indicator_rounded,
                                  color: Colors.grey,
                                  size: 22,
                                ),
                                const SizedBox(width: 10),
                                Container(
                                  width: 28,
                                  height: 28,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: Colors.grey.shade200,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Text(
                                    '$priorityNum',
                                    style:  TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: themeColor,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Text(
                                    name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14.5,
                                      color: Color(0xFF0F172A),
                                      letterSpacing: 0.2,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: themeColor.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: themeColor.withValues(alpha: 0.2),
                                      width: 1,
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.credit_card_rounded,
                                    color: themeColor,
                                    size: 18,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}


class CardWidgetUI extends StatelessWidget {
  final String cardName;
  final String cardType;
  final double currentValue;
  final double creditedValue;
  final bool isCreditOnly;
  final bool hideCreditData;
  final double maxValue;
  final bool isBudgetEnabled;
  final bool isSyncing;
  final VoidCallback onSync;
  final VoidCallback onSettingsTap;
  final VoidCallback onFilterTap;
  final String currentMonth;
  final Map<String, double> groupLimits;
  final Map<String, int> groupColors;
  final DateTime? cardDueDate;
  final String cardTheme;

  const CardWidgetUI({
    super.key,
    required this.cardName,
    required this.cardType,
    required this.currentValue,
    this.creditedValue = 0.0,
    this.isCreditOnly = false,
    this.hideCreditData = false,
    required this.maxValue,
    this.isBudgetEnabled = true,
    required this.isSyncing,
    required this.onSync,
    required this.onSettingsTap,
    required this.onFilterTap,
    required this.currentMonth,
    required this.groupLimits,
    required this.groupColors,
    this.cardDueDate,
    required this.cardTheme,
  });

  List<PieChartSectionData> _getPieSections() {
    List<PieChartSectionData> sections = [];
    double totalAllocated = 0;

    groupLimits.forEach((name, limit) {
      if (limit > 0) {
        totalAllocated += limit;
        sections.add(
          PieChartSectionData(
            color: Color(groupColors[name] ?? Colors.blue.value),
            value: limit,
            radius: 12,
            showTitle: false,
          ),
        );
      }
    });

    final remaining = maxValue - totalAllocated;
    if (remaining > 0) {
      sections.add(
        PieChartSectionData(
          color: Colors.white.withOpacity(0.1),
          value: remaining,
          radius: 10,
          showTitle: false,
        ),
      );
    }
    if (sections.isEmpty) {
      sections.add(
        PieChartSectionData(
          color: Colors.white.withOpacity(0.05),
          value: 1,
          radius: 10,
          showTitle: false,
        ),
      );
    }
    return sections;
  }

  @override
  Widget build(BuildContext context) {
    final progress = (currentValue / maxValue).clamp(0.0, 1.0);
    final remaining = maxValue - currentValue;

    final themeGradients = AppConstants.themeGradients;
    final gradientColors =
        themeGradients[cardTheme] ?? themeGradients['Ocean']!;

    return FlipCard(
      direction: FlipDirection.VERTICAL,
      front: _buildFrontCard(gradientColors, progress, remaining),
      back: _buildBackCard(gradientColors, progress, remaining),
    );
  }

  Widget _buildFrontCard(
    List<Color> gradientColors,
    double progress,
    double remaining,
  ) {
    return Container(
      margin: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: gradientColors.last.withValues(alpha: 0.35),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(22),
              child: CustomPaint(painter: CardPatternPainter(cardTheme)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Header Row matching mockup (Card Label & Issuer / Settings)
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Text(
                          '${cardName.toUpperCase()}',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2.5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.25),
                              width: 0.8,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.touch_app_rounded,
                                color: Colors.white.withValues(alpha: 0.9),
                                size: 10,
                              ),
                              const SizedBox(width: 3),
                              Text(
                                'HOLD TO REORDER',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.9),
                                  fontSize: 7.5,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: 0.4,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          HapticFeedback.lightImpact();
                          onSettingsTap();
                        },
                        borderRadius: BorderRadius.circular(12),
                        splashColor: Colors.white.withValues(alpha: 0.2),
                        highlightColor: Colors.white.withValues(alpha: 0.1),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: const [
                              Text(
                                'Plan B',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              SizedBox(width: 5),
                              Icon(
                                Icons.settings_rounded,
                                color: Colors.white,
                                size: 16,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Text(
                      'XXXX XXXX XXXX XXXX',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2.5,
                        shadows: [
                          Shadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    if (cardDueDate != null) ...[
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444),
                          borderRadius: BorderRadius.circular(6),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFFEF4444,
                              ).withValues(alpha: 0.4),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.error_outline_rounded,
                              color: Colors.white,
                              size: 10,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'BILL DUE: ${cardDueDate!.day}th',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 8,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                const Spacer(),
                // Bottom Row matching mockup: Holder Name, Expiry & Overlapping Mastercard Circles
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Row(
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Debited',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              currentValue.toStringAsFixed(0),
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: !hideCreditData ? 23 : 25,
                                fontWeight: FontWeight.bold,
                                letterSpacing: !hideCreditData ? 1.5 : 2.5,
                                shadows: [
                                  Shadow(
                                    color: Colors.black.withValues(alpha: 0.3),
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        if (!hideCreditData) ...[
                          const SizedBox(width: 10),
                          Container(
                            height: 30,
                            color: Colors.white.withValues(alpha: 0.4),
                            width: 2,
                          ),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Credited',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                creditedValue.toStringAsFixed(0),
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 23,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 1.5,
                                  shadows: [
                                    Shadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.3,
                                      ),
                                      blurRadius: 4,
                                      offset: const Offset(0, 2),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                    // Dual Overlapping White Mastercard Circles (Mockup Badge)
                    SizedBox(
                      width: 36,
                      height: 22,
                      child: Stack(
                        alignment: Alignment.centerLeft,
                        children: [
                          Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withValues(alpha: 0.85),
                            ),
                          ),
                          Positioned(
                            left: 11,
                            child: Container(
                              width: 20,
                              height: 20,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white.withValues(alpha: 0.55),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // Glassmorphism spent & budget section
                if (isBudgetEnabled) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.15),
                        width: 0.8,
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${(progress * 100).toStringAsFixed(0)}%',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            if (isBudgetEnabled)
                              Text(
                                'Rem: ₹${remaining.toStringAsFixed(0)}',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.85),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                          ],
                        ),
                        if (isBudgetEnabled) ...[
                          const SizedBox(height: 5),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: LinearProgressIndicator(
                              value: progress,
                              backgroundColor: Colors.white.withValues(
                                alpha: 0.5,
                              ),
                              valueColor: AlwaysStoppedAnimation<Color>(
                                progress > 0.8
                                    ? const Color(0xFFEF4444)
                                    : (progress > 0.5
                                          ? const Color(0xFFF97316)
                                          : const Color(0xFF10B981)),
                              ),
                              minHeight: 7,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackCard(
    List<Color> gradientColors,
    double progress,
    double remaining,
  ) {
    return Container(
      margin: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: gradientColors.reversed.toList(),
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1E3A8A).withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: CustomPaint(painter: CardPatternPainter(cardTheme)),
            ),
          ),
          // Magnetic Stripe
          Positioned(
            top: 25,
            left: 0,
            right: 0,
            child: Container(height: 45, color: Colors.black87),
          ),
          // Signature Panel and CVV
          Positioned(
            top: 85,
            left: 20,
            right: 20,
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 35,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.8),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    child: Text(
                      cardName,
                      style: const TextStyle(
                        color: Colors.black54,
                        fontStyle: FontStyle.italic,
                        fontSize: 16,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  width: 45,
                  height: 35,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  alignment: Alignment.center,
                  child: const Text(
                    '•••',
                    style: TextStyle(
                      color: Colors.black87,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Pie Chart and Details
          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                SizedBox(
                  width: 70,
                  height: 70,
                  child: PieChart(
                    PieChartData(
                      sections: _getPieSections(),
                      centerSpaceRadius: 18,
                      sectionsSpace: 2,
                    ),
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        'LIMIT ALLOCATION',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.6),
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
                // small bank text
                Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      cardType == 'credit_card' ? 'CREDIT' : 'DEBIT',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.4),
                        fontSize: 10,
                        letterSpacing: 2,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'AUTH ONLY',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.4),
                        fontSize: 8,
                        letterSpacing: 1,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}




class CardPatternPainter extends CustomPainter {
  final String themeName;

  CardPatternPainter(this.themeName);

  @override
  void paint(Canvas canvas, Size size) {
    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = Colors.white.withValues(alpha: 0.20);

    final fillPaint = Paint()..style = PaintingStyle.fill;

    switch (themeName) {
      case 'Sunset': // Image 1: Tri-tone Deep Purple, Peach Pink left blob & Amber Yellow right wave
        final peachBlob = Path()
          ..moveTo(0, 0)
          ..lineTo(size.width * 0.15, 0)
          ..cubicTo(
            size.width * 0.28,
            size.height * 0.35,
            size.width * 0.22,
            size.height * 0.75,
            0,
            size.height * 0.68,
          )
          ..close();
        canvas.drawPath(peachBlob, fillPaint..color = const Color(0xFFF09A9D));

        final yellowWave = Path()
          ..moveTo(size.width * 0.55, 0)
          ..cubicTo(
            size.width * 0.50,
            size.height * 0.45,
            size.width * 0.75,
            size.height * 0.75,
            size.width * 0.58,
            size.height,
          )
          ..lineTo(size.width, size.height)
          ..lineTo(size.width, 0)
          ..close();
        canvas.drawPath(yellowWave, fillPaint..color = const Color(0xFFF5A623));
        break;

      case 'Coral': // Image 2: Warm Orange background with Coral Red organic fluid shapes
        final coralWave1 = Path()
          ..moveTo(size.width * 0.5, 0)
          ..cubicTo(
            size.width * 0.42,
            size.height * 0.45,
            size.width * 0.75,
            size.height * 0.8,
            size.width * 0.4,
            size.height,
          )
          ..lineTo(size.width, size.height)
          ..lineTo(size.width, 0)
          ..close();
        canvas.drawPath(
          coralWave1,
          fillPaint..color = const Color(0xFFFF4757).withValues(alpha: 0.85),
        );

        final coralWave2 = Path()
          ..moveTo(0, size.height * 0.4)
          ..cubicTo(
            size.width * 0.4,
            size.height * 0.35,
            size.width * 0.45,
            size.height,
            size.width * 0.2,
            size.height,
          )
          ..lineTo(0, size.height)
          ..close();
        canvas.drawPath(
          coralWave2,
          fillPaint..color = const Color(0xFFFF3B5C).withValues(alpha: 0.70),
        );
        break;

      case 'Tangerine': // Image 3: Crimson Red background with Amber Yellow-Orange fluid waves
        final yellowBlobLeft = Path()
          ..moveTo(0, size.height * 0.35)
          ..cubicTo(
            size.width * 0.3,
            size.height * 0.3,
            size.width * 0.35,
            size.height,
            0,
            size.height,
          )
          ..close();
        canvas.drawPath(
          yellowBlobLeft,
          fillPaint..color = const Color(0xFFFF9500),
        );

        final yellowWaveRight = Path()
          ..moveTo(size.width * 0.42, 0)
          ..cubicTo(
            size.width * 0.35,
            size.height * 0.5,
            size.width * 0.75,
            size.height * 0.75,
            size.width * 0.58,
            size.height,
          )
          ..lineTo(size.width, size.height)
          ..lineTo(size.width, 0)
          ..close();
        canvas.drawPath(
          yellowWaveRight,
          fillPaint..color = const Color(0xFFFF9500),
        );
        break;

      case 'Ruby': // Image 4: Hot Pink Ruby with dark translucent circle & soft pink drop
        final dropBlob = Path()
          ..moveTo(0, size.height * 0.15)
          ..cubicTo(
            size.width * 0.4,
            size.height * 0.1,
            size.width * 0.38,
            size.height * 0.75,
            0,
            size.height * 0.65,
          )
          ..close();
        canvas.drawPath(
          dropBlob,
          fillPaint..color = const Color(0xFFFF80A0).withValues(alpha: 0.45),
        );

        final darkCircleCenter = Offset(size.width * 0.78, size.height * 0.65);
        canvas.drawCircle(
          darkCircleCenter,
          size.height * 0.55,
          fillPaint..color = const Color(0xFF880033).withValues(alpha: 0.50),
        );
        break;

      case 'Emerald': // Image 5: Teal background with dark oceanic teal & mint fluid wave blobs
        final darkTealWave = Path()
          ..moveTo(0, size.height * 0.2)
          ..cubicTo(
            size.width * 0.45,
            size.height * 0.1,
            size.width * 0.3,
            size.height * 0.85,
            0,
            size.height * 0.85,
          )
          ..close();
        canvas.drawPath(
          darkTealWave,
          fillPaint..color = const Color(0xFF004D40).withValues(alpha: 0.55),
        );

        final bottomTealBlob = Path()
          ..moveTo(size.width * 0.25, size.height)
          ..cubicTo(
            size.width * 0.4,
            size.height * 0.55,
            size.width * 0.7,
            size.height * 0.65,
            size.width * 0.6,
            size.height,
          )
          ..close();
        canvas.drawPath(
          bottomTealBlob,
          fillPaint..color = const Color(0xFF004D40).withValues(alpha: 0.45),
        );

        final rightMintWave = Path()
          ..moveTo(size.width * 0.65, 0)
          ..cubicTo(
            size.width * 0.55,
            size.height * 0.4,
            size.width * 0.85,
            size.height * 0.7,
            size.width,
            size.height * 0.4,
          )
          ..lineTo(size.width, 0)
          ..close();
        canvas.drawPath(
          rightMintWave,
          fillPaint..color = const Color(0xFF2DD4BF).withValues(alpha: 0.35),
        );
        break;

      case 'Amethyst': // Card 1: Geometric 3D cube ribbon grid
        final path = Path();
        for (double i = -size.height; i < size.width * 1.5; i += 26) {
          path.moveTo(i, 0);
          path.lineTo(i + size.height, size.height);
          path.moveTo(i, size.height);
          path.lineTo(i + size.height, 0);
        }
        canvas.drawPath(
          path,
          strokePaint
            ..strokeWidth = 1.0
            ..color = Colors.white.withValues(alpha: 0.15),
        );
        final ribbon = Path()
          ..moveTo(size.width * 0.35, size.height)
          ..lineTo(size.width * 0.6, 0)
          ..lineTo(size.width * 0.85, 0)
          ..lineTo(size.width * 0.6, size.height)
          ..close();
        canvas.drawPath(
          ribbon,
          fillPaint..color = Colors.white.withValues(alpha: 0.18),
        );
        break;

      case 'Lavender': // Card 3: Fluid organic corner wave blobs
        final lavender1 = Path()
          ..moveTo(size.width * 0.4, 0)
          ..cubicTo(
            size.width * 0.7,
            size.height * 0.3,
            size.width * 0.5,
            size.height * 0.8,
            size.width,
            size.height * 0.6,
          )
          ..lineTo(size.width, 0)
          ..close();
        canvas.drawPath(
          lavender1,
          fillPaint..color = const Color(0xFFDDD6FE).withValues(alpha: 0.35),
        );
        final lavender2 = Path()
          ..moveTo(0, size.height * 0.5)
          ..cubicTo(
            size.width * 0.3,
            size.height * 0.4,
            size.width * 0.4,
            size.height,
            size.width * 0.7,
            size.height,
          )
          ..lineTo(0, size.height)
          ..close();
        canvas.drawPath(
          lavender2,
          fillPaint..color = const Color(0xFFA78BFA).withValues(alpha: 0.25),
        );
        break;

      case 'Mocha': // Card 4: Dark Espresso Brown organic fluid waves
        final mochaWave1 = Path()
          ..moveTo(0, size.height * 0.4)
          ..cubicTo(
            size.width * 0.4,
            size.height * 0.8,
            size.width * 0.7,
            size.height * 0.2,
            size.width,
            size.height * 0.6,
          )
          ..lineTo(size.width, size.height)
          ..lineTo(0, size.height)
          ..close();
        canvas.drawPath(
          mochaWave1,
          fillPaint..color = const Color(0xFF92400E).withValues(alpha: 0.35),
        );
        break;

      case 'Ocean': // Card 5: Deep Blue angled geometric block geometry
        final block1 = Path()
          ..moveTo(size.width * 0.45, 0)
          ..lineTo(size.width * 0.85, 0)
          ..lineTo(size.width * 0.6, size.height)
          ..lineTo(size.width * 0.2, size.height)
          ..close();
        canvas.drawPath(
          block1,
          fillPaint..color = Colors.white.withValues(alpha: 0.16),
        );
        break;

      case 'Cyan': // Card 7: Cyan concentric radar rings in top right
        final topRight = Offset(size.width * 0.85, size.height * 0.15);
        for (double r = 25; r < 240; r += 20) {
          canvas.drawCircle(
            topRight,
            r,
            strokePaint
              ..strokeWidth = 1.2
              ..color = Colors.white.withValues(alpha: 0.22),
          );
        }
        break;

      case 'DeepTeal': // Card 10: Deep Teal floating triangles
        final points = [
          Offset(size.width * 0.4, size.height * 0.2),
          Offset(size.width * 0.5, size.height * 0.4),
          Offset(size.width * 0.35, size.height * 0.45),
          Offset(size.width * 0.7, size.height * 0.3),
          Offset(size.width * 0.8, size.height * 0.6),
          Offset(size.width * 0.65, size.height * 0.75),
          Offset(size.width * 0.85, size.height * 0.85),
        ];
        for (int i = 0; i < points.length; i++) {
          final t = Path()
            ..moveTo(points[i].dx, points[i].dy)
            ..lineTo(points[i].dx + 24, points[i].dy + 32)
            ..lineTo(points[i].dx - 18, points[i].dy + 28)
            ..close();
          canvas.drawPath(
            t,
            fillPaint..color = const Color(0xFF5EEAD4).withValues(alpha: 0.35),
          );
        }
        break;

      case 'Gold': // Card 11: Golden Olive halftone dot matrix & ring arcs
        for (double x = size.width * 0.3; x < size.width; x += 15) {
          for (double y = 10; y < size.height; y += 15) {
            final radius =
                1.2 + ((x - size.width * 0.3) / (size.width * 0.7)) * 3.5;
            canvas.drawCircle(
              Offset(x, y),
              radius,
              fillPaint
                ..color = const Color(0xFFFEF08A).withValues(alpha: 0.35),
            );
          }
        }
        break;

      case 'Turquoise': // Card 12: Wireframe line sweep
        for (int i = 0; i < 7; i++) {
          final path = Path();
          final startY = size.height * 0.1 + (i * 14);
          path.moveTo(0, startY);
          path.cubicTo(
            size.width * 0.4,
            startY + 40,
            size.width * 0.6,
            startY - 30,
            size.width,
            startY + 20,
          );
          canvas.drawPath(
            path,
            strokePaint
              ..strokeWidth = 1.2
              ..color = const Color(
                0xFF99F6E4,
              ).withValues(alpha: 0.35 - (i * 0.04)),
          );
        }
        break;

      case 'Taupe': // Card 13: Slanted pinstripes
        for (double i = -size.height; i < size.width + size.height; i += 8) {
          canvas.drawLine(
            Offset(i, 0),
            Offset(i + size.height, size.height),
            strokePaint
              ..strokeWidth = 0.8
              ..color = Colors.white.withValues(alpha: 0.16),
          );
        }
        break;

      case 'RoyalIndigo': // Card 14: Circular radial waves
        final botRight = Offset(size.width * 0.75, size.height * 0.75);
        for (double r = 20; r < 240; r += 18) {
          canvas.drawCircle(
            botRight,
            r,
            strokePaint
              ..strokeWidth = 1.1
              ..color = const Color(0xFFC084FC).withValues(alpha: 0.3),
          );
        }
        break;

      case 'ElectricBlue': // Card 15: Sweeping sine waves
        for (int i = 0; i < 6; i++) {
          final path = Path();
          final startY = size.height * 0.15 + (i * 16);
          path.moveTo(0, startY);
          path.cubicTo(
            size.width * 0.3,
            startY - 35,
            size.width * 0.7,
            startY + 35,
            size.width,
            startY - 15,
          );
          canvas.drawPath(
            path,
            strokePaint
              ..strokeWidth = 1.4
              ..color = const Color(
                0xFF93C5FD,
              ).withValues(alpha: 0.35 - (i * 0.04)),
          );
        }
        break;

      case 'Espresso': // Card 16: Subtle pinstripes
        for (double i = -size.height; i < size.width + size.height; i += 12) {
          canvas.drawLine(
            Offset(i, 0),
            Offset(i + size.height, size.height),
            strokePaint
              ..strokeWidth = 0.9
              ..color = Colors.white.withValues(alpha: 0.12),
          );
        }
        break;

      case 'NeonViolet': // Card 17: Geometric diamond lattice grid
        final dPath = Path();
        for (double x = -size.height; x < size.width + size.height; x += 22) {
          dPath.moveTo(x, 0);
          dPath.lineTo(x + size.height, size.height);
          dPath.moveTo(x, size.height);
          dPath.lineTo(x + size.height, 0);
        }
        canvas.drawPath(
          dPath,
          strokePaint
            ..strokeWidth = 1.0
            ..color = const Color(0xFFDDD6FE).withValues(alpha: 0.35),
        );
        break;

      case 'DuoPurple': // Card 18: Corner fluid blob
        final duoBlob = Path()
          ..moveTo(size.width * 0.35, 0)
          ..cubicTo(
            size.width * 0.7,
            size.height * 0.2,
            size.width * 0.4,
            size.height * 0.9,
            size.width,
            size.height * 0.65,
          )
          ..lineTo(size.width, 0)
          ..close();
        canvas.drawPath(
          duoBlob,
          fillPaint..color = const Color(0xFFC084FC).withValues(alpha: 0.35),
        );
        break;

      case 'RoseCrimson': // Card 19: Horizontal line hatch
        for (double y = 6; y < size.height; y += 8) {
          canvas.drawLine(
            Offset(size.width * 0.25, y),
            Offset(size.width, y),
            strokePaint
              ..strokeWidth = 0.8
              ..color = const Color(0xFFFECDD3).withValues(alpha: 0.28),
          );
        }
        break;

      case 'NeonPink': // Card 20: Diagonal lattice grid
        final lattice = Path();
        for (double x = -size.height; x < size.width + size.height; x += 18) {
          lattice.moveTo(x, 0);
          lattice.lineTo(x + size.height, size.height);
          lattice.moveTo(x, size.height);
          lattice.lineTo(x + size.height, 0);
        }
        canvas.drawPath(
          lattice,
          strokePaint
            ..strokeWidth = 1.0
            ..color = const Color(0xFFFFD6E0).withValues(alpha: 0.35),
        );
        break;

      case 'Magenta': // Card 21: Wide slanted diagonal stripes
        for (double x = -40; x < size.width + 100; x += 32) {
          final p = Path()
            ..moveTo(x, 0)
            ..lineTo(x + 40, 0)
            ..lineTo(x + 40 - size.height * 0.85, size.height)
            ..lineTo(x - size.height * 0.85, size.height)
            ..close();
          canvas.drawPath(
            p,
            fillPaint..color = const Color(0xFFFBCFE8).withValues(alpha: 0.25),
          );
        }
        break;

      case 'Indigo': // Card 23: Line hatching
        for (double i = -size.height; i < size.width + size.height; i += 9) {
          canvas.drawLine(
            Offset(i, 0),
            Offset(i + size.height, size.height),
            strokePaint
              ..strokeWidth = 0.85
              ..color = const Color(0xFFC7D2FE).withValues(alpha: 0.35),
          );
        }
        break;

      case 'SkyBlue': // Card 24: Sweeping line arcs
        for (int i = 0; i < 6; i++) {
          final path = Path();
          final startY = size.height * 0.1 + (i * 15);
          path.moveTo(size.width * 0.2, startY);
          path.cubicTo(
            size.width * 0.5,
            startY + 35,
            size.width * 0.7,
            startY - 25,
            size.width,
            startY + 10,
          );
          canvas.drawPath(
            path,
            strokePaint
              ..strokeWidth = 1.2
              ..color = const Color(
                0xFFBAE6FD,
              ).withValues(alpha: 0.4 - (i * 0.05)),
          );
        }
        break;

      case 'Forest': // Card 26: Camouflage fluid shapes
        final fBlob = Path()
          ..moveTo(0, size.height * 0.4)
          ..cubicTo(
            size.width * 0.3,
            size.height * 0.1,
            size.width * 0.65,
            size.height * 0.9,
            size.width,
            size.height * 0.3,
          )
          ..lineTo(size.width, 0)
          ..lineTo(0, 0)
          ..close();
        canvas.drawPath(
          fBlob,
          fillPaint..color = const Color(0xFFD9F99D).withValues(alpha: 0.3),
        );
        break;

      case 'Midnight': // Card 27: Halftone dot matrix
        for (double x = 10; x < size.width * 0.7; x += 15) {
          for (double y = size.height * 0.2; y < size.height; y += 15) {
            final radius = 1.0 + ((1.0 - (x / (size.width * 0.7))) * 3.5);
            canvas.drawCircle(
              Offset(x, y),
              radius,
              fillPaint
                ..color = const Color(0xFF93C5FD).withValues(alpha: 0.35),
            );
          }
        }
        break;

      case 'Teal': // Card 28: Overlapping wave blobs
        final tBlob = Path()
          ..moveTo(size.width * 0.2, size.height)
          ..cubicTo(
            size.width * 0.4,
            size.height * 0.3,
            size.width * 0.75,
            size.height * 0.7,
            size.width,
            size.height * 0.2,
          )
          ..lineTo(size.width, size.height)
          ..close();
        canvas.drawPath(
          tBlob,
          fillPaint..color = const Color(0xFF99F6E4).withValues(alpha: 0.35),
        );
        break;

      case 'Terracotta': // Card 30: Band stripes
        for (double x = -60; x < size.width + 60; x += 38) {
          final path = Path()
            ..moveTo(x, 0)
            ..lineTo(x + 22, 0)
            ..lineTo(x + 22 - size.height, size.height)
            ..lineTo(x - size.height, size.height)
            ..close();
          canvas.drawPath(
            path,
            fillPaint..color = const Color(0xFFFFEDD5).withValues(alpha: 0.3),
          );
        }
        break;

      case 'Graphite': // Card 31: Radar target circles
        final targetCenter = Offset(size.width * 0.75, size.height * 0.6);
        for (double r = 16; r < 180; r += 20) {
          canvas.drawCircle(
            targetCenter,
            r,
            strokePaint
              ..strokeWidth = 1.0
              ..color = const Color(0xFFCBD5E1).withValues(alpha: 0.35),
          );
        }
        break;

      case 'Olive': // Card 32: Organic wave contour
      case 'Obsidian':
      default:
        final oWave = Path()
          ..moveTo(0, size.height * 0.4)
          ..cubicTo(
            size.width * 0.4,
            size.height * 0.8,
            size.width * 0.7,
            size.height * 0.2,
            size.width,
            size.height * 0.6,
          )
          ..lineTo(size.width, size.height)
          ..lineTo(0, size.height)
          ..close();
        canvas.drawPath(
          oWave,
          fillPaint..color = const Color(0xFFECFCCB).withValues(alpha: 0.25),
        );
        break;
    }
  }

  @override
  bool shouldRepaint(covariant CardPatternPainter oldDelegate) =>
      oldDelegate.themeName != themeName;
}
