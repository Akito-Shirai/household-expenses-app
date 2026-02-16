import 'package:flutter/material.dart';

import '../main.dart';
import '../models/transaction.dart' as model;
import '../repositories/transaction_repository.dart';
import '../utils/error_handler.dart';
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

  late int _year;
  late int _month;
  List<model.Transaction> _transactions = [];
  MonthlySummary? _summary;
  bool _isLoading = true;

  /// 非同期競合防止用トークン（最新リクエストのみ反映）
  int _loadToken = 0;

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
      if (token != _loadToken || !mounted) return;
      final summary = TransactionRepository.summarize(transactions);
      setState(() {
        _transactions = transactions;
        _summary = summary;
        _isLoading = false;
      });
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
        builder: (_) => TransactionEditScreen(existing: existing),
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

  /// 金額フォーマット（3桁カンマ区切り）
  String _formatAmount(int amount) {
    final str = amount.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < str.length; i++) {
      if (i > 0 && (str.length - i) % 3 == 0) buffer.write(',');
      buffer.write(str[i]);
    }
    return buffer.toString();
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
    // N-3: 収支がマイナスの場合は符号付き表示
    final prefix = amount < 0 ? '-¥' : '¥';
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 4),
        Text(
          '$prefix${_formatAmount(amount.abs())}',
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
            '¥${_formatAmount(amount)}',
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
            '${isExpense ? '-' : '+'}¥${_formatAmount(tx.amount)}',
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
