import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../../features/expenses/presentation/bloc/expense_bloc.dart';
import '../../../features/expenses/presentation/bloc/expense_state.dart';
import '../../../features/expenses/presentation/bloc/expense_event.dart';
import '../../../core/services/sms_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'custom_blue_date_picker_dialog.dart';

class SettingsDrawer extends StatefulWidget {
  final List<String> visibleCards;
  final List<String> selectedExpenseNames;
  final String? editingCardName;
  final Map<String, double> cardLimits;
  final Map<String, double> cardBoundaries;
  final Map<String, DateTime> cardDueDates;
  final Map<String, bool> isCreditCardOverrides;
  final Map<String, String> categoryGroups;
  final Map<String, int> groupColors;
  final Map<String, double> groupLimits;
  final List<BankSmsGroup> bankGroups;
  final int initialTabIndex;
  final String? initialCardName;
  final Function(
    List<String> visibleCards,
    List<String> selectedExpenseNames,
    String? editingCardName,
    Map<String, double> cardLimits,
    Map<String, double> cardBoundaries,
    Map<String, DateTime> cardDueDates,
    Map<String, bool> isCreditCardOverrides,
    Map<String, String> categoryGroups,
    Map<String, int> groupColors,
    Map<String, double> groupLimits,
  )
  onApply;

  const SettingsDrawer({
    super.key,
    required this.visibleCards,
    required this.selectedExpenseNames,
    this.editingCardName,
    required this.cardLimits,
    required this.cardBoundaries,
    required this.cardDueDates,
    required this.isCreditCardOverrides,
    required this.categoryGroups,
    required this.groupColors,
    required this.groupLimits,
    required this.bankGroups,
    this.initialTabIndex = 0,
    this.initialCardName,
    required this.onApply,
  });

  @override
  State<SettingsDrawer> createState() => _SettingsDrawerState();
}

class _SettingsDrawerState extends State<SettingsDrawer> {
  late List<String> _tempVisibleCards;
  late List<String> _tempSelectedExpenseNames;
  String? _tempEditingCardName;
  late Map<String, double> _tempCardLimits;
  late Map<String, double> _tempCardBoundaries;
  late Map<String, DateTime> _tempCardDueDates;
  late Map<String, bool> _tempIsCreditCardOverrides;
  late Map<String, String> _tempCategoryGroups;
  late Map<String, int> _tempGroupColors;
  late Map<String, double> _tempGroupLimits;
  late int _drawerTabIndex;

  @override
  void initState() {
    super.initState();
    _tempVisibleCards = List.from(widget.visibleCards);
    _tempSelectedExpenseNames = List.from(widget.selectedExpenseNames);
    _tempEditingCardName = widget.editingCardName ?? widget.initialCardName;
    _tempCardLimits = Map.from(widget.cardLimits);
    _tempCardBoundaries = Map.from(widget.cardBoundaries);
    _tempCardDueDates = Map.from(widget.cardDueDates);
    _tempIsCreditCardOverrides = Map.from(widget.isCreditCardOverrides);
    _tempCategoryGroups = Map.from(widget.categoryGroups);
    _tempGroupColors = Map.from(widget.groupColors);
    _tempGroupLimits = Map.from(widget.groupLimits);
    _drawerTabIndex = widget.initialTabIndex;
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(30),
          bottomLeft: Radius.circular(30),
        ),
      ),
      width: MediaQuery.of(context).size.width / 1.15,
      child: StatefulBuilder(
        builder: (context, setDrawerState) {
          return SafeArea(
            child: DefaultTabController(
              length: _tempVisibleCards.isEmpty ? 1 : 3,
              initialIndex: _tempVisibleCards.isEmpty ? 0 : _drawerTabIndex,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                    child: TabBar(
                      dividerColor: Colors.white,
                      labelColor: Colors.black,
                      unselectedLabelColor: Colors.grey,
                      indicatorColor: Colors.black,
                      indicatorWeight: 3,
                      labelStyle: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                      ),
                      onTap: (index) => setState(() => _drawerTabIndex = index),
                      tabs: _tempVisibleCards.isEmpty
                          ? [const Tab(text: 'Configure')]
                          : [
                              const Tab(text: 'Settings'),
                              const Tab(text: 'Filter'),
                              const Tab(text: 'Configure'),
                            ],
                    ),
                  ),
                  Expanded(
                    child: BlocBuilder<ExpenseBloc, ExpenseState>(
                      builder: (context, state) {
                        return TabBarView(
                          children: _tempVisibleCards.isEmpty
                              ? [_buildTempConfigureTab(setDrawerState)]
                              : [
                                  _buildTempSettingsTab(setDrawerState, state),
                                  _buildTempFilterTab(setDrawerState, state),
                                  _buildTempConfigureTab(setDrawerState),
                                ],
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              setDrawerState(() {
                                _tempSelectedExpenseNames.clear();
                                _tempVisibleCards = List.from(
                                  widget.visibleCards,
                                );
                                _tempCardLimits = Map.from(widget.cardLimits);
                                _tempCardBoundaries = Map.from(
                                  widget.cardBoundaries,
                                );
                                _tempCardDueDates = Map.from(
                                  widget.cardDueDates,
                                );
                                _tempIsCreditCardOverrides = Map.from(
                                  widget.isCreditCardOverrides,
                                );
                              });
                              Navigator.pop(context);
                            },
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(0, 50),
                              side: BorderSide(color: Colors.grey.shade300),
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
                              widget.onApply(
                                _tempVisibleCards,
                                _tempSelectedExpenseNames,
                                _tempEditingCardName,
                                _tempCardLimits,
                                _tempCardBoundaries,
                                _tempCardDueDates,
                                _tempIsCreditCardOverrides,
                                _tempCategoryGroups,
                                _tempGroupColors,
                                _tempGroupLimits,
                              );
                              Navigator.pop(context);
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
            ),
          );
        },
      ),
    );
  }

  Widget _buildTempConfigureTab(StateSetter setDrawerState) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Manage Cards',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Toggle card visibility on your dashboard',
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
          const SizedBox(height: 24),
          if (widget.bankGroups.isEmpty)
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
                      'No cards discovered',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            )
          else
            ...widget.bankGroups.map((group) {
              final isSelected = _tempVisibleCards.contains(group.label);

              IconData bankIcon = Icons.account_balance_wallet_outlined;
              if (group.label.toUpperCase().contains('SBI'))
                bankIcon = Icons.account_balance_outlined;
              if (group.label.toUpperCase().contains('AXIS'))
                bankIcon = Icons.credit_card_outlined;
              if (group.label.toUpperCase().contains('HDFC'))
                bankIcon = Icons.payments_outlined;

              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.white
                      : Colors.grey.shade50.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected
                        ? Colors.black.withValues(alpha: 0.1)
                        : Colors.grey.shade200,
                    width: 1.5,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.03),
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
                        color: isSelected ? Colors.black : Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Icon(
                        bankIcon,
                        color: isSelected ? Colors.white : Colors.grey.shade600,
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
                    Switch.adaptive(
                      value: isSelected,
                      activeTrackColor: Colors.black,
                      inactiveTrackColor: Colors.white,
                      onChanged: (selected) {
                        setDrawerState(() {
                          if (selected) {
                            _tempVisibleCards.add(group.label);
                          } else {
                            _tempVisibleCards.remove(group.label);
                          }
                        });
                      },
                    ),
                  ],
              ));
            }),
          const SizedBox(height: 20),
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
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Official Privacy Policy',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(height: 2),
                          Text(
                            'privacypolicyofspenderpro.web.app',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white70,
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
        ],
      ),
    );
  }

  Widget _buildTempSettingsTab(StateSetter setDrawerState, ExpenseState state) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Card Settings',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          // Card Selection
          SizedBox(
            height: 40,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _tempVisibleCards.length,
              itemBuilder: (context, index) {
                final name = _tempVisibleCards[index];
                final isSelected = _tempEditingCardName == name;
                return GestureDetector(
                  onTap: () =>
                      setDrawerState(() => _tempEditingCardName = name),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.black : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Center(
                      child: Text(
                        name,
                        style: TextStyle(
                          color: isSelected ? Colors.white : Colors.black87,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 24),
          if (_tempEditingCardName != null) ...[
            _buildSection(
              'Card Information',
              Row(
                children: [
                  Icon(
                    _tempIsCreditCardOverrides[_tempEditingCardName!] == true
                        ? Icons.credit_card
                        : Icons.account_balance_wallet,
                    color: Colors.blue.shade900,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _tempIsCreditCardOverrides[_tempEditingCardName!] == true
                          ? 'Credit Card'
                          : 'Debit/Wallet',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  Switch.adaptive(
                    value:
                        _tempIsCreditCardOverrides[_tempEditingCardName!] ??
                        false,
                    activeTrackColor: Colors.black,
                    onChanged: (val) => setDrawerState(
                      () => _tempIsCreditCardOverrides[_tempEditingCardName!] =
                          val,
                    ),
                  ),
                ],
              ),
            ),
            _buildSection(
              'Monthly Limit',
              Column(
                children: [
                  Row(
                    children: [
                      const Text(
                        '₹',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            hintText: 'Enter limit (e.g. 50000)',
                          ),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                          onChanged: (val) {
                            final limit = double.tryParse(val);
                            if (limit != null) {
                              setDrawerState(
                                () => _tempCardLimits[_tempEditingCardName!] =
                                    limit,
                              );
                            }
                          },
                          controller:
                              TextEditingController(
                                  text:
                                      _tempCardLimits[_tempEditingCardName!]
                                          ?.toStringAsFixed(0) ??
                                      '',
                                )
                                ..selection = TextSelection.collapsed(
                                  offset:
                                      (_tempCardLimits[_tempEditingCardName!]
                                                  ?.toStringAsFixed(0) ??
                                              '')
                                          .length,
                                ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Set your total monthly spending capacity for this card',
                    style: TextStyle(color: Colors.grey, fontSize: 11),
                  ),
                ],
              ),
            ),
            _buildSection(
              'Alert Boundary',
              Column(
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.notification_important_outlined,
                        color: Colors.orange.shade700,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '₹${_tempCardBoundaries[_tempEditingCardName!]?.toStringAsFixed(0) ?? "0"}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: (_tempCardBoundaries[_tempEditingCardName!] ?? 0)
                        .clamp(
                          0,
                          _tempCardLimits[_tempEditingCardName!] ?? 100000,
                        ),
                    max: _tempCardLimits[_tempEditingCardName!] ?? 100000,
                    divisions: 20,
                    activeColor: Colors.orange,
                    inactiveColor: Colors.orange.shade50,
                    onChanged: (val) => setDrawerState(
                      () => _tempCardBoundaries[_tempEditingCardName!] = val,
                    ),
                  ),
                  const Text(
                    'You will be warned when spending exceeds this amount',
                    style: TextStyle(color: Colors.grey, fontSize: 11),
                  ),
                ],
              ),
            ),
            _buildSection(
              'Due Date',
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(
                  Icons.calendar_month,
                  color: Colors.black87,
                ),
                title: Text(
                  _tempCardDueDates[_tempEditingCardName!] == null
                      ? 'Not Set'
                      : DateFormat(
                          'dd MMMM',
                        ).format(_tempCardDueDates[_tempEditingCardName!]!),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final now = DateTime.now();
                  final initialDueDate = _tempCardDueDates[_tempEditingCardName!] ?? now;
                  final picked = await showDialog<DateTime>(
                    context: context,
                    builder: (context) => CustomBlueDatePickerDialog(
                      initialDate: initialDueDate.isAfter(now) ? now : initialDueDate,
                      firstDate: DateTime(2020),
                      lastDate: now,
                    ),
                  );
                  if (picked != null) {
                    setDrawerState(
                      () => _tempCardDueDates[_tempEditingCardName!] = picked,
                    );
                  }
                },
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'GROUP MANAGEMENT',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 12),
            ..._tempGroupColors.keys.map((label) {
              final color = Color(_tempGroupColors[label]!);
              final limit = _tempGroupLimits[label] ?? 0.0;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade100),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          if (limit > 0)
                            Text(
                              'Budget: ₹${limit.toStringAsFixed(0)}',
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 11,
                              ),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      onPressed: () =>
                          _showGroupEditDialog(context, label, setDrawerState),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.delete_outline,
                        size: 18,
                        color: Colors.redAccent,
                      ),
                      onPressed: () {
                        setDrawerState(() {
                          _tempGroupColors.remove(label);
                          _tempGroupLimits.remove(label);
                          _tempCategoryGroups.removeWhere((k, v) => v == label);
                        });
                      },
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  void _showGroupEditDialog(
    BuildContext context,
    String label,
    StateSetter setDrawerState,
  ) {
    final TextEditingController limitController = TextEditingController(
      text: _tempGroupLimits[label]?.toStringAsFixed(0) ?? '',
    );
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Edit Group: $label'),
          content: TextField(
            controller: limitController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Monthly Budget',
              prefixText: '₹ ',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final limit = double.tryParse(limitController.text);
                setDrawerState(() {
                  if (limit != null) {
                    _tempGroupLimits[label] = limit;
                  } else {
                    _tempGroupLimits.remove(label);
                  }
                });
                Navigator.pop(context);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildTempFilterTab(StateSetter setDrawerState, ExpenseState state) {
    if (state is! ExpenseLoaded)
      return const Center(child: CircularProgressIndicator());

    final normalizedCardName = _tempEditingCardName?.toUpperCase() ?? '';
    final cardExpenses = state.data.expenses.where((e) {
      final matchesBank =
          normalizedCardName.isEmpty ||
          e.bank.toUpperCase().contains(normalizedCardName) ||
          normalizedCardName.contains(e.bank.toUpperCase());
      return matchesBank && (e.type == 'spent' || e.type == 'debited');
    }).toList();

    final merchantTotals = <String, double>{};
    for (var e in cardExpenses) {
      final name = e.name.trim().toUpperCase();
      merchantTotals[name] = (merchantTotals[name] ?? 0) + e.amount;
    }

    final sortedMerchants = merchantTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Filter by Merchants',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                'Showing merchants for ${_tempEditingCardName ?? "all cards"}',
                style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: sortedMerchants.length,
            itemBuilder: (context, index) {
              final entry = sortedMerchants[index];
              final name = entry.key;
              final amount = entry.value;
              final isSelected = _tempSelectedExpenseNames.contains(name);
              final group = _tempCategoryGroups[name];

              return InkWell(
                onTap: () {
                  setDrawerState(() {
                    if (isSelected) {
                      _tempSelectedExpenseNames.remove(name);
                    } else {
                      _tempSelectedExpenseNames.add(name);
                    }
                  });
                },
                child: Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? Colors.black.withValues(alpha: 0.02)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected
                          ? Colors.black.withValues(alpha: 0.1)
                          : Colors.grey.shade100,
                    ),
                  ),
                  child: Row(
                    children: [
                      Checkbox(
                        value: isSelected,
                        activeColor: Colors.black,
                        onChanged: (val) {
                          setDrawerState(() {
                            if (val == true) {
                              _tempSelectedExpenseNames.add(name);
                            } else {
                              _tempSelectedExpenseNames.remove(name);
                            }
                          });
                        },
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            if (group != null)
                              Container(
                                margin: const EdgeInsets.only(top: 4),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Color(
                                    _tempGroupColors[group] ??
                                        Colors.grey.value,
                                  ).withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  group,
                                  style: TextStyle(
                                    color: Color(
                                      _tempGroupColors[group] ??
                                          Colors.grey.value,
                                    ),
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      Text(
                        '₹${amount.toStringAsFixed(0)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.blueGrey,
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
    );
  }

  Widget _buildSection(String title, Widget child) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade600,
              letterSpacing: 1.2,
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
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
          child: child,
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
