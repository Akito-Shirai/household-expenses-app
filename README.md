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

以下のSQLを Supabase SQL Editor で順番に実行してください。

> **配置場所**: migration ファイルは2箇所に分かれています。
> - リポジトリルート: `supabase/migrations/` — テーブル定義・スキーマ変更・トリガー
> - アプリ配下: `household-expenses-app/supabase/migrations/` — アプリ固有の設定テーブル

| # | ファイル | 配置場所 | 内容 |
|---|---------|---------|------|
| 1 | `20260215000000_create_categories_and_transactions.sql` | ルート | テーブル定義 + RLS + トリガー |
| 2 | `20260216000000_alter_user_id_defaults_and_composite_fk.sql` | ルート | 既存環境への差分適用（default / 複合FK） |
| 3 | `20260216100000_create_user_settings.sql` | アプリ配下 | ユーザー設定テーブル（表示通貨・為替レート） |
| 4 | `20260228000000_add_unit_price_and_quantity.sql` | ルート | 単価・個数カラム追加 + 既存データバックフィル |
| 5 | `20260228100000_seed_default_categories.sql` | ルート | 初期カテゴリ自動投入（トリガー + 既存ユーザーバックフィル） |

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
flutter test      # 全テスト（104テスト）
```

## 取引削除 (Step 7)

取引編集画面から登録済み取引を削除できます。

### 操作手順
1. ホーム画面の取引一覧から対象取引をタップして編集画面を開く
2. AppBar右上の削除アイコン（ゴミ箱）をタップ
3. 確認ダイアログで「削除」をタップ
4. ホーム画面に戻り、一覧とサマリーが即時更新される

### 仕様
- 削除ボタンは**編集時のみ**表示（新規追加画面では非表示）
- 削除前に必ず確認ダイアログを表示（誤操作防止）
- 保存中・削除中は操作が無効化される（二重送信防止）
- 削除失敗時は既存エラーハンドリング方針に従い通知（認証切れ時は再ログイン導線）

## 支出の単価・個数入力 (Step 8)

支出登録時に「単価」と「個数」を分けて入力でき、合計金額が自動計算されます。

### 入力仕様
- **支出**: 単価と個数を入力 → 合計金額（= 単価 × 個数）が自動計算・表示
- **収入**: 従来どおり金額を直接入力
- 新規支出の個数はデフォルト `1`（従来の単発購入と同じ手間）

### データ設計
- `transactions` テーブルに `unit_price`（nullable）と `quantity`（default 1, check >= 1）を追加
- 集計・一覧・通貨換算は既存の `amount` カラムを基準とし、回帰なし

### マイグレーション
4. `20260228000000_add_unit_price_and_quantity.sql` — 単価・個数カラム追加 + 既存データバックフィル

### 確認手順
```bash
flutter analyze   # 静的解析
flutter test      # 全テスト（145テスト）
```

## 初期カテゴリ自動設定 (Step 9)

ユーザー作成時にデフォルトカテゴリが自動で作成されます。

### 初期カテゴリ一覧
- **支出（6件）**: 食費、水道光熱費、家賃、交通費、通信費、医療費
- **収入（2件）**: 給与、賞与

### 仕様
- 新規ユーザー登録時に `auth.users` トリガーで自動投入
- 既存ユーザーにはマイグレーション適用時にバックフィル（欠落分のみ補完）
- 初期カテゴリは通常カテゴリと同じ扱い（編集・削除可能）
- 同名・同タイプのカテゴリが既に存在する場合はスキップ（重複防止）

### セキュリティ
- `seed_default_categories()` / `on_auth_user_created()` は `REVOKE EXECUTE` で `anon` / `authenticated` からの直接呼び出しを禁止
- トリガー経由（`SECURITY DEFINER`）でのみ実行される

### 確認手順
```bash
flutter analyze   # 静的解析
flutter test      # 全テスト（157テスト）
```

DB側の検証手順（トリガー発火・冪等性・バックフィル）は `docs/tasks/step9_default_categories.md` の「SQL検証手順」セクションを参照してください。

## 分析グラフ (Step 10)

ホーム画面のAppBarにあるグラフアイコンから分析画面へ遷移できます。

### 機能
- **粒度切替**: 日別 / 月別 / 年別をセグメントボタンで切り替え
- **期間ナビゲーション**: 前後の月/年へ移動
- **カテゴリフィルタ**: 複数カテゴリを選択して絞り込み（チップで適用中フィルタを可視化）
- **棒グラフ**: 支出（赤）/ 収入（青）を並列表示（fl_chart使用）
- **合計カード**: フィルタ適用後の支出合計・収入合計・収支を表示

### 集計仕様
- 集計は `transactions.amount` を基準にクライアント側で実行
- グラフと合計カードは同一フィルタ条件で集計（整合性保証）
- 日別: 指定月内の各日をバケット化
- 月別: 指定年内の各月をバケット化（直近12ヶ月）
- 年別: 直近5年分のデータをバケット化

### 確認手順
```bash
flutter analyze   # 静的解析
flutter test      # 全テスト
```

## トラブルシューティング

### RLS 42501 エラー（カテゴリ追加/取引保存が失敗する）

「権限エラーが発生しました」または「セッションの有効期限が切れました」と表示される場合:

1. **セッション切れの場合**: 再ログインしてください
2. **セッション有効なのに 42501 の場合**: DBスキーマのドリフト（migration未適用）が原因です
   - 上記の「migration 適用確認」クエリを実行し、`column_default` が `auth.uid()` になっているか確認
   - 未設定の場合は `20260216000000_alter_user_id_defaults_and_composite_fk.sql` を再適用してください
