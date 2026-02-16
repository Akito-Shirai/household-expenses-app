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
3. `20260216100000_create_user_settings.sql` — ユーザー設定テーブル（表示通貨・為替レート）

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

## 通貨設定

### 表示通貨の変更

設定画面の「表示通貨設定」セクションで、金額の表示通貨を変更できます。

- **対応通貨**: JPY (¥), USD ($), AUD (A$), EUR (€), GBP (£)
- **為替レート**: 手動で設定します（例: 1 USD = 150 JPY の場合、`150` と入力）
- **保存値**: すべての金額はJPY基準で保存されます。表示時にのみ換算されます

### 手動レート運用

1. 設定画面を開く
2. 表示通貨を選択（例: USD）
3. 為替レートを入力（例: `150.5`）— 「1 表示通貨 = ? JPY」の形式
4. 「通貨設定を保存」をタップ
5. ホーム画面に戻ると、金額が選択通貨で表示されます

> レート未設定の場合はJPY表示にフォールバックし、SnackBarで通知されます。

## UI/UX改善 (Step 6)

Step 6 で以下のUI改善が適用されています:

### デザイン基盤
- `lib/theme/app_theme.dart` にカラートークン・スペーシング・テーマを一元管理
- Material 3 テーマ（`ColorScheme.fromSeed`）を全画面で共有

### 状態表示の標準化
- `lib/widgets/state_views.dart` に共通部品（LoadingView / EmptyStateView / ErrorStateView）
- 全画面でローディング・空状態・エラー表示が統一

### 画面別改善
- **ホーム**: 収支を最上部に大きく強調、カテゴリ別内訳の色分け
- **取引編集**: フォームにprefixIcon追加、保存中の入力無効化、バリデーション明確化
- **設定**: 通貨設定/カテゴリ管理のセクション分離、アイコン付きヘッダー
- **ログイン**: prefixIcon追加

### 確認手順
```bash
flutter analyze   # 静的解析
flutter test      # 全テスト（60テスト）
```

## トラブルシューティング

### RLS 42501 エラー（カテゴリ追加/取引保存が失敗する）

「権限エラーが発生しました」または「セッションの有効期限が切れました」と表示される場合:

1. **セッション切れの場合**: 再ログインしてください
2. **セッション有効なのに 42501 の場合**: DBスキーマのドリフト（migration未適用）が原因です
   - 上記の「migration 適用確認」クエリを実行し、`column_default` が `auth.uid()` になっているか確認
   - 未設定の場合は `20260216000000_alter_user_id_defaults_and_composite_fk.sql` を再適用してください
