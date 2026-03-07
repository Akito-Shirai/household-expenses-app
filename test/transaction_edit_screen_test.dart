import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:household_mvp/models/transaction.dart';
import 'package:household_mvp/models/user_settings.dart';
import 'package:household_mvp/repositories/transaction_repository.dart';
import 'package:household_mvp/screens/transaction_edit_screen.dart';
import 'package:household_mvp/services/image_pick/image_pick_adapter.dart';
import 'package:household_mvp/models/ocr_token.dart';
import 'package:household_mvp/services/ocr_engine/ocr_engine.dart';
import 'package:household_mvp/services/receipt_ocr_service.dart';
import 'package:household_mvp/utils/fx_converter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// ─── テスト用モック ───

/// テスト用モック画像アダプタ（固定の PickImageResult を返す）
class _MockImagePickAdapter implements ImagePickAdapter {
  final PickImageResult result;
  _MockImagePickAdapter(this.result);

  @override
  Future<PickImageResult> pickImage(ImageSource source) async => result;

  @override
  void dispose() {}
}

/// 呼び出しごとに異なる結果を返すモック画像アダプタ
class _SequentialMockImagePickAdapter implements ImagePickAdapter {
  final List<PickImageResult> results;
  int _callCount = 0;
  _SequentialMockImagePickAdapter(this.results);

  @override
  Future<PickImageResult> pickImage(ImageSource source) async {
    final result = results[_callCount % results.length];
    _callCount++;
    return result;
  }

  @override
  void dispose() {}
}

/// テスト用モックOCRエンジン（常に利用可能、空トークンを返す）
class _MockOcrEngine implements OcrEngine {
  @override
  bool get isAvailable => true;

  @override
  Future<List<OcrToken>> recognizeFromBytes(Uint8List imageBytes) async => [];

  @override
  void dispose() {}
}

/// TransactionEditScreenの主要ロジック（バリデーション・通貨表示・削除導線・OCRフロー）のテスト。
/// 画面全体はSupabase依存のため、ロジック・UIパーツ単位でテストする。
/// OCRフロー: 実画面の TransactionEditScreen を pumpWidget し、DI済み
/// imagePickAdapter / ocrEngine / imageSourceSelector をモック注入して
/// 各 PickImageStatus に対する UI分岐（SnackBar・ダイアログ・無表示）を検証する。
void main() {
  group('取引編集: 金額バリデーションロジック', () {
    // _save()内のバリデーション相当のロジックを抽出テスト
    String? validateAmount(String? value) {
      if (value == null || value.trim().isEmpty) {
        return '金額を入力してください';
      }
      final amount = int.tryParse(value.trim());
      if (amount == null || amount < 0) {
        return '0以上の整数を入力してください';
      }
      return null;
    }

    test('空入力でエラーメッセージ', () {
      expect(validateAmount(''), '金額を入力してください');
      expect(validateAmount(null), '金額を入力してください');
      expect(validateAmount('   '), '金額を入力してください');
    });

    test('正の整数は通過', () {
      expect(validateAmount('100'), isNull);
      expect(validateAmount('0'), isNull);
      expect(validateAmount('999999'), isNull);
    });

    test('負数はエラー', () {
      expect(validateAmount('-1'), '0以上の整数を入力してください');
      expect(validateAmount('-100'), '0以上の整数を入力してください');
    });

    test('小数・文字列はエラー', () {
      expect(validateAmount('12.5'), '0以上の整数を入力してください');
      expect(validateAmount('abc'), '0以上の整数を入力してください');
    });
  });

  group('取引編集: カテゴリバリデーション', () {
    String? validateCategory(String? value) {
      return value == null ? 'カテゴリを選択してください' : null;
    }

    test('未選択でエラー', () {
      expect(validateCategory(null), 'カテゴリを選択してください');
    });

    test('選択済みで通過', () {
      expect(validateCategory('cat-1'), isNull);
    });
  });

  group('取引編集: 通貨記号表示', () {
    test('JPY設定で¥記号', () {
      expect(MoneyFormatter.symbol('JPY'), '¥');
    });

    test('USD設定で\$記号', () {
      expect(MoneyFormatter.symbol('USD'), '\$');
    });

    test('EUR設定で€記号', () {
      expect(MoneyFormatter.symbol('EUR'), '€');
    });

    test('GBP設定で£記号', () {
      expect(MoneyFormatter.symbol('GBP'), '£');
    });

    test('AUD設定でA\$記号', () {
      expect(MoneyFormatter.symbol('AUD'), 'A\$');
    });
  });

  group('取引編集: 保存中状態のUI', () {
    testWidgets('FilledButtonが無効化時にテキスト変更', (tester) async {
      // 保存中ボタンの見た目テスト（独立したウィジェット）
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                // 通常状態
                FilledButton(
                  onPressed: () {},
                  child: const Text('追加する'),
                ),
                // 保存中状態
                const FilledButton(
                  onPressed: null,
                  child: SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('追加する'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('種別切替SegmentedButtonが表示される', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SegmentedButton<String>(
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
              selected: const {'expense'},
              onSelectionChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('支出'), findsOneWidget);
      expect(find.text('収入'), findsOneWidget);
    });
  });

  group('取引編集: 削除ボタン表示条件', () {
    testWidgets('編集モードで削除アイコンが表示される', (tester) async {
      // 編集モード相当: AppBarにdelete_outlineアイコンが存在
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              title: const Text('取引編集'),
              actions: [
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: '削除',
                  onPressed: () {},
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.delete_outline), findsOneWidget);
      expect(find.byTooltip('削除'), findsOneWidget);
    });

    testWidgets('新規追加モードで削除アイコンが表示されない', (tester) async {
      // 新規モード相当: AppBarにdeleteアイコンなし
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              title: const Text('取引追加'),
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.delete_outline), findsNothing);
    });
  });

  group('取引編集: 削除確認ダイアログ', () {
    testWidgets('確認ダイアログにキャンセルと削除ボタンが表示される', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => FilledButton(
              onPressed: () {
                showDialog<bool>(
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
                            backgroundColor:
                                Theme.of(context).colorScheme.error,
                          ),
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('削除'),
                        ),
                      ],
                    );
                  },
                );
              },
              child: const Text('テスト'),
            ),
          ),
        ),
      );

      // ダイアログを開く
      await tester.tap(find.text('テスト'));
      await tester.pumpAndSettle();

      expect(find.text('取引削除'), findsOneWidget);
      expect(find.text('この取引を削除しますか？'), findsOneWidget);
      expect(find.text('キャンセル'), findsOneWidget);
      expect(find.text('削除'), findsOneWidget);
    });

    testWidgets('キャンセルタップでダイアログが閉じる', (tester) async {
      var dialogResult = true;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => FilledButton(
              onPressed: () async {
                final result = await showDialog<bool>(
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
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('削除'),
                        ),
                      ],
                    );
                  },
                );
                dialogResult = result ?? false;
              },
              child: const Text('テスト'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('テスト'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('キャンセル'));
      await tester.pumpAndSettle();

      // キャンセルでfalseが返る
      expect(dialogResult, isFalse);
      // ダイアログが閉じている
      expect(find.text('取引削除'), findsNothing);
    });
  });

  group('取引編集: 削除後のサマリー更新', () {
    test('取引削除後のサマリーが正しく再計算される', () {
      final before = [
        Transaction(
          id: '1', userId: 'u', date: DateTime(2026, 2, 1),
          type: 'expense', amount: 1000, categoryId: 'c1',
          categoryName: '食費', createdAt: DateTime.now(), updatedAt: DateTime.now(),
        ),
        Transaction(
          id: '2', userId: 'u', date: DateTime(2026, 2, 2),
          type: 'expense', amount: 500, categoryId: 'c1',
          categoryName: '食費', createdAt: DateTime.now(), updatedAt: DateTime.now(),
        ),
        Transaction(
          id: '3', userId: 'u', date: DateTime(2026, 2, 3),
          type: 'income', amount: 3000, categoryId: 'c2',
          categoryName: '給与', createdAt: DateTime.now(), updatedAt: DateTime.now(),
        ),
      ];

      final summaryBefore = TransactionRepository.summarize(before);
      expect(summaryBefore.totalExpense, 1500);
      expect(summaryBefore.net, 1500);

      // id=1の取引を削除した状態をシミュレート
      final after = before.where((tx) => tx.id != '1').toList();
      final summaryAfter = TransactionRepository.summarize(after);
      expect(summaryAfter.totalExpense, 500);
      expect(summaryAfter.totalIncome, 3000);
      expect(summaryAfter.net, 2500);
      expect(summaryAfter.expenseByCategory['食費'], 500);
    });

    test('全取引削除後のサマリーはゼロ', () {
      final summary = TransactionRepository.summarize([]);
      expect(summary.totalExpense, 0);
      expect(summary.totalIncome, 0);
      expect(summary.net, 0);
      expect(summary.expenseByCategory, isEmpty);
    });

    test('唯一の取引を削除した場合のカテゴリ別集計', () {
      final transactions = [
        Transaction(
          id: '1', userId: 'u', date: DateTime(2026, 2, 1),
          type: 'expense', amount: 1000, categoryId: 'c1',
          categoryName: '食費', createdAt: DateTime.now(), updatedAt: DateTime.now(),
        ),
      ];

      final summaryBefore = TransactionRepository.summarize(transactions);
      expect(summaryBefore.expenseByCategory['食費'], 1000);

      // 削除後
      final summaryAfter = TransactionRepository.summarize([]);
      expect(summaryAfter.expenseByCategory['食費'], isNull);
    });
  });

  group('取引編集: 単価バリデーションロジック', () {
    String? validateUnitPrice(String? value) {
      if (value == null || value.trim().isEmpty) {
        return '単価を入力してください';
      }
      final price = int.tryParse(value.trim());
      if (price == null || price < 0) {
        return '0以上の整数を入力してください';
      }
      return null;
    }

    test('空入力でエラー', () {
      expect(validateUnitPrice(''), '単価を入力してください');
      expect(validateUnitPrice(null), '単価を入力してください');
    });

    test('0以上の整数は通過', () {
      expect(validateUnitPrice('0'), isNull);
      expect(validateUnitPrice('100'), isNull);
      expect(validateUnitPrice('9999'), isNull);
    });

    test('負数はエラー', () {
      expect(validateUnitPrice('-1'), '0以上の整数を入力してください');
    });

    test('小数・文字列はエラー', () {
      expect(validateUnitPrice('12.5'), '0以上の整数を入力してください');
      expect(validateUnitPrice('abc'), '0以上の整数を入力してください');
    });
  });

  group('取引編集: 個数バリデーションロジック', () {
    String? validateQuantity(String? value) {
      if (value == null || value.trim().isEmpty) {
        return '個数を入力してください';
      }
      final qty = int.tryParse(value.trim());
      if (qty == null || qty < 1) {
        return '1以上の整数を入力してください';
      }
      return null;
    }

    test('空入力でエラー', () {
      expect(validateQuantity(''), '個数を入力してください');
      expect(validateQuantity(null), '個数を入力してください');
    });

    test('1以上の整数は通過', () {
      expect(validateQuantity('1'), isNull);
      expect(validateQuantity('10'), isNull);
      expect(validateQuantity('999'), isNull);
    });

    test('0はエラー', () {
      expect(validateQuantity('0'), '1以上の整数を入力してください');
    });

    test('負数はエラー', () {
      expect(validateQuantity('-1'), '1以上の整数を入力してください');
    });

    test('小数・文字列はエラー', () {
      expect(validateQuantity('1.5'), '1以上の整数を入力してください');
      expect(validateQuantity('abc'), '1以上の整数を入力してください');
    });
  });

  group('取引編集: 合計金額の自動計算ロジック', () {
    int calculateAmount(String unitPriceStr, String quantityStr) {
      final unitPrice = int.tryParse(unitPriceStr.trim()) ?? 0;
      final quantity = int.tryParse(quantityStr.trim()) ?? 1;
      return unitPrice * quantity;
    }

    test('単価×個数で合計が計算される', () {
      expect(calculateAmount('100', '3'), 300);
      expect(calculateAmount('250', '2'), 500);
      expect(calculateAmount('1000', '1'), 1000);
    });

    test('単価0の場合は合計0', () {
      expect(calculateAmount('0', '5'), 0);
    });

    test('個数1（デフォルト）の場合は単価がそのまま合計', () {
      expect(calculateAmount('500', '1'), 500);
    });

    test('空文字の場合のフォールバック', () {
      expect(calculateAmount('', '1'), 0);
      expect(calculateAmount('100', ''), 100);
      expect(calculateAmount('', ''), 0);
    });
  });

  group('取引編集: 日付フォーマット', () {
    test('日付がゼロ埋めで表示される', () {
      final date = DateTime(2026, 2, 5);
      final formatted =
          '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
      expect(formatted, '2026/02/05');
    });

    test('12月31日のフォーマット', () {
      final date = DateTime(2026, 12, 31);
      final formatted =
          '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
      expect(formatted, '2026/12/31');
    });
  });

  // ─── H-1対応: OCRフロー 実画面 Widget テスト ───

  group('取引編集: OCRフロー 実画面テスト（TransactionEditScreen pumpWidget）', () {
    // TransactionEditScreen を直接 pumpWidget し、DI済みモックで
    // _startOcr → pickImage → UI分岐 の実フロー回帰を検証する。

    setUpAll(() async {
      // テスト用にSupabaseを初期化（ダミー接続先）
      // _loadCategories は失敗するが、エラーハンドラが catch してフォーム表示に遷移する
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      try {
        await Supabase.initialize(
          url: 'https://test.supabase.co',
          anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.'
              'eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRlc3QiLCJyb2xlIjoiYW5vbiIs'
              'ImlhdCI6MTYyMDAwMDAwMCwiZXhwIjoxOTM1NjAwMDAwfQ.'
              'test_signature',
        );
      } catch (_) {
        // 既に初期化済みの場合は無視
      }
    });

    /// 指定ステータスを返すモックアダプタ付きの実画面を構築
    Widget buildScreen(PickImageResult pickResult) {
      return MaterialApp(
        home: TransactionEditScreen(
          userSettings: UserSettings.defaults('test-user'),
          imagePickAdapter: _MockImagePickAdapter(pickResult),
          ocrEngine: _MockOcrEngine(),
          // ImageSourceDialog をスキップし、直接 gallery を返す
          imageSourceSelector: (_) async => ImageSource.gallery,
        ),
      );
    }

    /// カテゴリ読み込み失敗を待ち、フォーム表示に遷移させるヘルパー
    Future<void> waitForFormReady(WidgetTester tester) async {
      // _loadCategories の非同期処理（ネットワークエラー）を消化
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      // カテゴリ読み込みエラーのSnackBarをクリア（後続テストとの干渉防止）
      final messenger = tester.state<ScaffoldMessengerState>(
        find.byType(ScaffoldMessenger),
      );
      messenger.clearSnackBars();
      await tester.pump();
    }

    /// OCRボタンタップ後、非同期チェーン（imageSourceSelector → pickImage → UI更新）を消化
    /// pumpAndSettle は SnackBar の自動消去タイマーまで進めてしまうため、
    /// 個別 pump で非同期完了 + SnackBar表示アニメーションだけ進める
    Future<void> tapOcrAndSettle(WidgetTester tester) async {
      await tester.tap(find.text('レシート読み取り'));
      // 非同期チェーン解決 + SnackBarアニメーション用に十分な pump
      for (int i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('browserBlocked: SnackBar文言 + 再試行表示', (tester) async {
      await tester.pumpWidget(buildScreen(
        const PickImageResult(PickImageStatus.browserBlocked),
      ));
      await waitForFormReady(tester);
      await tapOcrAndSettle(tester);

      expect(
        find.text(PickImageStatus.browserBlocked.defaultMessage),
        findsOneWidget,
      );
      expect(find.text('再試行'), findsOneWidget);
    });

    testWidgets('fileReadError: SnackBar文言 + 再試行表示', (tester) async {
      await tester.pumpWidget(buildScreen(
        const PickImageResult(PickImageStatus.fileReadError),
      ));
      await waitForFormReady(tester);
      await tapOcrAndSettle(tester);

      expect(
        find.text(PickImageStatus.fileReadError.defaultMessage),
        findsOneWidget,
      );
      expect(find.text('再試行'), findsOneWidget);
    });

    testWidgets('unsupportedFormat: SnackBar文言 + 再試行表示', (tester) async {
      await tester.pumpWidget(buildScreen(
        const PickImageResult(PickImageStatus.unsupportedFormat),
      ));
      await waitForFormReady(tester);
      await tapOcrAndSettle(tester);

      expect(
        find.text(PickImageStatus.unsupportedFormat.defaultMessage),
        findsOneWidget,
      );
      expect(find.text('再試行'), findsOneWidget);
    });

    testWidgets('fileTooLarge: SnackBar文言 + 再試行表示', (tester) async {
      await tester.pumpWidget(buildScreen(
        const PickImageResult(PickImageStatus.fileTooLarge),
      ));
      await waitForFormReady(tester);
      await tapOcrAndSettle(tester);

      expect(
        find.text(PickImageStatus.fileTooLarge.defaultMessage),
        findsOneWidget,
      );
      expect(find.text('再試行'), findsOneWidget);
    });

    testWidgets('unknown: SnackBar文言 + 再試行表示', (tester) async {
      await tester.pumpWidget(buildScreen(
        const PickImageResult(PickImageStatus.unknown),
      ));
      await waitForFormReady(tester);
      await tapOcrAndSettle(tester);

      expect(
        find.text(PickImageStatus.unknown.defaultMessage),
        findsOneWidget,
      );
      expect(find.text('再試行'), findsOneWidget);
    });

    testWidgets('permissionDenied: 権限ダイアログ表示', (tester) async {
      await tester.pumpWidget(buildScreen(
        const PickImageResult(PickImageStatus.permissionDenied),
      ));
      await waitForFormReady(tester);
      await tapOcrAndSettle(tester);

      // 権限ダイアログの要素を検証
      expect(find.text('カメラ/写真へのアクセス'), findsOneWidget);
      expect(find.text('手入力で続ける'), findsOneWidget);
      expect(find.text('設定を開く'), findsOneWidget);
    });

    testWidgets('canceled: 通知なし（SnackBar・ダイアログとも表示されない）',
        (tester) async {
      await tester.pumpWidget(buildScreen(
        const PickImageResult(PickImageStatus.canceled),
      ));
      await waitForFormReady(tester);
      await tapOcrAndSettle(tester);

      // エラー系SnackBarが表示されない（カテゴリ読み込みエラーのSnackBarは除外して検証）
      expect(find.text('カメラ/写真へのアクセス'), findsNothing);
      expect(find.text(PickImageStatus.browserBlocked.defaultMessage), findsNothing);
      expect(find.text(PickImageStatus.unknown.defaultMessage), findsNothing);
    });

    testWidgets('success: OCR処理開始（エラー表示なし）', (tester) async {
      await tester.pumpWidget(buildScreen(
        PickImageResult(
          PickImageStatus.success,
          imageBytes: Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]),
        ),
      ));
      await waitForFormReady(tester);
      await tapOcrAndSettle(tester);

      // エラー系のSnackBar・ダイアログは表示されない
      expect(find.text('カメラ/写真へのアクセス'), findsNothing);
      expect(find.text(PickImageStatus.browserBlocked.defaultMessage), findsNothing);
    });

    testWidgets('errorDetail設定時: カスタムメッセージが優先表示される',
        (tester) async {
      await tester.pumpWidget(buildScreen(
        const PickImageResult(
          PickImageStatus.fileTooLarge,
          errorDetail: '画像サイズが大きすぎます（15.2MB）。10MB以下の画像を選択してください。',
        ),
      ));
      await waitForFormReady(tester);
      await tapOcrAndSettle(tester);

      expect(
        find.text('画像サイズが大きすぎます（15.2MB）。10MB以下の画像を選択してください。'),
        findsOneWidget,
      );
      expect(find.text('再試行'), findsOneWidget);
    });

    testWidgets('連続browserBlocked: 2回目で強調メッセージに切り替わる',
        (tester) async {
      final adapter = _SequentialMockImagePickAdapter([
        const PickImageResult(PickImageStatus.browserBlocked),
        const PickImageResult(PickImageStatus.browserBlocked),
      ]);
      await tester.pumpWidget(MaterialApp(
        home: TransactionEditScreen(
          userSettings: UserSettings.defaults('test-user'),
          imagePickAdapter: adapter,
          ocrEngine: _MockOcrEngine(),
          imageSourceSelector: (_) async => ImageSource.gallery,
        ),
      ));
      await waitForFormReady(tester);

      // 1回目: 通常の browserBlocked メッセージ
      await tapOcrAndSettle(tester);
      expect(
        find.text(PickImageStatus.browserBlocked.defaultMessage),
        findsOneWidget,
      );

      // SnackBar をクリアして2回目
      final messenger = tester.state<ScaffoldMessengerState>(
        find.byType(ScaffoldMessenger),
      );
      messenger.clearSnackBars();
      await tester.pump();

      // 2回目: 強調メッセージ
      await tapOcrAndSettle(tester);
      expect(
        find.text(
          'ブラウザの制約により画像選択が繰り返し失敗しています。'
          '別のブラウザで試すか、手入力で続けてください。',
        ),
        findsOneWidget,
      );
    });

    testWidgets('fileTooLarge後のbrowserBlocked: 連続カウントされない（通常文言）',
        (tester) async {
      final adapter = _SequentialMockImagePickAdapter([
        const PickImageResult(PickImageStatus.fileTooLarge),
        const PickImageResult(PickImageStatus.browserBlocked),
      ]);
      await tester.pumpWidget(MaterialApp(
        home: TransactionEditScreen(
          userSettings: UserSettings.defaults('test-user'),
          imagePickAdapter: adapter,
          ocrEngine: _MockOcrEngine(),
          imageSourceSelector: (_) async => ImageSource.gallery,
        ),
      ));
      await waitForFormReady(tester);

      // 1回目: fileTooLarge
      await tapOcrAndSettle(tester);
      expect(
        find.text(PickImageStatus.fileTooLarge.defaultMessage),
        findsOneWidget,
      );

      // SnackBar をクリアして2回目
      final messenger = tester.state<ScaffoldMessengerState>(
        find.byType(ScaffoldMessenger),
      );
      messenger.clearSnackBars();
      await tester.pump();

      // 2回目: browserBlocked だが初回なので通常メッセージ
      await tapOcrAndSettle(tester);
      expect(
        find.text(PickImageStatus.browserBlocked.defaultMessage),
        findsOneWidget,
      );
      // 強調メッセージは表示されない
      expect(
        find.text(
          'ブラウザの制約により画像選択が繰り返し失敗しています。'
          '別のブラウザで試すか、手入力で続けてください。',
        ),
        findsNothing,
      );
    });

    testWidgets('permissionDenied: 「手入力で続ける」タップでダイアログが閉じる',
        (tester) async {
      await tester.pumpWidget(buildScreen(
        const PickImageResult(PickImageStatus.permissionDenied),
      ));
      await waitForFormReady(tester);
      await tapOcrAndSettle(tester);
      expect(find.text('カメラ/写真へのアクセス'), findsOneWidget);

      // 「手入力で続ける」タップ
      await tester.tap(find.text('手入力で続ける'));
      await tester.pumpAndSettle();

      // ダイアログが閉じている
      expect(find.text('カメラ/写真へのアクセス'), findsNothing);
    });
  });
}
