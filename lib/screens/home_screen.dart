import 'package:flutter/material.dart';

import '../main.dart';
import '../models/transaction.dart' as model;
import '../models/user_settings.dart';
import '../repositories/transaction_repository.dart';
import '../repositories/user_settings_repository.dart';
import '../utils/error_handler.dart';
import '../utils/fx_converter.dart';
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
    setState(() => _isLoading = true);
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
          (settings.displayCurrency == 'JPY' || settings.effectiveRate != null)) {
        _rateMissingNotified = false;
      }
    } catch (e) {
      if (token != _loadToken || !mounted) return;
      setState(() => _isLoading = false);
      await handleError(
        context: context,
        error: e,
        debugLabel: '取引読み込みエラー',
        userMessage: 'データの読み込みに失敗しました',
      );
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

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 収支サマリー
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _summaryItem('収入', summary.totalIncome, Colors.blue),
                _summaryItem('支出', summary.totalExpense, Colors.red),
                _summaryItem(
                  '収支',
                  summary.net,
                  summary.net >= 0 ? Colors.green : Colors.red,
                ),
              ],
            ),
            // カテゴリ別展開（金額降順ソート）
            if (summary.expenseByCategory.isNotEmpty) ...[
              const Divider(height: 24),
              const Text(
                '支出内訳',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 4),
              ..._sortedEntries(
                summary.expenseByCategory,
              ).map((e) => _categoryRow(e.key, e.value)),
            ],
            if (summary.incomeByCategory.isNotEmpty) ...[
              const Divider(height: 24),
              const Text(
                '収入内訳',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 4),
              ..._sortedEntries(
                summary.incomeByCategory,
              ).map((e) => _categoryRow(e.key, e.value)),
            ],
          ],
        ),
      ),
    );
  }

  /// カテゴリ別Mapを金額降順でソート
  List<MapEntry<String, int>> _sortedEntries(Map<String, int> map) {
    final entries = map.entries.toList();
    entries.sort((a, b) => b.value.compareTo(a.value));
    return entries;
  }

  Widget _summaryItem(String label, int amount, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 4),
        Text(
          MoneyFormatter.formatSigned(amount, _settings),
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
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
            style: const TextStyle(fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionList() {
    if (_transactions.isEmpty) {
      return const SliverFillRemaining(child: Center(child: Text('取引がありません')));
    }

    return SliverList(
      delegate: SliverChildBuilderDelegate((context, index) {
        final tx = _transactions[index];
        final isExpense = tx.type == 'expense';
        return ListTile(
          leading: Icon(
            isExpense ? Icons.remove_circle_outline : Icons.add_circle_outline,
            color: isExpense ? Colors.red : Colors.blue,
          ),
          title: Text(tx.categoryName ?? '不明'),
          subtitle: Text(
            '${tx.date.month}/${tx.date.day}${tx.memo != null && tx.memo!.isNotEmpty ? '  ${tx.memo}' : ''}',
          ),
          trailing: Text(
            MoneyFormatter.formatWithSign(tx.amount, _settings, isExpense: isExpense),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isExpense ? Colors.red : Colors.blue,
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
          ? const Center(child: CircularProgressIndicator())
          : CustomScrollView(
              slivers: [
                // 年月ナビゲーション
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.chevron_left),
                          onPressed: _prevMonth,
                        ),
                        Text(
                          '$_year年$_month月',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_right),
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
                    padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Text(
                      '取引一覧',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
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
