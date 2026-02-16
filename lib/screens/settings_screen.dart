import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../main.dart';
import '../models/category.dart';
import '../models/user_settings.dart';
import '../repositories/category_repository.dart';
import '../repositories/user_settings_repository.dart';
import '../utils/error_handler.dart';
import '../utils/fx_converter.dart';

/// 設定画面（通貨設定 + カテゴリ管理）
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _repo = CategoryRepository(supabase);
  final _settingsRepo = UserSettingsRepository(supabase);
  final _rateController = TextEditingController();

  List<Category> _expenseCategories = [];
  List<Category> _incomeCategories = [];
  String _selectedCurrency = 'JPY';
  String _selectedFxMode = 'manual';
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isSavingCurrency = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _rateController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final expenses = await _repo.list('expense');
      final incomes = await _repo.list('income');
      UserSettings? settings;
      try {
        settings = await _settingsRepo.getOrCreate();
      } catch (e) {
        debugPrint('通貨設定読み込みエラー: $e');
      }
      if (mounted) {
        setState(() {
          _expenseCategories = expenses;
          _incomeCategories = incomes;
          if (settings != null) {
            _selectedCurrency = settings.displayCurrency;
            _selectedFxMode = settings.fxMode;
            _rateController.text = settings.manualRate?.toString() ?? '';
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        await handleError(
          context: context,
          error: e,
          debugLabel: 'カテゴリ読み込みエラー',
          userMessage: 'カテゴリの読み込みに失敗しました',
        );
      }
    }
  }

  /// 通貨設定を保存
  Future<void> _saveCurrencySettings() async {
    if (_isSavingCurrency) return;

    // レートのバリデーション（JPY以外で入力がある場合）
    double? manualRate;
    if (_selectedCurrency != 'JPY') {
      final rateText = _rateController.text.trim();
      if (rateText.isNotEmpty) {
        manualRate = double.tryParse(rateText);
        if (manualRate == null || manualRate <= 0) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('レートは正の数値を入力してください')),
          );
          return;
        }
      }
    }

    setState(() => _isSavingCurrency = true);
    try {
      await _settingsRepo.updateCurrencySettings(
        currency: _selectedCurrency,
        manualRate: manualRate,
        fxMode: _selectedFxMode,
      );
      if (mounted) {
        setState(() => _isSavingCurrency = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('通貨設定を保存しました')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSavingCurrency = false);
        await handleError(
          context: context,
          error: e,
          debugLabel: '通貨設定保存エラー',
          userMessage: '通貨設定の保存に失敗しました',
        );
      }
    }
  }

  /// 通貨設定セクション
  Widget _buildCurrencySection() {
    // 通貨ラベルのマップ
    const currencyLabels = {
      'JPY': 'JPY (¥)',
      'USD': 'USD (\$)',
      'AUD': 'AUD (A\$)',
      'EUR': 'EUR (€)',
      'GBP': 'GBP (£)',
    };

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '表示通貨設定',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 4),
            const Text(
              '金額の表示通貨を変更します。保存値はJPY基準のまま維持されます。',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            // 通貨選択ドロップダウン
            DropdownButtonFormField<String>(
              initialValue: _selectedCurrency,
              decoration: const InputDecoration(
                labelText: '表示通貨',
                border: OutlineInputBorder(),
              ),
              items: UserSettings.supportedCurrencies.map((c) {
                return DropdownMenuItem(
                  value: c,
                  child: Text(currencyLabels[c] ?? c),
                );
              }).toList(),
              onChanged: _isSavingCurrency
                  ? null
                  : (v) {
                      if (v != null) {
                        setState(() => _selectedCurrency = v);
                        // JPYに戻す場合はレート入力をクリア
                        if (v == 'JPY') {
                          _rateController.clear();
                        }
                      }
                    },
            ),
            // JPY以外の場合にモード選択とレート入力を表示
            if (_selectedCurrency != 'JPY') ...[
              const SizedBox(height: 12),
              // FXモード選択
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'manual',
                    label: Text('手動'),
                    icon: Icon(Icons.edit),
                  ),
                  ButtonSegment(
                    value: 'auto',
                    label: Text('自動'),
                    icon: Icon(Icons.sync),
                    enabled: false,
                  ),
                ],
                selected: {_selectedFxMode},
                onSelectionChanged: _isSavingCurrency
                    ? null
                    : (selected) {
                        setState(() => _selectedFxMode = selected.first);
                      },
              ),
              const SizedBox(height: 4),
              if (_selectedFxMode == 'auto')
                const Text(
                  '自動レート更新は今後のアップデートで対応予定です',
                  style: TextStyle(fontSize: 11, color: Colors.orange),
                ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _rateController,
                decoration: InputDecoration(
                  labelText: '為替レート (1 ${MoneyFormatter.symbol(_selectedCurrency)} = ? JPY)',
                  border: const OutlineInputBorder(),
                  hintText: '例: 150.5',
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                ],
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _isSavingCurrency ? null : _saveCurrencySettings,
                child: _isSavingCurrency
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('通貨設定を保存'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// カテゴリ追加/編集ダイアログ
  Future<void> _showCategoryDialog({
    required String type,
    Category? existing,
  }) async {
    if (_isSaving) return;

    final nameController = TextEditingController(text: existing?.name ?? '');
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(existing == null ? 'カテゴリ追加' : 'カテゴリ編集'),
          content: Form(
            key: formKey,
            child: TextFormField(
              controller: nameController,
              decoration: const InputDecoration(
                labelText: 'カテゴリ名',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
              validator: (v) {
                if (v == null || v.trim().isEmpty) return 'カテゴリ名を入力してください';
                return null;
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(context, nameController.text.trim());
                }
              },
              child: const Text('保存'),
            ),
          ],
        );
      },
    );

    if (result == null) return;

    setState(() => _isSaving = true);
    try {
      if (existing == null) {
        final list = type == 'expense' ? _expenseCategories : _incomeCategories;
        await _repo.create(name: result, type: type, sortOrder: list.length);
      } else {
        await _repo.update(
          id: existing.id,
          name: result,
          sortOrder: existing.sortOrder,
        );
      }
      await _load();
    } catch (e) {
      if (mounted) {
        await handleError(
          context: context,
          error: e,
          debugLabel: 'カテゴリ保存エラー',
          userMessage: 'カテゴリの保存に失敗しました',
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// カテゴリ削除（確認ダイアログ付き）
  Future<void> _deleteCategory(Category category) async {
    if (_isSaving) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('カテゴリ削除'),
          content: Text(
            '「${category.name}」を削除しますか？\nこのカテゴリを使用中の取引がある場合、削除できません。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('削除'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    setState(() => _isSaving = true);
    try {
      await _repo.delete(category.id);
      await _load();
    } on PostgrestException catch (e) {
      debugPrint('カテゴリ削除エラー (PostgrestException): ${e.message}');
      if (mounted) {
        if (e.code == '42501') {
          await handleError(
            context: context,
            error: e,
            debugLabel: 'カテゴリ削除 RLS違反',
            userMessage: '',
          );
        } else {
          final message = e.code == '23503'
              ? 'このカテゴリを使用中の取引があるため削除できません'
              : 'カテゴリの削除に失敗しました';
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(message)));
        }
      }
    } catch (e) {
      if (mounted) {
        await handleError(
          context: context,
          error: e,
          debugLabel: 'カテゴリ削除エラー',
          userMessage: 'カテゴリの削除に失敗しました',
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _buildCategoryList(String type) {
    final categories = type == 'expense'
        ? _expenseCategories
        : _incomeCategories;

    if (categories.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('カテゴリがありません'),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _isSaving
                  ? null
                  : () => _showCategoryDialog(type: type),
              icon: const Icon(Icons.add),
              label: const Text('追加'),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: categories.length,
      itemBuilder: (context, index) {
        final cat = categories[index];
        return ListTile(
          title: Text(cat.name),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.edit),
                tooltip: '編集',
                onPressed: _isSaving
                    ? null
                    : () => _showCategoryDialog(type: type, existing: cat),
              ),
              IconButton(
                icon: const Icon(Icons.delete),
                tooltip: '削除',
                onPressed: _isSaving ? null : () => _deleteCategory(cat),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('設定'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // 通貨設定セクション
                _buildCurrencySection(),
                // カテゴリ管理タブ
                TabBar(
                  controller: _tabController,
                  tabs: const [
                    Tab(text: '支出カテゴリ'),
                    Tab(text: '収入カテゴリ'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildCategoryList('expense'),
                      _buildCategoryList('income'),
                    ],
                  ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _isSaving
            ? null
            : () {
                final type = _tabController.index == 0 ? 'expense' : 'income';
                _showCategoryDialog(type: type);
              },
        tooltip: 'カテゴリ追加',
        child: const Icon(Icons.add),
      ),
    );
  }
}
