import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:household_mvp/widgets/state_views.dart';

void main() {
  group('LoadingView', () {
    testWidgets('CircularProgressIndicatorが表示される', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: LoadingView())),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('メッセージが指定時に表示される', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: LoadingView(message: '読み込み中...')),
        ),
      );
      expect(find.text('読み込み中...'), findsOneWidget);
    });

    testWidgets('メッセージなしの場合はテキストが表示されない', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: LoadingView())),
      );
      // CircularProgressIndicatorのみ
      expect(find.byType(Text), findsNothing);
    });
  });

  group('EmptyStateView', () {
    testWidgets('アイコンとタイトルが表示される', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EmptyStateView(
              icon: Icons.receipt_long_outlined,
              title: 'データがありません',
            ),
          ),
        ),
      );
      expect(find.byIcon(Icons.receipt_long_outlined), findsOneWidget);
      expect(find.text('データがありません'), findsOneWidget);
    });

    testWidgets('サブタイトルが指定時に表示される', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EmptyStateView(
              icon: Icons.receipt_long_outlined,
              title: 'データがありません',
              subtitle: '追加しましょう',
            ),
          ),
        ),
      );
      expect(find.text('追加しましょう'), findsOneWidget);
    });

    testWidgets('アクションボタンが指定時に表示される', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EmptyStateView(
              icon: Icons.receipt_long_outlined,
              title: 'データがありません',
              actionLabel: '追加する',
              onAction: () => tapped = true,
            ),
          ),
        ),
      );
      expect(find.text('追加する'), findsOneWidget);
      await tester.tap(find.text('追加する'));
      expect(tapped, isTrue);
    });

    testWidgets('アクションボタンなしの場合はFilledButtonが表示されない', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EmptyStateView(
              icon: Icons.receipt_long_outlined,
              title: 'データがありません',
            ),
          ),
        ),
      );
      expect(find.byType(FilledButton), findsNothing);
    });
  });

  group('ErrorStateView', () {
    testWidgets('エラーメッセージが表示される', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ErrorStateView(message: '読み込みに失敗しました'),
          ),
        ),
      );
      expect(find.text('読み込みに失敗しました'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('リトライボタンが指定時に表示・動作する', (tester) async {
      var retried = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ErrorStateView(
              message: 'エラーです',
              onRetry: () => retried = true,
            ),
          ),
        ),
      );
      expect(find.text('再読み込み'), findsOneWidget);
      await tester.tap(find.text('再読み込み'));
      expect(retried, isTrue);
    });

    testWidgets('リトライなしの場合はOutlinedButtonが表示されない', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ErrorStateView(message: 'エラーです'),
          ),
        ),
      );
      expect(find.byType(OutlinedButton), findsNothing);
    });
  });
}
