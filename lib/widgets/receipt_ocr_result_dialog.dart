import 'package:flutter/material.dart';

import '../models/receipt_ocr_result.dart';
import '../theme/app_theme.dart';

/// OCR結果確認ダイアログ
///
/// 抽出された店名・合計金額を表示し、適用/再撮影/キャンセルを選択させる。
class ReceiptOcrResultDialog extends StatelessWidget {
  final ReceiptOcrResult result;

  const ReceiptOcrResultDialog({super.key, required this.result});

  /// ダイアログを表示し、適用する場合は true を返す
  static Future<bool?> show(BuildContext context, ReceiptOcrResult result) {
    return showDialog<bool>(
      context: context,
      builder: (_) => ReceiptOcrResultDialog(result: result),
    );
  }

  Color _confidenceColor(ConfidenceLevel level) {
    switch (level) {
      case ConfidenceLevel.high:
        return AppTheme.seedColor;
      case ConfidenceLevel.medium:
        return AppTheme.warningColor;
      case ConfidenceLevel.low:
        return AppTheme.expenseColor;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final level = result.confidenceLevel;

    return AlertDialog(
      title: const Text('読み取り結果'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 信頼度バッジ
          Row(
            children: [
              Icon(
                level == ConfidenceLevel.high
                    ? Icons.check_circle
                    : level == ConfidenceLevel.medium
                        ? Icons.info
                        : Icons.warning,
                size: 18,
                color: _confidenceColor(level),
              ),
              const SizedBox(width: AppTheme.spacingXs),
              Text(
                '信頼度: ${level.label}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: _confidenceColor(level),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppTheme.spacingMd),

          // 店名
          _ResultRow(
            label: '店名',
            value: result.merchantName ?? '(抽出できませんでした)',
            isEmpty: result.merchantName == null,
          ),
          const SizedBox(height: AppTheme.spacingSm),

          // 合計金額
          _ResultRow(
            label: '合計金額',
            value: result.totalAmount != null
                ? '${result.totalAmount} 円'
                : '(抽出できませんでした)',
            isEmpty: result.totalAmount == null,
          ),

          if (level == ConfidenceLevel.low) ...[
            const SizedBox(height: AppTheme.spacingMd),
            Text(
              '信頼度が低いため、適用後に内容をご確認ください。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppTheme.warningColor,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('キャンセル'),
        ),
        FilledButton(
          onPressed: result.isEmpty ? null : () => Navigator.pop(context, true),
          child: const Text('適用する'),
        ),
      ],
    );
  }
}

/// 結果行ウィジェット
class _ResultRow extends StatelessWidget {
  final String label;
  final String value;
  final bool isEmpty;

  const _ResultRow({
    required this.label,
    required this.value,
    required this.isEmpty,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: AppTheme.subtleText,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: isEmpty ? AppTheme.subtleText : null,
            fontStyle: isEmpty ? FontStyle.italic : null,
          ),
        ),
      ],
    );
  }
}
