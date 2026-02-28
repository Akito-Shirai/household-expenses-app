import 'package:flutter/material.dart';

import '../main.dart';
import '../models/transaction.dart' as model;
import '../models/user_settings.dart';
import '../repositories/transaction_repository.dart';
import '../repositories/user_settings_repository.dart';
import '../theme/app_theme.dart';
import '../utils/error_handler.dart';
import '../utils/fx_converter.dart';
import '../utils/fx_fetch_service.dart';
import '../widgets/state_views.dart';
import 'analytics_screen.dart';
import 'settings_screen.dart';
import 'transaction_edit_screen.dart';

/// ホーム画面（取引一覧 + 月次サマリー）
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _txRepo = TransactionRepository(supabase);
  final _settingsRepo = UserSettingsRepository(supabase);

  late int _year;
  late int _month;
  List<model.Transaction> _transactions = [];
  MonthlySummary? _summary;
  UserSettings? _userSettings;
  bool _isLoading = true;
  String? _errorMessage;

  /// レート未設定通知を1回だけ表示するフラグ
  bool _rateMissingNotified = false;

  /// 非同期競合防止用トークン（最新リクエストのみ反映）
  int _loadToken = 0;

  /// フォールバック用のデフォルト設定
  UserSettings get _settings =>
      _userSettings ?? UserSettings.defaults(supabase.auth.currentUser?.id ?? '');

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
      final transactions = await _txRepo.listByMonth(_year, _month);
      // 通貨設定の取得（失敗してもフォールバックで動作）
      UserSettings? settings;
      try {
        settings = await _settingsRepo.getOrCreate();
      } catch (e) {
        debugPrint('通貨設定読み込みエラー: $e');
      }
      if (token != _loadToken || !mounted) return;
      final summary = TransactionRepository.summarize(transactions);
      setState(() {
        _transactions = transactions;
        _summary = summary;
        if (settings != null) _userSettings = settings;
        _isLoading = false;
      });
      // レート未設定時の通知（同一セッション内で1回のみ）
      if (!_rateMissingNotified &&
          settings != null &&
          settings.displayCurrency != 'JPY' &&
          settings.effectiveRate == null &&
          mounted) {
        _rateMissingNotified = true;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('為替レートが未設定のため、JPYで表示しています'),
          ),
        );
      }
      // 設定が正常に反映された場合はフラグをリセット（次回通貨変更時に再通知可能に）
      if (settings != null &&
          (settings.displayCurrency == 'JPY' ||
              settings.effectiveRate != null)) {
        _rateMissingNotified = false;
      }
      // autoモードかつlast_rateが古い場合、バックグラウンドでベストエフォート更新
      // （一覧描画をブロックしない fire-and-forget）
      if (settings != null &&
          settings.fxMode == 'auto' &&
          settings.displayCurrency != 'JPY' &&
          settings.isLastRateStale) {
        _refreshRateInBackground(token, settings.displayCurrency);
      }
    } catch (e) {
      if (token != _loadToken || !mounted) return;
      // 認証系エラー（42501）はhandleErrorで処理（セッション切れ→サインアウト導線）
      final signedOut = await handleError(
        context: context,
        error: e,
        debugLabel: '取引読み込みエラー',
        userMessage: 'データの読み込みに失敗しました',
      );
      if (!mounted) return;
      // サインアウトされた場合はErrorStateView不要（AuthGateでログイン画面に遷移）
      if (!signedOut) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'データの読み込みに失敗しました';
        });
      }
    }
  }

  /// バックグラウンドでレートを更新し、成功時のみ表示を差し替える
  Future<void> _refreshRateInBackground(int token, String currency) async {
    try {
      final newRate = await FxFetchService.fetchJpyRate(currency);
      if (token != _loadToken || !mounted || newRate == null) return;
      final updated = await _settingsRepo.updateLastRate(newRate);
      if (token != _loadToken || !mounted) return;
      setState(() => _userSettings = updated);
    } catch (e) {
      debugPrint('バックグラウンドレート更新エラー: $e');
    }
  }

  /// 前月へ
  void _prevMonth() {
    setState(() {
      if (_month == 1) {
        _year--;
        _month = 12;
      } else {
        _month--;
      }
    });
    _load();
  }

  /// 翌月へ
  void _nextMonth() {
    setState(() {
      if (_month == 12) {
        _year++;
        _month = 1;
      } else {
        _month++;
      }
    });
    _load();
  }

  /// 取引追加/編集画面へ遷移
  Future<void> _openTransactionEdit({model.Transaction? existing}) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => TransactionEditScreen(
          existing: existing,
          userSettings: _settings,
        ),
      ),
    );
    if (!mounted) return;
    if (result == true) _load();
  }

  /// 設定画面へ遷移
  Future<void> _openSettings() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const SettingsScreen()),
    );
    if (!mounted) return;
    _load();
  }

  Widget _buildSummaryCard() {
    final summary = _summary;
    if (summary == null) return const SizedBox.shrink();

    final netColor = summary.net >= 0
        ? AppTheme.positiveColor
        : AppTheme.expenseColor;

    return Card(
      margin: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacingMd,
        vertical: AppTheme.spacingSm,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacingMd),
        child: Column(
          children: [
            // 収支（最も強調）
            Text(
              '収支',
              style: TextStyle(
                fontSize: 13,
                color: AppTheme.subtleText,
              ),
            ),
            const SizedBox(height: AppTheme.spacingXs),
            Text(
              MoneyFormatter.formatSigned(summary.net, _settings),
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.bold,
                color: netColor,
              ),
            ),
            const SizedBox(height: AppTheme.spacingMd),
            // 収入・支出を横並び
            Row(
              children: [
                Expanded(
                  child: _summaryItem(
                    '収入',
                    summary.totalIncome,
                    AppTheme.incomeColor,
                  ),
                ),
                Container(
                  width: 1,
                  height: 36,
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                Expanded(
                  child: _summaryItem(
                    '支出',
                    summary.totalExpense,
                    AppTheme.expenseColor,
                  ),
                ),
              ],
            ),
            // カテゴリ別内訳
            if (summary.expenseByCategory.isNotEmpty) ...[
              const Divider(height: AppTheme.spacingLg),
              _buildCategoryBreakdown(
                '支出内訳',
                summary.expenseByCategory,
                AppTheme.expenseColor,
              ),
            ],
            if (summary.incomeByCategory.isNotEmpty) ...[
              const Divider(height: AppTheme.spacingLg),
              _buildCategoryBreakdown(
                '収入内訳',
                summary.incomeByCategory,
                AppTheme.incomeColor,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryBreakdown(
    String title,
    Map<String, int> categoryMap,
    Color color,
  ) {
    final sorted = categoryMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: color,
          ),
        ),
        const SizedBox(height: AppTheme.spacingXs),
        ...sorted.map((e) => _categoryRow(e.key, e.value)),
      ],
    );
  }

  Widget _summaryItem(String label, int amount, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 12, color: AppTheme.subtleText),
        ),
        const SizedBox(height: AppTheme.spacingXs),
        Text(
          MoneyFormatter.formatSigned(amount, _settings),
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _categoryRow(String name, int amount) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(name, style: const TextStyle(fontSize: 13)),
          Text(
            MoneyFormatter.format(amount, _settings),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionList() {
    if (_transactions.isEmpty) {
      return SliverFillRemaining(
        child: EmptyStateView(
          icon: Icons.receipt_long_outlined,
          title: 'この月の取引はありません',
          subtitle: '「＋」ボタンから取引を追加しましょう',
          actionLabel: '取引を追加',
          onAction: () => _openTransactionEdit(),
        ),
      );
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        final tx = _transactions[index];
        final isExpense = tx.type == 'expense';
        final txColor = isExpense ? AppTheme.expenseColor : AppTheme.incomeColor;
        return ListTile(
          leading: Icon(
            isExpense ? Icons.remove_circle_outline : Icons.add_circle_outline,
            color: txColor,
          ),
          title: Text(tx.categoryName ?? '不明'),
          subtitle: Text(
            '${tx.date.month}/${tx.date.day}${tx.memo != null && tx.memo!.isNotEmpty ? '  ${tx.memo}' : ''}',
          ),
          trailing: Text(
            MoneyFormatter.formatWithSign(tx.amount, _settings, isExpense: isExpense),
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: txColor,
            ),
          ),
          onTap: () => _openTransactionEdit(existing: tx),
        );
      }, childCount: _transactions.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('家計簿'),
        actions: [
          IconButton(
            icon: const Icon(Icons.bar_chart_outlined),
            tooltip: '分析',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AnalyticsScreen(userSettings: _settings),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: '設定',
            onPressed: _openSettings,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'ログアウト',
            onPressed: () async {
              await supabase.auth.signOut();
            },
          ),
        ],
      ),
      body: _isLoading
          ? const LoadingView(message: '読み込み中...')
          : _errorMessage != null
              ? ErrorStateView(
                  message: _errorMessage!,
                  onRetry: _load,
                )
              : CustomScrollView(
              slivers: [
                // 年月ナビゲーション
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppTheme.spacingMd,
                      vertical: AppTheme.spacingSm,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.chevron_left),
                          tooltip: '前月',
                          onPressed: _prevMonth,
                        ),
                        Semantics(
                          header: true,
                          child: Text(
                            '$_year年$_month月',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_right),
                          tooltip: '翌月',
                          onPressed: _nextMonth,
                        ),
                      ],
                    ),
                  ),
                ),
                // サマリーカード
                SliverToBoxAdapter(child: _buildSummaryCard()),
                // 取引一覧ヘッダー
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      AppTheme.spacingMd,
                      AppTheme.spacingSm,
                      AppTheme.spacingMd,
                      AppTheme.spacingXs,
                    ),
                    child: Text(
                      '取引一覧',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
                // 取引リスト
                _buildTransactionList(),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openTransactionEdit(),
        tooltip: '取引追加',
        child: const Icon(Icons.add),
      ),
    );
  }
}
