import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart';
import '../models/category.dart';
import '../models/transaction.dart' as model;
import '../models/user_settings.dart';
import '../repositories/category_repository.dart';
import '../repositories/transaction_repository.dart';
import '../utils/error_handler.dart';
import '../utils/fx_converter.dart';

/// 取引の作成/編集画面
class TransactionEditScreen extends StatefulWidget {
  /// 編集対象（nullなら新規作成）
  final model.Transaction? existing;

  /// 通貨設定（表示通貨の記号表示に使用）
  final UserSettings userSettings;

  const TransactionEditScreen({
    super.key,
    this.existing,
    required this.userSettings,
  });

  @override
  State<TransactionEditScreen> createState() => _TransactionEditScreenState();
}

class _TransactionEditScreenState extends State<TransactionEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _memoController = TextEditingController();
  final _catRepo = CategoryRepository(supabase);
  final _txRepo = TransactionRepository(supabase);

  String _type = 'expense';
  DateTime _date = DateTime.now();
  String? _selectedCategoryId;
  List<Category> _categories = [];
  bool _isLoading = false;
  bool _isSaving = false;

  bool get _isEditing => widget.existing != null;

  /// 通貨記号（設定通貨に連動）
  String get _currencySymbol =>
      MoneyFormatter.symbol(widget.userSettings.displayCurrency);

  @override
  void initState() {
    super.initState();
    if (_isEditing) {
      final tx = widget.existing!;
      _type = tx.type;
      _date = tx.date;
      _selectedCategoryId = tx.categoryId;
      _amountController.text = tx.amount.toString();
      _memoController.text = tx.memo ?? '';
    }
    _loadCategories();
  }

  @override
  void dispose() {
    _amountController.dispose();
    _memoController.dispose();
    super.dispose();
  }

  Future<void> _loadCategories() async {
    setState(() => _isLoading = true);
    try {
      final cats = await _catRepo.list(_type);
      if (mounted) {
        setState(() {
          _categories = cats;
          // 選択中のカテゴリが新しいリストに無ければリセット
          if (_selectedCategoryId != null &&
              !cats.any((c) => c.id == _selectedCategoryId)) {
            _selectedCategoryId = cats.isNotEmpty ? cats.first.id : null;
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

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      setState(() => _date = picked);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCategoryId == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('カテゴリを選択してください')));
      return;
    }

    // H-7: type と category_id の整合チェック
    final selectedCat = _categories
        .where((c) => c.id == _selectedCategoryId)
        .firstOrNull;
    if (selectedCat == null || selectedCat.type != _type) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('カテゴリと種別が一致しません。カテゴリを再選択してください')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final amount = int.parse(_amountController.text.trim());
      final memo = _memoController.text.trim();

      if (_isEditing) {
        await _txRepo.update(
          id: widget.existing!.id,
          categoryId: _selectedCategoryId!,
          date: _date,
          amount: amount,
          type: _type,
          memo: memo.isEmpty ? null : memo,
        );
      } else {
        await _txRepo.create(
          categoryId: _selectedCategoryId!,
          date: _date,
          amount: amount,
          type: _type,
          memo: memo.isEmpty ? null : memo,
        );
      }

      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        await handleError(
          context: context,
          error: e,
          debugLabel: '取引保存エラー',
          userMessage: '取引の保存に失敗しました',
        );
      }
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('取引削除'),
          content: const Text('この取引を削除しますか？'),
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
      await _txRepo.delete(widget.existing!.id);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        await handleError(
          context: context,
          error: e,
          debugLabel: '取引削除エラー',
          userMessage: '取引の削除に失敗しました',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? '取引編集' : '取引追加'),
        actions: [
          if (_isEditing)
            IconButton(
              icon: const Icon(Icons.delete),
              tooltip: '削除',
              onPressed: _isSaving ? null : _delete,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 種別切替
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'expense', label: Text('支出')),
                        ButtonSegment(value: 'income', label: Text('収入')),
                      ],
                      selected: {_type},
                      onSelectionChanged: (selected) {
                        setState(() {
                          _type = selected.first;
                          _selectedCategoryId = null;
                        });
                        _loadCategories();
                      },
                    ),
                    const SizedBox(height: 16),

                    // 日付選択
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.calendar_today),
                      title: Text(
                        '${_date.year}/${_date.month.toString().padLeft(2, '0')}/${_date.day.toString().padLeft(2, '0')}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: _pickDate,
                    ),
                    const SizedBox(height: 16),

                    // カテゴリ選択
                    DropdownButtonFormField<String>(
                      initialValue: _selectedCategoryId,
                      decoration: const InputDecoration(
                        labelText: 'カテゴリ',
                        border: OutlineInputBorder(),
                      ),
                      items: _categories
                          .map(
                            (c) => DropdownMenuItem<String>(
                              value: c.id,
                              child: Text(c.name),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => setState(() => _selectedCategoryId = v),
                      validator: (v) => v == null ? 'カテゴリを選択してください' : null,
                    ),
                    const SizedBox(height: 16),

                    // 金額
                    TextFormField(
                      controller: _amountController,
                      decoration: InputDecoration(
                        labelText: '金額 (JPY)',
                        border: const OutlineInputBorder(),
                        prefixText: '$_currencySymbol ',
                        helperText: widget.userSettings.displayCurrency != 'JPY'
                            ? '※ 入力はJPY基準です'
                            : null,
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) {
                          return '金額を入力してください';
                        }
                        final amount = int.tryParse(v.trim());
                        if (amount == null || amount < 0) {
                          return '0以上の整数を入力してください';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),

                    // メモ
                    TextFormField(
                      controller: _memoController,
                      decoration: const InputDecoration(
                        labelText: 'メモ（任意）',
                        border: OutlineInputBorder(),
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 24),

                    // 保存ボタン
                    FilledButton(
                      onPressed: _isSaving ? null : _save,
                      child: _isSaving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : Text(_isEditing ? '更新' : '追加'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
