import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:household_mvp/screens/login_screen.dart';

void main() {
  testWidgets('LoginScreen にメール・パスワード入力欄と送信ボタンが表示される', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    // メールアドレス入力欄の存在確認
    expect(find.text('メールアドレス'), findsOneWidget);

    // パスワード入力欄の存在確認
    expect(find.text('パスワード'), findsOneWidget);

    // ログインボタンの存在確認
    expect(find.text('ログイン'), findsWidgets);

    // 切替リンクの存在確認
    expect(find.text('アカウントをお持ちでない方はこちら'), findsOneWidget);
  });

  testWidgets('サインアップモードに切り替えできる', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    // 切替ボタンをタップ
    await tester.tap(find.text('アカウントをお持ちでない方はこちら'));
    await tester.pump();

    // サインアップモードに変わっていること
    expect(find.text('サインアップ'), findsWidgets);
    expect(find.text('すでにアカウントをお持ちの方はこちら'), findsOneWidget);
  });

  testWidgets('空欄送信でバリデーションエラーが表示される', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    // ログインボタンをタップ（入力なし）
    await tester.tap(find.widgetWithText(FilledButton, 'ログイン'));
    await tester.pump();

    // バリデーションエラーの確認
    expect(find.text('メールアドレスを入力してください'), findsOneWidget);
    expect(find.text('パスワードを入力してください'), findsOneWidget);
  });
}
