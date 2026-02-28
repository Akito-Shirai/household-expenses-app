import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../main.dart';
import '../models/analytics_bucket.dart';
import '../models/category.dart';
import '../models/transaction.dart' as model;
import '../models/user_settings.dart';
import '../repositories/category_repository.dart';
import '../repositories/transaction_repository.dart';
import '../theme/app_theme.dart';
import '../utils/error_handler.dart';
import '../utils/fx_converter.dart';
import '../widgets/state_views.dart';

/// 分析画面（日別/月別/年別グラフ + カテゴリフィルタ）
class AnalyticsScreen extends StatefulWidget {
  final UserSettings userSettings;

  const AnalyticsScreen({super.key, required this.userSettings});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  final _txRepo = TransactionRepository(supabase);
  final _catRepo = CategoryRepository(supabase);

  AnalyticsPeriod _period = AnalyticsPeriod.daily;
  late int _year;
  late int _month;

  List<model.Transaction> _transactions = [];
  List<Category> _allCategories = [];
  Set<String> _selectedCategoryIds = {};
  bool _isLoading = true;
  String? _errorMessage;

  /// 非同期競合防止用トークン（最新リクエストのみ反映）
  int _loadToken = 0;

  UserSettings get _settings => widget.userSettings;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _year = now.year;
    _month = now.month;
    _load();
  }

  Future<void> _load() async {
    final token = ++_loadToken;
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      late DateTime startDate;
      late DateTime endDate;

      switch (_period) {
        case AnalyticsPeriod.daily:
          // 日別: 対象月のデータ
          startDate = DateTime(_year, _month, 1);
          endDate = DateTime(_year, _month + 1, 1);
        case AnalyticsPeriod.monthly:
          // 月別: 対象年の1〜12月
          startDate = DateTime(_year, 1, 1);
          endDate = DateTime(_year + 1, 1, 1);
        case AnalyticsPeriod.yearly:
          // 年別: _year基準で5年分（_year-4 .. _year）
          startDate = DateTime(_year - 4, 1, 1);
          endDate = DateTime(_year + 1, 1, 1);
      }

      final transactions = await _txRepo.listByDateRange(startDate, endDate);
      final categories = await _catRepo.listAll();

      if (token != _loadToken || !mounted) return;
      setState(() {
        _transactions = transactions;
        _allCategories = categories;
        _isLoading = false;
      });
    } catch (e) {
      if (token != _loadToken || !mounted) return;
      final signedOut = await handleError(
        context: context,
        error: e,
        debugLabel: '分析データ読み込みエラー',
        userMessage: 'データの読み込みに失敗しました',
      );
      if (token != _loadToken || !mounted) return;
      if (!signedOut) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'データの読み込みに失敗しました';
        });
      }
    }
  }

  List<AnalyticsBucket> get _buckets => AnalyticsAggregator.aggregate(
        transactions: _transactions,
        period: _period,
        categoryIds: _selectedCategoryIds,
      );

  ({int totalExpense, int totalIncome, int net}) get _totals =>
      AnalyticsAggregator.totals(
        transactions: _transactions,
        categoryIds: _selectedCategoryIds,
      );

  /// 期間ナビゲーション（前/次）
  void _prev() {
    setState(() {
      switch (_period) {
        case AnalyticsPeriod.daily:
          if (_month == 1) {
            _year--;
            _month = 12;
          } else {
            _month--;
          }
        case AnalyticsPeriod.monthly:
          _year--;
        case AnalyticsPeriod.yearly:
          _year -= 5;
      }
    });
    _load();
  }

  void _next() {
    setState(() {
      switch (_period) {
        case AnalyticsPeriod.daily:
          if (_month == 12) {
            _year++;
            _month = 1;
          } else {
            _month++;
          }
        case AnalyticsPeriod.monthly:
          _year++;
        case AnalyticsPeriod.yearly:
          _year += 5;
      }
    });
    _load();
  }

  String get _periodLabel {
    switch (_period) {
      case AnalyticsPeriod.daily:
        return '$_year年$_month月';
      case AnalyticsPeriod.monthly:
        return '$_year年';
      case AnalyticsPeriod.yearly:
        return '${_year - 4}年〜$_year年';
    }
  }

  /// カテゴリフィルタダイアログ
  Future<void> _showCategoryFilter() async {
    final selected = Set<String>.from(_selectedCategoryIds);

    await showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('カテゴリフィルタ'),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    // 全選択/全解除
                    CheckboxListTile(
                      title: const Text('すべて表示'),
                      value: selected.isEmpty,
                      onChanged: (v) {
                        setDialogState(() {
                          selected.clear();
                        });
                      },
                    ),
                    const Divider(),
                    ..._allCategories.map((cat) {
                      return CheckboxListTile(
                        title: Text(cat.name),
                        subtitle: Text(
                          cat.type == 'expense' ? '支出' : '収入',
                          style: TextStyle(
                            fontSize: 12,
                            color: cat.type == 'expense'
                                ? AppTheme.expenseColor
                                : AppTheme.incomeColor,
                          ),
                        ),
                        value: selected.contains(cat.id),
                        onChanged: (v) {
                          setDialogState(() {
                            if (v == true) {
                              selected.add(cat.id);
                            } else {
                              selected.remove(cat.id);
                            }
                          });
                        },
                      );
                    }),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('キャンセル'),
                ),
                FilledButton(
                  onPressed: () {
                    setState(() => _selectedCategoryIds = selected);
                    Navigator.pop(context);
                  },
                  child: const Text('適用'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildChart() {
    final buckets = _buckets;

    if (buckets.isEmpty) {
      return SizedBox(
        height: 250,
        child: EmptyStateView(
          icon: Icons.bar_chart_outlined,
          title: '表示するデータがありません',
          subtitle: '期間やフィルタ条件を変更してみてください',
        ),
      );
    }

    final maxValue = buckets.fold<int>(0, (max, b) {
      final bucketMax = [b.expense, b.income, b.net.abs()].reduce(
        (a, b) => a > b ? a : b,
      );
      return bucketMax > max ? bucketMax : max;
    });

    // Y軸の上限（余裕を持たせる）
    final maxY = maxValue == 0 ? 1000.0 : maxValue * 1.2;

    return SizedBox(
      height: 250,
      child: Padding(
        padding: const EdgeInsets.only(
          left: AppTheme.spacingSm,
          right: AppTheme.spacingMd,
          top: AppTheme.spacingMd,
        ),
        child: BarChart(
          BarChartData(
            alignment: BarChartAlignment.spaceAround,
            maxY: maxY,
            barTouchData: BarTouchData(
              touchTooltipData: BarTouchTooltipData(
                getTooltipItem: (group, groupIndex, rod, rodIndex) {
                  final bucket = buckets[groupIndex];
                  final labels = ['支出', '収入', '収支'];
                  final values = [bucket.expense, bucket.income, bucket.net];
                  return BarTooltipItem(
                    '${bucket.label}\n${labels[rodIndex]}: ${MoneyFormatter.format(values[rodIndex].abs(), _settings)}',
                    const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                    ),
                  );
                },
              ),
            ),
            titlesData: FlTitlesData(
              show: true,
              bottomTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  getTitlesWidget: (value, meta) {
                    final index = value.toInt();
                    if (index < 0 || index >= buckets.length) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        buckets[index].label,
                        style: const TextStyle(fontSize: 10),
                      ),
                    );
                  },
                  reservedSize: 28,
                ),
              ),
              leftTitles: AxisTitles(
                sideTitles: SideTitles(
                  showTitles: true,
                  reservedSize: 48,
                  getTitlesWidget: (value, meta) {
                    if (value == meta.max || value == meta.min) {
                      return const SizedBox.shrink();
                    }
                    final formatted = _formatAxisValue(value);
                    return Text(
                      formatted,
                      style: const TextStyle(fontSize: 10),
                    );
                  },
                ),
              ),
              topTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
              rightTitles: const AxisTitles(
                sideTitles: SideTitles(showTitles: false),
              ),
            ),
            borderData: FlBorderData(show: false),
            gridData: FlGridData(
              show: true,
              drawVerticalLine: false,
              horizontalInterval: maxY / 4,
            ),
            barGroups: buckets.asMap().entries.map((entry) {
              final i = entry.key;
              final b = entry.value;
              return BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: b.expense.toDouble(),
                    color: AppTheme.expenseColor.withAlpha(200),
                    width: 8,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(2),
                    ),
                  ),
                  BarChartRodData(
                    toY: b.income.toDouble(),
                    color: AppTheme.incomeColor.withAlpha(200),
                    width: 8,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(2),
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  /// Y軸の値をフォーマット（1000→1K、10000→10K）
  String _formatAxisValue(double value) {
    if (value >= 10000) {
      return '${(value / 10000).toStringAsFixed(0)}万';
    } else if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(0)}K';
    }
    return value.toInt().toString();
  }

  Widget _buildTotals() {
    final totals = _totals;
    final netColor =
        totals.net >= 0 ? AppTheme.positiveColor : AppTheme.expenseColor;

    return Card(
      margin: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacingMd,
        vertical: AppTheme.spacingSm,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacingMd),
        child: Row(
          children: [
            Expanded(
              child: _totalItem('支出', totals.totalExpense, AppTheme.expenseColor),
            ),
            Container(
              width: 1,
              height: 36,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            Expanded(
              child: _totalItem('収入', totals.totalIncome, AppTheme.incomeColor),
            ),
            Container(
              width: 1,
              height: 36,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            Expanded(
              child: _totalItem('収支', totals.net, netColor),
            ),
          ],
        ),
      ),
    );
  }

  Widget _totalItem(String label, int amount, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 11, color: AppTheme.subtleText),
        ),
        const SizedBox(height: AppTheme.spacingXs),
        Text(
          MoneyFormatter.formatSigned(amount, _settings),
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildLegend() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppTheme.spacingMd),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _legendItem('支出', AppTheme.expenseColor),
          const SizedBox(width: AppTheme.spacingMd),
          _legendItem('収入', AppTheme.incomeColor),
        ],
      ),
    );
  }

  Widget _legendItem(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color.withAlpha(200),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }

  Widget _buildFilterChips() {
    if (_selectedCategoryIds.isEmpty) return const SizedBox.shrink();

    final selectedNames = _allCategories
        .where((c) => _selectedCategoryIds.contains(c.id))
        .map((c) => c.name)
        .toList();

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacingMd,
        vertical: AppTheme.spacingXs,
      ),
      child: Wrap(
        spacing: AppTheme.spacingSm,
        runSpacing: AppTheme.spacingXs,
        children: [
          ...selectedNames.map(
            (name) => Chip(
              label: Text(name, style: const TextStyle(fontSize: 12)),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          ActionChip(
            label: const Text('クリア', style: TextStyle(fontSize: 12)),
            visualDensity: VisualDensity.compact,
            onPressed: () => setState(() => _selectedCategoryIds = {}),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('分析'),
        actions: [
          IconButton(
            icon: Badge(
              isLabelVisible: _selectedCategoryIds.isNotEmpty,
              label: Text('${_selectedCategoryIds.length}'),
              child: const Icon(Icons.filter_list),
            ),
            tooltip: 'カテゴリフィルタ',
            onPressed: _isLoading ? null : _showCategoryFilter,
          ),
        ],
      ),
      body: _isLoading
          ? const LoadingView(message: 'データを読み込み中...')
          : _errorMessage != null
              ? ErrorStateView(message: _errorMessage!, onRetry: _load)
              : SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 粒度切替
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppTheme.spacingMd,
                          vertical: AppTheme.spacingSm,
                        ),
                        child: SegmentedButton<AnalyticsPeriod>(
                          segments: const [
                            ButtonSegment(
                              value: AnalyticsPeriod.daily,
                              label: Text('日別'),
                            ),
                            ButtonSegment(
                              value: AnalyticsPeriod.monthly,
                              label: Text('月別'),
                            ),
                            ButtonSegment(
                              value: AnalyticsPeriod.yearly,
                              label: Text('年別'),
                            ),
                          ],
                          selected: {_period},
                          onSelectionChanged: (selected) {
                            setState(() => _period = selected.first);
                            _load();
                          },
                        ),
                      ),

                      // 期間ナビゲーション
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppTheme.spacingMd,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.chevron_left),
                              onPressed: _prev,
                            ),
                            Text(
                              _periodLabel,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            IconButton(
                              icon: const Icon(Icons.chevron_right),
                              onPressed: _next,
                            ),
                          ],
                        ),
                      ),

                      // フィルタチップ表示
                      _buildFilterChips(),

                      // グラフ
                      _buildChart(),

                      // 凡例
                      const SizedBox(height: AppTheme.spacingSm),
                      _buildLegend(),

                      // 合計
                      const SizedBox(height: AppTheme.spacingSm),
                      _buildTotals(),

                      const SizedBox(height: AppTheme.spacingLg),
                    ],
                  ),
                ),
    );
  }
}
