# household_mvp

家計簿MVPアプリ（Flutter + Supabase）

## セットアップ

```bash
flutter pub get
```

## 実行

Supabase の URL と Anon Key を `--dart-define` で渡して起動します。

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://<your-project>.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=<your-anon-key>
```

## テスト

```bash
flutter test
```

## 静的解析

```bash
flutter analyze
```

## フォーマット

```bash
dart format .
```

## Supabase migration 適用

`supabase/migrations/` 配下のSQLを Supabase SQL Editor で順番に実行してください。

1. `20260215000000_create_categories_and_transactions.sql` — テーブル定義 + RLS + トリガー
2. `20260216000000_alter_user_id_defaults_and_composite_fk.sql` — 既存環境への差分適用（default / 複合FK）

### migration 適用確認

以下のクエリで `user_id` の default と RLS policy を確認できます。

```sql
-- user_id default の確認（auth.uid() が設定されていること）
select table_name, column_name, column_default
from information_schema.columns
where table_schema = 'public'
  and table_name in ('categories', 'transactions')
  and column_name = 'user_id';

-- RLS policy の確認
select tablename, policyname, cmd, qual, with_check
from pg_policies
where schemaname = 'public'
  and tablename in ('categories', 'transactions')
order by tablename, policyname;
```

## トラブルシューティング

### RLS 42501 エラー（カテゴリ追加/取引保存が失敗する）

「権限エラーが発生しました」または「セッションの有効期限が切れました」と表示される場合:

1. **セッション切れの場合**: 再ログインしてください
2. **セッション有効なのに 42501 の場合**: DBスキーマのドリフト（migration未適用）が原因です
   - 上記の「migration 適用確認」クエリを実行し、`column_default` が `auth.uid()` になっているか確認
   - 未設定の場合は `20260216000000_alter_user_id_defaults_and_composite_fk.sql` を再適用してください
