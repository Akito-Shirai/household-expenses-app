import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../main.dart';
import '../models/category.dart';
import '../models/receipt_ocr_result.dart';
import '../models/transaction.dart' as model;
import '../models/user_settings.dart';
import '../repositories/category_repository.dart';
import '../repositories/transaction_repository.dart';
import '../services/image_pick/image_pick_adapter.dart';
import '../services/ocr_engine/ocr_engine.dart';
import '../services/receipt_ocr_service.dart';
import '../theme/app_theme.dart';
import '../utils/error_handler.dart';
import '../utils/fx_converter.dart';
import '../widgets/image_source_dialog.dart';
import '../widgets/receipt_ocr_result_dialog.dart';
import '../widgets/state_views.dart';

/// 取引の作成/編集画面
class TransactionEditScreen extends StatefulWidget {
  /// 編集対象（nullなら新規作成）
  final model.Transaction? existing;

  /// 通貨設定（表示通貨の記号表示に使用）
  final UserSettings userSettings;

  /// テスト用: 画像取得アダプタの注入
  @visibleForTesting
  final ImagePickAdapter? imagePickAdapter;

  /// テスト用: OCRエンジンの注入
  @visibleForTesting
  final OcrEngine? ocrEngine;

  /// テスト用: 画像ソース選択の注入（ImageSourceDialog.show を差し替え可能にする）
  @visibleForTesting
  final Future<ImageSource?> Function(BuildContext)? imageSourceSelector;

  const TransactionEditScreen({
    super.key,
    this.existing,
    required this.userSettings,
    this.imagePickAdapter,
    this.ocrEngine,
    this.imageSourceSelector,
  });

  @override
  State<TransactionEditScreen> createState() => _TransactionEditScreenState();
}

class _TransactionEditScreenState extends State<TransactionEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _unitPriceController = TextEditingController();
  final _quantityController = TextEditingController();
  final _memoController = TextEditingController();
  final _catRepo = CategoryRepository(supabase);
  final _txRepo = TransactionRepository(supabase);

  String _type = 'expense';
  DateTime _date = DateTime.now();
  String? _selectedCategoryId;
  List<Category> _categories = [];
  bool _isLoading = false;
  bool _isSaving = false;
  bool _isOcrProcessing = false;

  bool get _isEditing => widget.existing != null;
  bool get _isExpense => _type == 'expense';

  /// 支出の合計金額（単価 × 個数）
  int get _calculatedAmount {
    final unitPrice = int.tryParse(_unitPriceController.text.trim()) ?? 0;
    final quantity = int.tryParse(_quantityController.text.trim()) ?? 1;
    return unitPrice * quantity;
  }

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
      _memoController.text = tx.memo ?? '';

      if (tx.type == 'expense') {
        // 支出: 単価・個数を復元（unit_price未設定の既存データはamountを初期単価として補完）
        _unitPriceController.text =
            (tx.unitPrice ?? tx.amount).toString();
        _quantityController.text = tx.quantity.toString();
      } else {
        // 収入: 従来の金額入力
        _amountController.text = tx.amount.toString();
      }
    } else {
      // 新規作成: 個数のデフォルト値を1に設定
      _quantityController.text = '1';
    }
    _loadCategories();
  }

  @override
  void dispose() {
    _ocrEngine?.dispose();
    _imagePickAdapter?.dispose();
    _amountController.dispose();
    _unitPriceController.dispose();
    _quantityController.dispose();
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
      final memo = _memoController.text.trim();

      if (_isExpense) {
        // 支出: 単価×個数で保存
        final unitPrice = int.parse(_unitPriceController.text.trim());
        final quantity = int.parse(_quantityController.text.trim());
        final amount = unitPrice * quantity;

        if (_isEditing) {
          await _txRepo.update(
            id: widget.existing!.id,
            categoryId: _selectedCategoryId!,
            date: _date,
            amount: amount,
            type: _type,
            unitPrice: unitPrice,
            quantity: quantity,
            memo: memo.isEmpty ? null : memo,
          );
        } else {
          await _txRepo.create(
            categoryId: _selectedCategoryId!,
            date: _date,
            amount: amount,
            type: _type,
            unitPrice: unitPrice,
            quantity: quantity,
            memo: memo.isEmpty ? null : memo,
          );
        }
      } else {
        // 収入: 従来の金額入力
        final amount = int.parse(_amountController.text.trim());

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

  // ─── レシートOCR ───

  OcrEngine? _ocrEngine;
  ImagePickAdapter? _imagePickAdapter;

  /// OCRエンジンを取得（DI or 遅延初期化）
  OcrEngine get _engine {
    _ocrEngine ??= widget.ocrEngine ?? createOcrEngine();
    return _ocrEngine!;
  }

  /// 画像取得アダプタを取得（DI or 遅延初期化）
  ImagePickAdapter get _picker {
    _imagePickAdapter ??= widget.imagePickAdapter ?? createImagePickAdapter();
    return _imagePickAdapter!;
  }

  /// OCRボタンを表示すべきか
  bool get _isOcrSupported => _engine.isAvailable;

  /// レシートOCRフローを開始
  Future<void> _startOcr() async {
    // 1日上限チェック
    if (ReceiptOcrService.isDailyLimitReached) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('本日のレシート読み取り上限に達しました')),
        );
      }
      return;
    }

    // 画像ソース選択（テスト時はDI経由で差し替え可能）
    final source = widget.imageSourceSelector != null
        ? await widget.imageSourceSelector!(context)
        : await ImageSourceDialog.show(context);
    if (source == null || !mounted) return;

    // 画像取得（アダプタ経由で理由を判別）
    final pickResult = await _picker.pickImage(source);
    if (!mounted) return;

    // 失敗種別を記録（匿名メトリクス、PII なし）
    ReceiptOcrService.recordPickFailure(pickResult.status);

    // 失敗時のUI分岐
    if (pickResult.status == PickImageStatus.canceled) return;

    if (pickResult.status == PickImageStatus.permissionDenied) {
      await _showPermissionDeniedDialog();
      return;
    }

    if (pickResult.status != PickImageStatus.success) {
      final message = pickResult.displayMessage!;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          action: pickResult.shouldShowRetry
              ? SnackBarAction(label: '再試行', onPressed: _startOcr)
              : null,
        ),
      );
      return;
    }

    final imageBytes = pickResult.imageBytes!;

    // OCR処理（Engine経由）
    setState(() => _isOcrProcessing = true);
    try {
      final result = await ReceiptOcrService.processImageBytes(
        imageBytes,
        _engine,
      );

      if (!mounted) return;
      setState(() => _isOcrProcessing = false);

      if (result == null || result.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('レシートを読み取れませんでした。手入力してください。')),
        );
        return;
      }

      // 結果確認ダイアログ
      final apply = await ReceiptOcrResultDialog.show(context, result);
      if (apply == true && mounted) {
        await _applyOcrResult(result);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isOcrProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('読み取り中にエラーが発生しました')),
        );
      }
    }
  }

  /// H-1: 権限拒否時のダイアログ（設定アプリ導線付き）
  Future<void> _showPermissionDeniedDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('カメラ/写真へのアクセス'),
        content: const Text(
          'レシート読み取りにはカメラまたは写真ライブラリへのアクセスが必要です。\n'
          '端末の「設定」からアクセスを許可してください。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('手入力で続ける'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            child: const Text('設定を開く'),
          ),
        ],
      ),
    );
  }

  /// OCR結果をフォームに反映（H-2: 既存値がある場合は確認）
  Future<void> _applyOcrResult(ReceiptOcrResult result) async {
    // H-2: 既存入力との競合チェック
    final hasExistingPrice = _unitPriceController.text.trim().isNotEmpty;
    final hasExistingQuantity =
        _quantityController.text.trim().isNotEmpty &&
        _quantityController.text.trim() != '1';
    final hasExistingMemo = _memoController.text.trim().isNotEmpty;

    if (hasExistingPrice || hasExistingQuantity || hasExistingMemo) {
      final overwrite = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('入力済みの値を上書き'),
          content: const Text(
            '既に入力されている値があります。\nレシートの読み取り結果で上書きしますか？',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('キャンセル'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('上書きする'),
            ),
          ],
        ),
      );
      if (overwrite != true || !mounted) return;
    }

    setState(() {
      // 金額を単価に反映
      if (result.totalAmount != null) {
        _unitPriceController.text = result.totalAmount.toString();
        // 個数は既存値を維持（上書きしない）
      }
      // 店名をメモに反映
      if (result.merchantName != null) {
        final currentMemo = _memoController.text.trim();
        if (currentMemo.isEmpty) {
          _memoController.text = result.merchantName!;
        } else {
          _memoController.text = '${result.merchantName!}\n$currentMemo';
        }
      }
    });
  }

  /// 支出用の金額入力ウィジェット（単価・個数・合計自動計算）
  Widget _buildExpenseAmountFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 単価
        TextFormField(
          controller: _unitPriceController,
          decoration: InputDecoration(
            labelText: '単価',
            prefixText: '$_currencySymbol ',
            helperText: widget.userSettings.displayCurrency != 'JPY'
                ? '※ 入力・保存はJPY基準です'
                : null,
          ),
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          enabled: !_isSaving,
          onChanged: (_) => setState(() {}),
          validator: (v) {
            if (v == null || v.trim().isEmpty) {
              return '単価を入力してください';
            }
            final price = int.tryParse(v.trim());
            if (price == null || price < 0) {
              return '0以上の整数を入力してください';
            }
            return null;
          },
        ),
        const SizedBox(height: AppTheme.spacingMd),

        // 個数
        TextFormField(
          controller: _quantityController,
          decoration: const InputDecoration(
            labelText: '個数',
            prefixIcon: Icon(Icons.inventory_2_outlined),
          ),
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          enabled: !_isSaving,
          onChanged: (_) => setState(() {}),
          validator: (v) {
            if (v == null || v.trim().isEmpty) {
              return '個数を入力してください';
            }
            final qty = int.tryParse(v.trim());
            if (qty == null || qty < 1) {
              return '1以上の整数を入力してください';
            }
            return null;
          },
        ),
        const SizedBox(height: AppTheme.spacingSm),

        // 合計金額（読み取り専用）
        InputDecorator(
          decoration: InputDecoration(
            labelText: '合計金額',
            prefixText: '$_currencySymbol ',
            filled: true,
            fillColor: Theme.of(context)
                .colorScheme
                .surfaceContainerHighest
                .withAlpha(128),
          ),
          child: Text(
            _calculatedAmount.toString(),
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
        ),
      ],
    );
  }

  /// 収入用の金額入力ウィジェット（従来の金額直接入力）
  Widget _buildIncomeAmountField() {
    return TextFormField(
      controller: _amountController,
      decoration: InputDecoration(
        labelText: '金額',
        prefixText: '$_currencySymbol ',
        helperText: widget.userSettings.displayCurrency != 'JPY'
            ? '※ 入力・保存はJPY基準です'
            : null,
      ),
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      enabled: !_isSaving,
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? '取引編集' : '取引追加'),
        actions: [
          if (_isEditing)
            IconButton(
              icon: Icon(
                Icons.delete_outline,
                color: Theme.of(context).colorScheme.error,
              ),
              tooltip: '削除',
              onPressed: _isSaving ? null : _delete,
            ),
        ],
      ),
      body: _isLoading
          ? const LoadingView(message: 'カテゴリを読み込み中...')
          : SingleChildScrollView(
              padding: const EdgeInsets.all(AppTheme.spacingMd),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 種別切替
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'expense',
                          label: Text('支出'),
                          icon: Icon(Icons.remove_circle_outline),
                        ),
                        ButtonSegment(
                          value: 'income',
                          label: Text('収入'),
                          icon: Icon(Icons.add_circle_outline),
                        ),
                      ],
                      selected: {_type},
                      onSelectionChanged: _isSaving
                          ? null
                          : (selected) {
                              setState(() {
                                _type = selected.first;
                                _selectedCategoryId = null;
                              });
                              _loadCategories();
                            },
                    ),
                    const SizedBox(height: AppTheme.spacingMd),

                    // 日付選択
                    InkWell(
                      onTap: _isSaving ? null : _pickDate,
                      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                      child: InputDecorator(
                        decoration: const InputDecoration(
                          labelText: '日付',
                          prefixIcon: Icon(Icons.calendar_today),
                        ),
                        child: Text(
                          '${_date.year}/${_date.month.toString().padLeft(2, '0')}/${_date.day.toString().padLeft(2, '0')}',
                        ),
                      ),
                    ),
                    const SizedBox(height: AppTheme.spacingMd),

                    // カテゴリ選択
                    DropdownButtonFormField<String>(
                      initialValue: _selectedCategoryId,
                      decoration: const InputDecoration(
                        labelText: 'カテゴリ',
                        prefixIcon: Icon(Icons.category_outlined),
                      ),
                      items: _categories
                          .map(
                            (c) => DropdownMenuItem<String>(
                              value: c.id,
                              child: Text(c.name),
                            ),
                          )
                          .toList(),
                      onChanged: _isSaving
                          ? null
                          : (v) => setState(() => _selectedCategoryId = v),
                      validator: (v) => v == null ? 'カテゴリを選択してください' : null,
                    ),
                    const SizedBox(height: AppTheme.spacingMd),

                    // レシート読み取りボタン（支出モード & OCR対応プラットフォーム）
                    if (_isExpense && _isOcrSupported) ...[
                      OutlinedButton.icon(
                        onPressed: (_isSaving || _isOcrProcessing)
                            ? null
                            : _startOcr,
                        icon: _isOcrProcessing
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.document_scanner_outlined),
                        label: Text(
                          _isOcrProcessing ? '読み取り中...' : 'レシート読み取り',
                        ),
                      ),
                      const SizedBox(height: AppTheme.spacingMd),
                    ],

                    // 金額入力（支出/収入で切替）
                    if (_isExpense)
                      _buildExpenseAmountFields()
                    else
                      _buildIncomeAmountField(),
                    const SizedBox(height: AppTheme.spacingMd),

                    // メモ
                    TextFormField(
                      controller: _memoController,
                      decoration: const InputDecoration(
                        labelText: 'メモ（任意）',
                        prefixIcon: Icon(Icons.notes),
                      ),
                      maxLines: 2,
                      enabled: !_isSaving,
                    ),
                    const SizedBox(height: AppTheme.spacingLg),

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
                          : Text(_isEditing ? '更新する' : '追加する'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
