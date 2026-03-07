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
| 6 | `20260301000000_add_retention_policy.sql` | ルート | データ保持ポリシー（retention_config + expired_at + retention_logs） |
| 7 | `20260301100000_add_retention_functions.sql` | ルート | 保持ポリシーSQL関数群（dry_run / expire / purge / monthly_run） |

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

## データ保持ポリシー (Step 11)

Supabase無料枠での長期運用に向け、取引データの保持年数を管理し、2段階削除（期限切れ化 → 猶予後の物理削除）を導入しています。

### ポリシー概要
- **保持期間**: Free運用 5年 / Paid運用 10年（`retention_config` テーブルで管理）
- **対象**: `transactions` テーブルのみ（カテゴリ等のマスタは対象外）
- **2段階削除**:
  1. 期限切れ化: `expired_at` にタイムスタンプを設定（通常画面から非表示になるが、データは残存）
  2. 物理削除: 猶予期間（デフォルト90日）経過後に DELETE
- **物理削除済みデータは自動復元しない**（必要ならバックアップ復元で対応）

### 運用手順（Supabase SQL Editor で実行）

```sql
-- 1. 現在の設定確認
SELECT * FROM retention_config;

-- 2. Dry-run（対象件数の事前確認、データ変更なし）
--    expire/purge/rehydrate の各対象件数を返す
SELECT * FROM retention_dry_run();

-- 3. 期限切れ化の実行（内部で rehydrate を先に実行）
SELECT * FROM retention_expire();

-- 4. 物理削除の実行（猶予期間超過分のみ）
SELECT * FROM retention_purge();

-- 5. 実行ログの確認
SELECT * FROM retention_logs ORDER BY executed_at DESC;

-- 一括実行（rehydrate → dry_run → expire → purge を順番に実行）
SELECT * FROM retention_run_monthly();
```

### 保持年数の変更

```sql
-- Free → Paid 切替時
UPDATE retention_config SET retention_years = 10 WHERE id = 1;

-- 変更後の影響確認（rehydrate_target_count で復帰対象件数を確認）
SELECT * FROM retention_dry_run();

-- 既に期限切れ化されたデータのうち、新しいポリシーで保持対象になるデータを復帰
SELECT * FROM retention_rehydrate();
```

> **注意**: 保持年数を延長した場合、`retention_rehydrate()` を実行することで、
> 既に期限切れ化されたが新ポリシーでは保持期間内のデータが自動的に復帰します。
> `retention_expire()` や `retention_run_monthly()` は内部で自動的に `rehydrate` を実行するため、
> 通常の月次運用では明示的な呼び出しは不要です。

### 月次定期実行

#### Supabase Pro 以上（pg_cron 利用可能）

```sql
-- 毎月1日 AM3:00 (UTC) に自動実行
SELECT cron.schedule(
  'retention-monthly',
  '0 3 1 * *',
  $$SELECT public.retention_run_monthly()$$
);

-- ジョブの確認
SELECT * FROM cron.job;

-- 実行履歴の確認
SELECT * FROM cron.job_run_details ORDER BY start_time DESC LIMIT 10;

-- ジョブの削除
SELECT cron.unschedule('retention-monthly');
```

#### Supabase Free（手動実行）

毎月1回、SQL Editor から以下を実行してください:

```sql
SELECT * FROM retention_run_monthly();
SELECT * FROM retention_logs ORDER BY executed_at DESC LIMIT 5;
```

#### 実行失敗時

`retention_logs` の `success = false` のレコードを確認し、`error_message` を参照してください。
再実行は安全です（冪等性あり）。

### セキュリティ
- 全関数は `SECURITY DEFINER` + `REVOKE EXECUTE` + `SET search_path` で一般ユーザーからの直接呼び出しを遮断
- `retention_config` は認証済みユーザーの SELECT のみ許可
- `retention_logs` は RLS ポリシーなし（service_role のみ操作可）

## レシートOCR入力補助 (Step 12)

レシート画像から店名と合計金額を自動抽出し、支出入力の手間を削減します。

### 使い方
1. 支出追加画面で「レシート読み取り」ボタンをタップ
2. 「カメラで撮影」または「写真から選択」を選ぶ
3. OCR処理後、読み取り結果の確認ダイアログが表示される
4. 内容を確認し「適用する」をタップ → 単価・メモに自動反映
5. 必要に応じて内容を修正して保存

### 反映先
- **合計金額** → 単価フィールド（個数は1）
- **店名** → メモフィールド

### 仕様
- **オンデバイス処理**: 画像は端末外に送信・保存されません
- **対応言語**: 日本語レシートに最適化（google_mlkit_text_recognition使用）
- **対象項目**: 店名・合計金額のみ（明細行の自動分割は非対応）
- **信頼度表示**: 高/中/低の3段階で抽出精度を表示
- **1日上限**: 30回/日（ソフトリミット、アプリ再起動でリセット）

### 失敗時の動作
- OCR失敗・抽出失敗: SnackBarで通知し、手入力を継続可能
- 権限拒否: 画像取得がキャンセルされ、手入力にフォールバック
- 低信頼度: 確認ダイアログで警告表示し、適用後の確認を促す

### 確認手順
```bash
flutter analyze   # 静的解析
flutter test      # 全テスト（221テスト）
```

## レシートOCR Web対応・精度改善 (Step 13)

Step 12 のOCR機能をWebブラウザにも対応させ、抽出精度を改善しました。

### Web対応
- **ブラウザ内OCR**: tesseract.js を使用し、画像データを外部に送信せずにブラウザ内で処理
- **写真選択のみ**: Web版ではカメラ撮影は利用不可（画像ファイルの選択のみ）
- **初回利用時**: 日本語言語データ（約15MB）をダウンロード（2回目以降はキャッシュ済み）

### 精度改善
- **bbox活用**: OCRエンジンが返す位置・サイズ情報（bounding box）を活用したスコアリング
- **店名抽出**: 上位25%の位置 + フォントサイズ（bbox.height）で優先度を判定
- **合計金額抽出**: キーワード同一行最優先、右側近傍の金額を第2優先
- **除外強化**: 和暦日付（令和/平成）、10桁以上の連番（レシート番号等）を除外

### アーキテクチャ
- **3層構成**: OcrEngine（インフラ） / 抽出ロジック（純粋関数） / ReceiptOcrService（オーケストレーション）
- **条件付きインポート**: Mobile（ML Kit）/ Web（tesseract.js）をビルド時に自動切替
- **フォールバック**: bbox情報がない場合はテキストベースの既存ロジックを使用

### 確認手順
```bash
flutter analyze   # 静的解析
flutter test      # 全テスト（236テスト）
```

## Web画像取得の信頼性改善 (Step 14)

Webでレシート画像取得が失敗しやすい問題を解消し、失敗時の原因をUIで区別できるようにしました。

### 画像取得アダプタ
- **プラットフォーム別アダプタ**: OcrEngine と同じ条件付きインポートパターンで画像取得を分離
- **Mobile**: 従来の ImagePicker 経由（カメラ/ギャラリー選択、権限チェック）
- **Web**: ファイル形式チェック（JPEG/PNG、先頭バイト判定）＋サイズ上限チェック（10MB）

### 失敗分類とUIメッセージ
- **browserBlocked**: ブラウザ制約でファイル選択を開始できない場合
- **fileReadError**: 画像の読み込みに失敗した場合（ファイル破損等）
- **unsupportedFormat**: JPEG/PNG以外の画像を選択した場合
- **fileTooLarge**: 10MBを超える画像を選択した場合
- **permissionDenied**: カメラ/写真ライブラリへのアクセスが拒否された場合
- **unknown**: 未分類のエラー
- 各失敗時に「再試行」ボタン付き SnackBar を表示（permissionDenied は専用ダイアログ）

### 匿名メトリクス
- 失敗種別カウンタ（`debugPrint` ベース、PII非保存）

### 確認手順
```bash
flutter analyze   # 静的解析
flutter test      # 全テスト（277テスト）
flutter build web # Webビルド
```

## トラブルシューティング

### RLS 42501 エラー（カテゴリ追加/取引保存が失敗する）

「権限エラーが発生しました」または「セッションの有効期限が切れました」と表示される場合:

1. **セッション切れの場合**: 再ログインしてください
2. **セッション有効なのに 42501 の場合**: DBスキーマのドリフト（migration未適用）が原因です
   - 上記の「migration 適用確認」クエリを実行し、`column_default` が `auth.uid()` になっているか確認
   - 未設定の場合は `20260216000000_alter_user_id_defaults_and_composite_fk.sql` を再適用してください
