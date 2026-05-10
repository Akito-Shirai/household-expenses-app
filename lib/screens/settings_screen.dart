import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../main.dart';
import '../models/category.dart';
import '../models/recurring_rule.dart';
import '../models/user_settings.dart';
import '../repositories/category_repository.dart';
import '../repositories/recurring_rule_repository.dart';
import '../repositories/user_settings_repository.dart';
import '../theme/app_theme.dart';
import '../utils/error_handler.dart';
import '../utils/fx_converter.dart';
import '../utils/fx_fetch_service.dart';
import '../widgets/state_views.dart';

/// 設定画面（通貨設定 + カテゴリ管理）
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  /// 定期支出ルール削除確認ダイアログのタイトル（テスト容易性のため公開）
  static const String recurringRuleDeleteDialogTitle = '定期支出ルール削除';

  /// 定期支出ルール削除確認ダイアログ本文（テスト容易性のため公開）
  ///
  /// 削除（destructive）と無効化（一時停止）を区別するため、
  /// 削除後も既存取引が残ることと、再生成されないことを明示する。
  static const String recurringRuleDeleteDialogMessage =
      'この定期支出を削除しますか？\n'
      '既に作成された取引は通常取引として残ります。\n'
      '今後、この定期支出から自動作成されることはありません。';

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final _repo = CategoryRepository(supabase);
  final _settingsRepo = UserSettingsRepository(supabase);
  final _recurringRepo = RecurringRuleRepository(supabase);
  final _rateController = TextEditingController();

  List<Category> _expenseCategories = [];
  List<Category> _incomeCategories = [];
  List<RecurringRule> _recurringRules = [];
  String _selectedCurrency = 'JPY';
  String _selectedFxMode = 'manual';
  UserSettings? _currentSettings;
  bool _isLoading = true;
  String? _errorMessage;
  bool _isSaving = false;
  bool _isSavingCurrency = false;
  bool _isFetchingRate = false;

  /// 通貨設定に未保存の差分があるか（通貨・FXモードがDB値と異なる）
  bool get _hasUnsavedCurrencyChanges {
    final saved = _currentSettings;
    if (saved == null) return true;
    return _selectedCurrency != saved.displayCurrency ||
        _selectedFxMode != saved.fxMode;
  }

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
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final expenses = await _repo.list('expense');
      final incomes = await _repo.list('income');
      final rules = await _recurringRepo.listAll();
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
          _recurringRules = rules;
          if (settings != null) {
            _selectedCurrency = settings.displayCurrency;
            _selectedFxMode = settings.fxMode;
            _rateController.text = settings.manualRate?.toString() ?? '';
            _currentSettings = settings;
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        // 認証系エラー（42501）はhandleErrorで処理（セッション切れ→サインアウト導線）
        final signedOut = await handleError(
          context: context,
          error: e,
          debugLabel: 'カテゴリ読み込みエラー',
          userMessage: 'データの読み込みに失敗しました',
        );
        if (!mounted) return;
        if (!signedOut) {
          setState(() {
            _isLoading = false;
            _errorMessage = 'データの読み込みに失敗しました';
          });
        }
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
      final updated = await _settingsRepo.updateCurrencySettings(
        currency: _selectedCurrency,
        manualRate: manualRate,
        fxMode: _selectedFxMode,
      );
      if (mounted) {
        setState(() {
          _isSavingCurrency = false;
          _currentSettings = updated;
        });
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

  /// 自動モード情報パネル（最終更新時刻・適用中レート・手動更新ボタン）
  Widget _buildAutoRateInfo() {
    final settings = _currentSettings;
    final lastRate = settings?.lastRate;
    final lastRateAt = settings?.lastRateAt;

    String rateText;
    if (lastRate != null) {
      rateText = '1 $_selectedCurrency = ${lastRate.toStringAsFixed(2)} JPY';
    } else if (settings?.manualRate != null) {
      rateText = '手動レートを使用中: 1 $_selectedCurrency = ${settings!.manualRate!.toStringAsFixed(2)} JPY';
    } else {
      rateText = 'レート未取得（JPY表示へフォールバック）';
    }

    String updatedAtText;
    if (lastRateAt != null) {
      final local = lastRateAt.toLocal();
      updatedAtText =
          '最終更新: ${local.year}/${local.month.toString().padLeft(2, '0')}/${local.day.toString().padLeft(2, '0')} '
          '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
    } else {
      updatedAtText = '最終更新: 未取得';
    }

    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingSm),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            rateText,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 4),
          Text(
            updatedAtText,
            style: TextStyle(fontSize: 11, color: AppTheme.subtleText),
          ),
          const SizedBox(height: AppTheme.spacingSm),
          if (_hasUnsavedCurrencyChanges) ...[
            Text(
              '※ 通貨設定を先に保存してください',
              style: TextStyle(fontSize: 11, color: AppTheme.warningColor),
            ),
            const SizedBox(height: AppTheme.spacingXs),
          ],
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: (_isFetchingRate ||
                      _isSavingCurrency ||
                      _hasUnsavedCurrencyChanges)
                  ? null
                  : _fetchAndSaveRate,
              icon: _isFetchingRate
                  ? const SizedBox(
                      height: 14,
                      width: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh, size: 16),
              label: Text(_isFetchingRate ? '取得中...' : '今すぐ更新'),
            ),
          ),
        ],
      ),
    );
  }

  /// Frankfurter APIからレートを取得してDBに保存
  Future<void> _fetchAndSaveRate() async {
    if (_isFetchingRate || _selectedCurrency == 'JPY') return;
    setState(() => _isFetchingRate = true);
    try {
      final rate = await FxFetchService.fetchJpyRate(_selectedCurrency);
      if (!mounted) return;
      if (rate != null) {
        final updated = await _settingsRepo.updateLastRate(rate);
        if (mounted) {
          setState(() => _currentSettings = updated);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'レートを更新しました: 1 $_selectedCurrency = ${rate.toStringAsFixed(2)} JPY',
              ),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('レートの取得に失敗しました。手動レートを使用します'),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('レートの取得に失敗しました')),
        );
      }
    } finally {
      if (mounted) setState(() => _isFetchingRate = false);
    }
  }

  /// 通貨設定セクション
  Widget _buildCurrencySection() {
    const currencyLabels = {
      'JPY': 'JPY (¥)',
      'USD': 'USD (\$)',
      'AUD': 'AUD (A\$)',
      'EUR': 'EUR (€)',
      'GBP': 'GBP (£)',
    };

    return Card(
      margin: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacingMd,
        vertical: AppTheme.spacingSm,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacingMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.currency_exchange,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: AppTheme.spacingSm),
                Text(
                  '表示通貨設定',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
            const SizedBox(height: AppTheme.spacingXs),
            Text(
              '金額の表示通貨を変更します。保存値はJPY基準のまま維持されます。',
              style: TextStyle(fontSize: 12, color: AppTheme.subtleText),
            ),
            const SizedBox(height: AppTheme.spacingMd),
            // 通貨選択ドロップダウン
            DropdownButtonFormField<String>(
              initialValue: _selectedCurrency,
              decoration: const InputDecoration(
                labelText: '表示通貨',
                prefixIcon: Icon(Icons.language),
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
                        if (v == 'JPY') {
                          _rateController.clear();
                        }
                      }
                    },
            ),
            // JPY以外の場合にモード選択とレート入力を表示
            if (_selectedCurrency != 'JPY') ...[
              const SizedBox(height: AppTheme.spacingMd),
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
                  ),
                ],
                selected: {_selectedFxMode},
                onSelectionChanged: _isSavingCurrency
                    ? null
                    : (selected) {
                        setState(() => _selectedFxMode = selected.first);
                      },
              ),
              if (_selectedFxMode == 'auto') ...[
                const SizedBox(height: AppTheme.spacingMd),
                // 自動モード情報パネル
                _buildAutoRateInfo(),
              ],
              const SizedBox(height: AppTheme.spacingMd),
              TextFormField(
                controller: _rateController,
                decoration: InputDecoration(
                  labelText: '為替レート',
                  helperText: '1 ${MoneyFormatter.symbol(_selectedCurrency)} = ? JPY',
                  hintText: '例: 150.5',
                ),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                ],
              ),
            ],
            const SizedBox(height: AppTheme.spacingMd),
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
              ? 'このカテゴリを使用中の取引または定期支出ルールがあるため削除できません'
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

  // ─── 定期支出セクション ───

  /// 定期支出管理セクション
  Widget _buildRecurringSection() {
    return Card(
      margin: const EdgeInsets.symmetric(
        horizontal: AppTheme.spacingMd,
        vertical: AppTheme.spacingSm,
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppTheme.spacingMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.event_repeat,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: AppTheme.spacingSm),
                Text(
                  '定期支出',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  tooltip: '定期支出を追加',
                  onPressed: _isSaving ? null : () => _showRecurringRuleDialog(),
                ),
              ],
            ),
            const SizedBox(height: AppTheme.spacingXs),
            Text(
              '定期的な支出を登録すると、ホーム表示時に自動で取引が作成されます。',
              style: TextStyle(fontSize: 12, color: AppTheme.subtleText),
            ),
            if (_recurringRules.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppTheme.spacingMd),
                child: Center(
                  child: Text(
                    '定期支出ルールはありません',
                    style: TextStyle(color: AppTheme.subtleText),
                  ),
                ),
              )
            else
              ..._recurringRules.map((rule) => _buildRecurringRuleTile(rule)),
          ],
        ),
      ),
    );
  }

  /// 定期支出ルール1件の表示
  Widget _buildRecurringRuleTile(RecurringRule rule) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        rule.isActive ? Icons.repeat : Icons.repeat_one,
        color: rule.isActive
            ? Theme.of(context).colorScheme.primary
            : AppTheme.subtleText,
      ),
      title: Text(
        rule.categoryName ?? '不明',
        style: TextStyle(
          color: rule.isActive ? null : AppTheme.subtleText,
          decoration: rule.isActive ? null : TextDecoration.lineThrough,
        ),
      ),
      subtitle: Text(
        '¥${rule.amount} / ${rule.frequencyLabel}'
        '${rule.memo != null && rule.memo!.isNotEmpty ? '  ${rule.memo}' : ''}',
        style: TextStyle(fontSize: 12, color: AppTheme.subtleText),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 有効/無効トグル
          Switch(
            value: rule.isActive,
            onChanged: _isSaving
                ? null
                : (value) => _toggleRecurringRule(rule, value),
          ),
          // 編集ボタン
          IconButton(
            icon: const Icon(Icons.edit, size: 20),
            tooltip: '編集',
            onPressed: _isSaving
                ? null
                : () => _showRecurringRuleDialog(existing: rule),
          ),
          // 削除ボタン（destructive）
          IconButton(
            icon: Icon(
              Icons.delete_outline,
              size: 20,
              color: Theme.of(context).colorScheme.error,
            ),
            tooltip: '削除',
            onPressed: _isSaving ? null : () => _deleteRecurringRule(rule),
          ),
        ],
      ),
    );
  }

  /// 定期支出ルール削除（既存生成済み取引は通常取引として保持）
  Future<void> _deleteRecurringRule(RecurringRule rule) async {
    if (_isSaving) return;

    // 確認ダイアログ
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text(SettingsScreen.recurringRuleDeleteDialogTitle),
          content:
              const Text(SettingsScreen.recurringRuleDeleteDialogMessage),
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

    if (confirmed != true || !mounted) return;

    setState(() => _isSaving = true);
    try {
      await _recurringRepo.deleteRule(rule.id);
      if (!mounted) return;
      await _load();
    } catch (e) {
      if (mounted) {
        await handleError(
          context: context,
          error: e,
          debugLabel: '定期支出ルール削除エラー',
          userMessage: '定期支出ルールの削除に失敗しました',
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// 定期支出ルールの有効/無効を切り替え
  Future<void> _toggleRecurringRule(RecurringRule rule, bool isActive) async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      if (isActive) {
        await _recurringRepo.activate(rule.id);
      } else {
        await _recurringRepo.deactivate(rule.id);
      }
      await _load();
    } catch (e) {
      if (mounted) {
        await handleError(
          context: context,
          error: e,
          debugLabel: '定期支出ルール更新エラー',
          userMessage: '定期支出ルールの更新に失敗しました',
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  /// 定期支出ルール追加/編集ダイアログ
  Future<void> _showRecurringRuleDialog({RecurringRule? existing}) async {
    if (_isSaving) return;

    // 支出カテゴリのみ使用可能
    final categories = _expenseCategories;
    if (categories.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('先に支出カテゴリを追加してください')),
      );
      return;
    }

    final formKey = GlobalKey<FormState>();
    final amountController = TextEditingController(
      text: existing?.amount.toString() ?? '',
    );
    final memoController = TextEditingController(text: existing?.memo ?? '');
    final intervalController = TextEditingController(
      text: existing?.frequencyInterval.toString() ?? '1',
    );

    String? selectedCategoryId = existing?.categoryId ?? categories.first.id;
    String selectedUnit = existing?.frequencyUnit ?? 'month';
    DateTime selectedStartDate = existing?.startDate ?? DateTime.now();
    DateTime? selectedEndDate = existing?.endDate;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(existing == null ? '定期支出追加' : '定期支出編集'),
              content: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // カテゴリ選択
                      DropdownButtonFormField<String>(
                        initialValue: selectedCategoryId,
                        decoration: const InputDecoration(
                          labelText: 'カテゴリ',
                          border: OutlineInputBorder(),
                        ),
                        items: categories.map((c) {
                          return DropdownMenuItem(
                            value: c.id,
                            child: Text(c.name),
                          );
                        }).toList(),
                        onChanged: (v) {
                          setDialogState(() => selectedCategoryId = v);
                        },
                        validator: (v) =>
                            v == null ? 'カテゴリを選択してください' : null,
                      ),
                      const SizedBox(height: AppTheme.spacingMd),
                      // 金額
                      TextFormField(
                        controller: amountController,
                        decoration: const InputDecoration(
                          labelText: '金額',
                          prefixText: '¥',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        validator: (v) {
                          if (v == null || v.isEmpty) return '金額を入力してください';
                          final n = int.tryParse(v);
                          if (n == null || n < 0) return '正の整数を入力してください';
                          return null;
                        },
                      ),
                      const SizedBox(height: AppTheme.spacingMd),
                      // メモ
                      TextFormField(
                        controller: memoController,
                        decoration: const InputDecoration(
                          labelText: 'メモ（任意）',
                          hintText: '例: Netflix',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: AppTheme.spacingMd),
                      // 頻度: ユニット選択
                      DropdownButtonFormField<String>(
                        initialValue: selectedUnit,
                        decoration: const InputDecoration(
                          labelText: '頻度',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'week', child: Text('毎週')),
                          DropdownMenuItem(value: 'month', child: Text('毎月')),
                          DropdownMenuItem(value: 'year', child: Text('毎年')),
                        ],
                        onChanged: (v) {
                          if (v != null) {
                            setDialogState(() => selectedUnit = v);
                          }
                        },
                      ),
                      const SizedBox(height: AppTheme.spacingMd),
                      // 頻度: 間隔
                      TextFormField(
                        controller: intervalController,
                        decoration: const InputDecoration(
                          labelText: '間隔',
                          helperText: '例: 2 = 2週/2月/2年ごと',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        validator: (v) {
                          if (v == null || v.isEmpty) return '間隔を入力してください';
                          final n = int.tryParse(v);
                          if (n == null || n < 1) return '1以上を入力してください';
                          return null;
                        },
                      ),
                      const SizedBox(height: AppTheme.spacingMd),
                      // 開始日
                      InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: selectedStartDate,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) {
                            setDialogState(() => selectedStartDate = picked);
                          }
                        },
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: '開始日',
                            border: OutlineInputBorder(),
                            suffixIcon: Icon(Icons.calendar_today),
                          ),
                          child: Text(
                            '${selectedStartDate.year}/${selectedStartDate.month.toString().padLeft(2, '0')}/${selectedStartDate.day.toString().padLeft(2, '0')}',
                          ),
                        ),
                      ),
                      const SizedBox(height: AppTheme.spacingMd),
                      // 終了日（任意）
                      InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: selectedEndDate ?? selectedStartDate,
                            firstDate: selectedStartDate,
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) {
                            setDialogState(() => selectedEndDate = picked);
                          }
                        },
                        child: InputDecorator(
                          decoration: InputDecoration(
                            labelText: '終了日（任意）',
                            border: const OutlineInputBorder(),
                            suffixIcon: selectedEndDate != null
                                ? IconButton(
                                    icon: const Icon(Icons.clear),
                                    onPressed: () {
                                      setDialogState(
                                          () => selectedEndDate = null);
                                    },
                                  )
                                : const Icon(Icons.calendar_today),
                          ),
                          child: Text(
                            selectedEndDate != null
                                ? '${selectedEndDate!.year}/${selectedEndDate!.month.toString().padLeft(2, '0')}/${selectedEndDate!.day.toString().padLeft(2, '0')}'
                                : '未設定',
                          ),
                        ),
                      ),
                    ],
                  ),
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
                      Navigator.pop(context, {
                        'categoryId': selectedCategoryId,
                        'amount': int.parse(amountController.text),
                        'memo': memoController.text.trim().isEmpty
                            ? null
                            : memoController.text.trim(),
                        'frequencyUnit': selectedUnit,
                        'frequencyInterval':
                            int.parse(intervalController.text),
                        'startDate': selectedStartDate,
                        'endDate': selectedEndDate,
                      });
                    }
                  },
                  child: const Text('保存'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == null) return;

    setState(() => _isSaving = true);
    try {
      if (existing == null) {
        await _recurringRepo.create(
          categoryId: result['categoryId'] as String,
          amount: result['amount'] as int,
          memo: result['memo'] as String?,
          frequencyUnit: result['frequencyUnit'] as String,
          frequencyInterval: result['frequencyInterval'] as int,
          startDate: result['startDate'] as DateTime,
          endDate: result['endDate'] as DateTime?,
        );
      } else {
        await _recurringRepo.update(
          id: existing.id,
          categoryId: result['categoryId'] as String,
          amount: result['amount'] as int,
          memo: result['memo'] as String?,
          frequencyUnit: result['frequencyUnit'] as String,
          frequencyInterval: result['frequencyInterval'] as int,
          startDate: result['startDate'] as DateTime,
          endDate: result['endDate'] as DateTime?,
          isActive: existing.isActive,
        );
      }
      await _load();
    } catch (e) {
      if (mounted) {
        await handleError(
          context: context,
          error: e,
          debugLabel: '定期支出ルール保存エラー',
          userMessage: '定期支出ルールの保存に失敗しました',
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
      return EmptyStateView(
        icon: Icons.category_outlined,
        title: 'カテゴリがありません',
        subtitle: 'カテゴリを追加して取引を分類しましょう',
        actionLabel: 'カテゴリを追加',
        onAction: _isSaving ? null : () => _showCategoryDialog(type: type),
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
                icon: Icon(
                  Icons.delete_outline,
                  color: Theme.of(context).colorScheme.error,
                ),
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
          ? const LoadingView(message: '読み込み中...')
          : _errorMessage != null
              ? ErrorStateView(
                  message: _errorMessage!,
                  onRetry: _load,
                )
              : Column(
              children: [
                // 通貨設定セクション（スクロール可能）
                Expanded(
                  child: CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(child: _buildCurrencySection()),
                      // 定期支出セクション
                      SliverToBoxAdapter(child: _buildRecurringSection()),
                      // カテゴリ管理セクションヘッダー
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(
                            AppTheme.spacingMd,
                            AppTheme.spacingSm,
                            AppTheme.spacingMd,
                            AppTheme.spacingXs,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.category_outlined,
                                size: 20,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              const SizedBox(width: AppTheme.spacingSm),
                              Text(
                                'カテゴリ管理',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: TabBar(
                          controller: _tabController,
                          tabs: const [
                            Tab(text: '支出カテゴリ'),
                            Tab(text: '収入カテゴリ'),
                          ],
                        ),
                      ),
                      SliverFillRemaining(
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
