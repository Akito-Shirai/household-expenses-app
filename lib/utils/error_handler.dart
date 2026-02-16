import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../main.dart';

/// PostgrestException が RLS違反 (42501) かどうかを判定
bool isRlsViolation(Object error) {
  return error is PostgrestException && error.code == '42501';
}

/// エラーに応じたSnackBarを表示する。
/// RLS違反の場合はセッション状態に応じて分岐する。
/// 戻り値: サインアウトを実行した場合 true
Future<bool> handleError({
  required BuildContext context,
  required Object error,
  required String debugLabel,
  required String userMessage,
}) async {
  debugPrint('$debugLabel: $error');

  if (!context.mounted) return false;

  if (isRlsViolation(error)) {
    final hasSession = supabase.auth.currentSession != null;

    if (hasSession) {
      // セッション有りで 42501 → RLSポリシー/権限設定の問題
      debugPrint('$debugLabel: セッション有りで RLS違反。ポリシー設定を確認してください。');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('権限エラーが発生しました。管理者にお問い合わせください。')),
      );
      return false;
    }

    // セッション無しで 42501 → セッション切れ
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('セッションの有効期限が切れました。再度ログインしてください。')),
    );
    await supabase.auth.signOut();
    return true;
  }

  ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(userMessage)));
  return false;
}
